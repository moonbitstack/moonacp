//! Drive a MoonBit ACP agent over the official Rust SDK's HTTP transport.
//!
//! The harness starts the agent (`integration/http-acp`, which serves this library's ASGI
//! application on a port), connects with `HttpClient`, and runs a conversation the way an editor
//! would: `initialize`, `session/new`, a streamed `session/prompt`, a second prompt that is
//! cancelled, and `session/list`. Every answer is checked against what the agent said it would do.
//!
//! This is the one thing the transport's own tests cannot prove: that another implementation's
//! client, written against the same RFD, reaches this library's server and understands it.
//!
//! Usage: `rust-http-interop <agent executable> [args...]`

use std::process::{Child, Command, Stdio};
use std::time::{Duration, Instant};

use agent_client_protocol::{Channel, Client, ConnectTo, ConnectionDriver, TransportFrame};
use agent_client_protocol_http::HttpClient;
use futures::StreamExt as _;
use serde_json::{json, Value};
use tokio::time::timeout;

const DEADLINE: Duration = Duration::from_secs(20);

fn main() {
    let subscriber = tracing_subscriber::fmt()
        .with_max_level(if std::env::var("ACP_TRACE").is_ok() {
            tracing::Level::TRACE
        } else {
            tracing::Level::WARN
        })
        .finish();
    let _ = tracing::subscriber::set_global_default(subscriber);
    if let Err(report) = run() {
        eprintln!("FAILED: {report}");
        std::process::exit(1);
    }
}

fn run() -> Result<(), String> {
    let mut arguments = std::env::args().skip(1);
    let program = arguments
        .next()
        .ok_or("usage: rust-http-interop <agent executable> [args...]")?;
    let rest: Vec<String> = arguments.collect();
    let port = free_port()?;
    let mut child = spawn(&program, &rest, port)?;
    let result = drive(port, &mut child);
    let _ = child.kill();
    let _ = child.wait();
    result
}

/// A port the system handed out a moment ago and does not need any more.
fn free_port() -> Result<u16, String> {
    let listener = std::net::TcpListener::bind("127.0.0.1:0").map_err(|error| error.to_string())?;
    let port = listener
        .local_addr()
        .map_err(|error| error.to_string())?
        .port();
    drop(listener);
    Ok(port)
}

fn spawn(program: &str, arguments: &[String], port: u16) -> Result<Child, String> {
    Command::new(program)
        .args(arguments)
        .arg(port.to_string())
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit())
        .spawn()
        .map_err(|error| format!("cannot start {program}: {error}"))
}

/// Waits until something accepts a connection on the port, so a slow start is not a failure.
fn wait_for_server(port: u16) -> Result<(), String> {
    let deadline = Instant::now() + Duration::from_secs(20);
    while Instant::now() < deadline {
        if std::net::TcpStream::connect(("127.0.0.1", port)).is_ok() {
            return Ok(());
        }
        std::thread::sleep(Duration::from_millis(50));
    }
    Err(format!("nothing listened on 127.0.0.1:{port}"))
}

struct Peer {
    channel: Channel,
    driver: Option<tokio::task::JoinHandle<agent_client_protocol::Result<()>>>,
}

impl Peer {
    fn connect(client: HttpClient) -> Self {
        let (channel, driver): (Channel, Option<ConnectionDriver>) =
            ConnectTo::<Client>::into_channel_and_future(client);
        Self {
            channel,
            driver: Some(tokio::spawn(
                driver.expect("HttpClient owns its transport driver"),
            )),
        }
    }

    fn send(&self, value: Value) -> Result<(), String> {
        self.channel
            .tx
            .unbounded_send(TransportFrame::parse_json(&value.to_string()))
            .map_err(|error| error.to_string())
    }

    fn request(&self, id: u64, method: &str, params: Value) -> Result<(), String> {
        self.send(json!({ "jsonrpc": "2.0", "id": id, "method": method, "params": params }))
    }

    async fn next(&mut self) -> Result<Value, String> {
        let frame = match timeout(DEADLINE, self.channel.rx.next()).await {
            Ok(Some(frame)) => frame,
            Ok(None) => return Err(self.cause().await),
            Err(_) => return Err("the agent did not answer in time".to_string()),
        };
        let text = frame.to_json().map_err(|error| error.to_string())?;
        serde_json::from_str(&text).map_err(|error| error.to_string())
    }

    /// Why the transport stopped, read from the driver that stopped it.
    async fn cause(&mut self) -> String {
        match self.driver.take() {
            Some(driver) => match timeout(DEADLINE, driver).await {
                Ok(Ok(Ok(()))) => "the transport closed".to_string(),
                Ok(Ok(Err(error))) => format!("the transport failed: {error}"),
                Ok(Err(error)) => format!("the transport task failed: {error}"),
                Err(_) => "the transport did not stop".to_string(),
            },
            None => "the transport closed".to_string(),
        }
    }

    /// Reads until the answer with this identifier arrives, handing every notification it meets to
    /// `watch` in the order they came.
    async fn answer_to(
        &mut self,
        id: u64,
        mut watch: impl FnMut(&Value),
    ) -> Result<Value, String> {
        loop {
            let message = self.next().await?;
            if message.get("method").is_some() {
                watch(&message);
                continue;
            }
            if message["id"] == json!(id) {
                return Ok(message);
            }
        }
    }

    async fn close(mut self) -> Result<(), String> {
        drop(self.channel);
        match self.driver.take() {
            Some(driver) => timeout(DEADLINE, driver)
                .await
                .map_err(|_| "the transport did not finish".to_string())?
                .map_err(|error| error.to_string())?
                .map_err(|error| error.to_string()),
            None => Ok(()),
        }
    }
}

fn drive(port: u16, child: &mut Child) -> Result<(), String> {
    wait_for_server(port)?;
    let runtime = tokio::runtime::Runtime::new().map_err(|error| error.to_string())?;
    let outcome = runtime.block_on(converse(port));
    let _ = child.kill();
    outcome
}

async fn converse(port: u16) -> Result<(), String> {
    let endpoint = format!("http://127.0.0.1:{port}");
    let mut peer = Peer::connect(
        HttpClient::new(endpoint.clone()).map_err(|error| format!("{error:?}"))?,
    );

    peer.request(
        1,
        "initialize",
        json!({
            "protocolVersion": 1,
            "clientCapabilities": { "fs": { "readTextFile": true }, "terminal": false },
            "clientInfo": { "name": "rust-http-interop", "version": "0.1.0" },
        }),
    )?;
    let answer = peer.answer_to(1, |_| {}).await?;
    let result = &answer["result"];
    if result["protocolVersion"] != json!(1) {
        return Err(format!("initialize answered {result}"));
    }
    if result["agentCapabilities"]["loadSession"] != json!(true) {
        return Err(format!("the agent did not declare loadSession: {result}"));
    }
    if result["agentInfo"]["name"] != json!("slow") {
        return Err(format!("the agent did not name itself: {result}"));
    }
    println!("initialize: protocol 1, agent {}, loadSession", result["agentInfo"]["name"]);

    peer.request(2, "session/new", json!({ "cwd": "/work", "mcpServers": [] }))?;
    let started = peer.answer_to(2, |_| {}).await?;
    let session_id = started["result"]["sessionId"]
        .as_str()
        .ok_or_else(|| format!("session/new answered {started}"))?
        .to_string();
    println!("session/new: {session_id}");

    let mut streamed = String::new();
    peer.request(
        3,
        "session/prompt",
        json!({
            "sessionId": session_id,
            "prompt": [{ "type": "text", "text": "hello over HTTP" }],
        }),
    )?;
    let answer = peer
        .answer_to(3, |notification| {
            if notification["method"] == json!("session/update") {
                let update = &notification["params"]["update"];
                if update["sessionUpdate"] == json!("agent_message_chunk") {
                    if let Some(text) = update["content"]["text"].as_str() {
                        streamed.push_str(text);
                    }
                }
            }
        })
        .await?;
    if answer["result"]["stopReason"] != json!("end_turn") {
        return Err(format!("session/prompt answered {answer}"));
    }
    if streamed != "you said: hello over HTTP" {
        return Err(format!("the streamed answer was {streamed:?}"));
    }
    println!("session/prompt: two chunks, then end_turn, answer {streamed:?}");

    // A turn that is stopped while it runs still answers exactly once.
    peer.request(
        4,
        "session/prompt",
        json!({
            "sessionId": session_id,
            "prompt": [{ "type": "text", "text": "this one is cancelled" }],
        }),
    )?;
    let first = peer.next().await?;
    if first["method"] != json!("session/update") {
        return Err(format!("the turn did not stream before it was cancelled: {first}"));
    }
    peer.send(json!({
        "jsonrpc": "2.0",
        "method": "session/cancel",
        "params": { "sessionId": session_id },
    }))?;
    let answer = peer.answer_to(4, |_| {}).await?;
    if answer["result"]["stopReason"] != json!("cancelled") {
        return Err(format!("the cancelled turn answered {answer}"));
    }
    println!("session/cancel: the turn answered cancelled");

    // The stream of a session the agent has not named yet comes first, then the call that fills it:
    // a client that reopens a session it kept has nothing to send before the load.
    let mut replayed = String::new();
    peer.request(
        5,
        "session/load",
        json!({ "sessionId": "slow-1", "cwd": "/work", "mcpServers": [] }),
    )?;
    let loaded = peer
        .answer_to(5, |notification| {
            if notification["method"] == json!("session/update") {
                let update = &notification["params"]["update"];
                if let Some(text) = update["content"]["text"].as_str() {
                    replayed.push_str(text);
                }
            }
        })
        .await?;
    if loaded["result"]["sessionId"] != json!("slow-1") {
        return Err(format!("session/load answered {loaded}"));
    }
    if replayed != "asked before the restart" {
        return Err(format!("the replay was {replayed:?}"));
    }
    println!("session/load: replayed one update, then the session");

    peer.request(6, "session/list", json!({}))?;
    let listed = peer.answer_to(6, |_| {}).await?;
    let sessions = listed["result"]["sessions"]
        .as_array()
        .ok_or_else(|| format!("session/list answered {listed}"))?;
    if sessions.first().and_then(|row| row["sessionId"].as_str()) != Some("slow-1") {
        return Err(format!("session/list answered {listed}"));
    }
    println!("session/list: {} session", sessions.len());

    peer.close().await?;
    println!("the official Rust HTTP client drove this library's server end to end");
    Ok(())
}
