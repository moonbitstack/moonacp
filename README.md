<div align="center">

# moonacp

**An editor talks, an agent answers.** The Agent Client Protocol for MoonBit.

[Guide](https://moonbitstack.github.io/moonacp/) · [API reference](https://moonbitstack.github.io/moonacp/api.html) · [mooncakes](https://mooncakes.io/docs/moonbitstack/moonacp)

</div>

An editor and a coding agent are two programs that need to agree on more than text: who owns the
session, how an answer arrives while it is still being written, who may write a file, who runs the
command. This library is that agreement — the session, the streamed updates, the permission
prompts, the files and the terminals — with both sides of it in one place and two transports to
carry it.

<!-- nocheck -->
```moonbit
moon add moonbitstack/moonacp
```

## An agent in full

Three methods are required. Everything else has a default that reports itself as unsupported, so an
agent advertises in `initialize` exactly what it answers.

```moonbit native
struct Notes {
  mut sessions : Int32
}

fn Notes::new() -> Notes {
  { sessions: 0 }
}

impl @moonacp.Agent for Notes with fn initialize(self, request) {
  ignore(self)
  ignore(request)
  {
    ..@moonacp.Initialized::new(),
    capabilities: {
      ..@moonacp.AgentCapabilities::none(),
      prompt: { image: true, audio: false, embedded_context: true, meta: None },
    },
    agent_info: Some(@moonacp.Implementation::new("notes", "0.1.0")),
  }
}

impl @moonacp.Agent for Notes with fn new_session(self, request) {
  ignore(request)
  self.sessions = self.sessions + 1
  { session_id: "notes-\{self.sessions}", modes: None, config_options: None, meta: None }
}

impl @moonacp.Agent for Notes with fn prompt(self, request, session) {
  let text = request.prompt.map(block => match block {
    @moonacp.ContentBlock::Text(content) => content.text
    _ => ""
  }).join(" ")
  session.update(@moonacp.SessionUpdate::AgentMessageChunk({
    content: @moonacp.ContentBlock::Text({ text: "You said: " + text, annotations: None, meta: None }),
    message_id: None,
    meta: None,
  }))
  @moonacp.StopReason::EndTurn
}
```

Serve it on the pipe an editor launches it with:

```moonbit native
@stdio.serve_stdio(Notes::new())
```

## An editor in full

The client side is the same shape: implement `Client` for what the editor answers, connect it to a
transport, and run the connection so updates arrive while a turn is in flight.

```moonbit native
struct Editor {
  mut chunks : Int32
}

fn Editor::new() -> Editor {
  { chunks: 0 }
}

impl @moonacp.Client for Editor with fn update(self, id, update) {
  ignore(id)
  match update {
    @moonacp.SessionUpdate::AgentMessageChunk(chunk) =>
      if chunk.content is @moonacp.ContentBlock::Text(text) {
        self.chunks = self.chunks + 1
        println(text.text)
      }
    _ => ()
  }
}

impl @moonacp.Client for Editor with fn request_permission(self, ask) {
  ignore(self)
  match ask.options {
    [] => @moonacp.Outcome::Cancelled
    [first, ..] => @moonacp.Outcome::Selected(first.option_id)
  }
}

async fn main {
  let child = @stdio.spawn(Editor::new(), ["/usr/local/bin/notes-agent"])
  let conn = child.conn()
  @async.with_task_group(async fn(group) {
    group.spawn_bg(async fn() { conn.run() })
    ignore(conn.initialize({
      protocol_version: @moonacp.protocol_version,
      client_capabilities: @moonacp.ClientCapabilities::none(),
      client_info: None,
      meta: None,
    }))
    let session = conn.new_session({
      cwd: "/work",
      additional_directories: None,
      mcp_servers: [],
      meta: None,
    })
    let answer = conn.prompt({
      session_id: session.session_id,
      prompt: [@moonacp.ContentBlock::Text({ text: "hello", annotations: None, meta: None })],
      meta: None,
    })
    println(answer.stop_reason.to_string())
  })
}
```

## Transports

| Transport | Entry point | Shape |
|:--|:--|:--|
| stdio | `@stdio.serve_stdio`, `@stdio.spawn` | One JSON-RPC message per line on the process's own streams. The transport an editor uses when it launches an agent. |
| ASGI | `@asgi.to_asgi` | One endpoint: `POST` for client-to-agent messages, long-lived `GET` streams for the answers, `DELETE` to end a connection, and a `WebSocket` upgrade carrying the same messages on one channel. |

The remote transport follows the protocol's request for discussion of 2026-11-04. That document is
not final, and the schema has no member for the connection identifier it introduces: the identifier
travels in the `initialize` answer's `_meta` and in an `Acp-Connection-Id` header.

## Traces and metrics

`@otel` wraps either side of the conversation, so that what happened in it can be read afterwards.
A turn becomes one span and one observation of a duration, and every file or terminal request the
agent makes of the editor becomes one more of each. Every name here — of a span, of a metric, of an
attribute — is read from `moontel/semconv`, which is generated from the OpenTelemetry GenAI
registry; nothing in a signal is named by this library.

| Signal | Written by | Carries |
|:--|:--|:--|
| `invoke_agent {agent}` span | `@otel.traced`, one per prompt | the agent and its version, the conversation — ACP's session — and the stop reason as `gen_ai.response.finish_reasons` |
| `execute_tool {method}` span | `@otel.traced_client`, one per `fs/*` and `terminal/*` request | the tool, named after the method, the conversation, and the agent when the editor knows it |
| `gen_ai.invoke_agent.duration` histogram, in seconds | `@otel.metered`, one observation per prompt | the operation and the agent |
| `gen_ai.execute_tool.duration` histogram, in seconds | `@otel.metered_client`, one observation per answered request | the tool, and the agent when the editor knows it |

A span covers the call, so a turn that failed ends as an error with the failure as its status, and a
turn that was cancelled ends as `Ok` with `cancelled` among its finish reasons. Prompt and answer
text is never recorded: a trace is read by more people than the conversation is.

```moonbit native
let tracer = @trace.Tracer::new(
  rand=width => Bytes::make(width, b'\x21'),
  sink=@trace.Recorder::new(),
  sampler=@trace.always,
)
@stdio.serve_stdio(@otel.traced(Notes::new(), tracer))
```

The tracer is the one `moontel` builds, so spans go wherever its sinks send them: a recorder in a
test, a collector over OTLP, a file. Metrics go the same way — a histogram is one observation per
turn, and the built-in bounds are five milliseconds to ten seconds:

```moonbit native
let transport = @grpc.GrpcTransport::connect(host="127.0.0.1", port=4317)
let metrics = @otlp.MetricsExporter::new(
  transport~,
  format=@otlp.BodyFormat::Protobuf,
  now=@async.now,
  rand=width => Bytes::make(width, b'\x21'),
)
@stdio.serve_stdio(@otel.metered(Notes::new(), metrics))
```

The wrappers compose, so one line gets both: `@otel.metered(@otel.traced(agent, tracer), metrics)`.
The example in `src/examples/04-otel` runs a whole conversation with all four wrappers on and
exports both signals.

## The interface

<!-- nocheck -->
```moonbit
// The agent's side
pub(open) trait Agent {
  async fn initialize(Self, Initialize) -> Initialized raise Refused
  async fn new_session(Self, NewSession) -> SessionStarted raise Refused
  async fn prompt(Self, Prompt, Session) -> StopReason raise Refused
  // authenticate, logout, session/load, session/resume, session/list, session/delete,
  // session/close, session/set_mode, session/set_config_option, cancel: optional
}

// What a prompt uses to talk back
pub async fn Session::update(Self, SessionUpdate) -> Unit raise Refused
pub async fn Session::request_permission(Self, Permission) -> Outcome raise Refused
pub async fn Session::read_text_file(Self, String, line? : Int64, limit? : Int64) -> String raise Refused
pub async fn Session::write_text_file(Self, String, String) -> Unit raise Refused
pub async fn Session::terminal(Self, String, ..) -> Terminal raise Refused
pub async fn Session::elicit(Self, Elicitation) -> Answer raise Refused

// The editor's side
pub(open) trait Client {
  async fn update(Self, String, SessionUpdate) -> Unit
  async fn request_permission(Self, Permission) -> Outcome raise Refused
  // read_text_file, write_text_file, create_terminal, terminal_output, wait_for_terminal_exit,
  // kill_terminal, release_terminal, elicit: optional
}

pub fn serve(&Agent, &@peer.Frames) -> @peer.Peer
pub fn connect(&Client, &@peer.Frames) -> Conn
pub async fn Conn::initialize(Self, Initialize) -> Initialized raise Refused
pub async fn Conn::prompt(Self, Prompt) -> PromptResult raise Refused
pub async fn Conn::cancel(Self, String) -> Unit raise Refused
pub async fn Conn::run(Self) -> Unit
```

The wire types are the schema's own: `ContentBlock`, `SessionUpdate` with its fourteen shapes,
`ToolCall`, `StopReason`, `AgentCapabilities`, `ClientCapabilities`, the MCP server records, the
elicitation forms, and one type per method for its parameters and its answer.

## MCP servers

A client names the MCP servers it wants in `session/new`; launching them and talking to them is the
agent's job, and it is written where that job lives — in the example. `mcp.mbt` there spawns each
stdio server, completes the MCP handshake, asks what tools it offers, and closes its input when the
session ends. The library itself carries the servers' records and nothing more, because speaking
MCP is a protocol of its own.

## Consistency

Every implementation this protocol has an official client for is driven against the example agent,
in both directions, and every message either side writes is checked against the published schema.
Nothing is listed as passing that does not run on every push.

| Check | Pinned at | Result |
|:--|:--|:--|
| `acp-tck`, the official conformance suite | commit `b7f40fb`, v1 suite | `CONFORMANT`: every mandatory requirement and every declared capability |
| The published schema | v1.29.1 | every message, both directions |
| Official TypeScript client → this library | `@agentclientprotocol/sdk` 2.4.0 | conversation, streamed answer, cancel |
| Official Python client → this library | `agent-client-protocol` 0.12.1 | conversation, streamed answer, cancel |
| This library → official TypeScript agent | `@agentclientprotocol/sdk` 2.4.0 | conversation, streamed answer |
| This library → official Python agent | `agent-client-protocol` 0.12.1 | conversation, streamed answer |
| Official Rust client over HTTP → this library's server | `agent-client-protocol-http` 5.0.0 | initialize, session, streamed turn, cancel, list |
| The signals this library writes against the GenAI registry | `weaver` 0.28.0, conventions `aa3b7f4` | spans and metrics, no findings |

## License

Apache-2.0.
