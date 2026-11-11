//! An agent served by the official Rust SDK's HTTP transport, for a MoonBit client to drive.
//!
//! This is the other direction of the interop: `scripts/interop/rust-http-client` proves that an
//! editor written with the official SDK reaches this library's server; this program is the agent
//! that SDK ships, mounted on axum, so this library's client can be proven against it in turn.
//!
//! The conversation is the same script as the client's: `initialize`, a session, a streamed turn
//! of two chunks, and a second turn that answers `cancelled` when the client cancels it.
//!
//! Usage: `acp-http-agent [port]`, and it prints the address it got before serving.

use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;

use agent_client_protocol::v1::schema::{
    AgentCapabilities, ContentBlock, ContentChunk, InitializeRequest, InitializeResponse,
    NewSessionRequest, NewSessionResponse, PromptRequest, PromptResponse, SessionNotification,
    SessionUpdate, StopReason, TextContent,
};
use agent_client_protocol::{on_receive_request, Agent};
use agent_client_protocol_http::AcpHttpServer;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let port: u16 = std::env::args().nth(1).unwrap_or_else(|| "0".into()).parse()?;
    let sessions = Arc::new(AtomicU64::new(0));

    let factory = {
        let sessions = sessions.clone();
        move || {
            let session = format!("rust-{}", sessions.fetch_add(1, Ordering::SeqCst) + 1);
            Agent
                .v1()
                .name("rust-echo")
                .on_receive_request(
                    async move |request: InitializeRequest, responder, _cx| {
                        responder.respond(
                            InitializeResponse::new(request.protocol_version)
                                .agent_capabilities(AgentCapabilities::new()),
                        )
                    },
                    on_receive_request!(),
                )
                .on_receive_request(
                    async move |_request: NewSessionRequest, responder, _cx| {
                        responder.respond(NewSessionResponse::new(session.clone()))
                    },
                    on_receive_request!(),
                )
                .on_receive_request(
                    async move |request: PromptRequest, responder, cx| {
                        let asked = request
                            .prompt
                            .iter()
                            .filter_map(|block| match block {
                                ContentBlock::Text(text) => Some(text.text.as_str()),
                                _ => None,
                            })
                            .collect::<Vec<_>>()
                            .join(" ");
                        let session_id = request.session_id.clone();
                        let chunk = |text: String| {
                            let update = SessionUpdate::AgentMessageChunk(ContentChunk::new(
                                ContentBlock::Text(TextContent::new(text)),
                            ));
                            cx.send_notification(SessionNotification::new(
                                session_id.clone(),
                                update,
                            ))
                        };
                        chunk("rust echo: ".to_string())?;
                        chunk(asked)?;
                        responder.respond(PromptResponse::new(StopReason::EndTurn))
                    },
                    on_receive_request!(),
                )
        }
    };

    let app = AcpHttpServer::new(factory).into_router();
    let listener = tokio::net::TcpListener::bind(("127.0.0.1", port)).await?;
    println!("serving on {}", listener.local_addr()?);
    axum::serve(listener, app).await?;
    Ok(())
}
