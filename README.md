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

```moonbit
moon add moonbitstack/moonacp
```

## An agent in full

Three methods are required. Everything else has a default that reports itself as unsupported, so an
agent advertises in `initialize` exactly what it answers.

<!-- nocheck -->
```moonbit
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

<!-- nocheck -->
```moonbit
async fn main {
  @stdio.serve_stdio(Notes::new())
}
```

## An editor in full

The client side is the same shape: implement `Client` for what the editor answers, connect it to a
transport, and run the connection so updates arrive while a turn is in flight.

<!-- nocheck -->
```moonbit
let child = @stdio.spawn(editor, ["/usr/local/bin/notes-agent"])
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
```

## Transports

| Transport | Entry point | Shape |
|:--|:--|:--|
| stdio | `@stdio.serve_stdio`, `@stdio.spawn` | One JSON-RPC message per line on the process's own streams. The transport an editor uses when it launches an agent. |
| ASGI | `@asgi.to_asgi` | One endpoint: `POST` for client-to-agent messages, long-lived `GET` streams for the answers, `DELETE` to end a connection, and a `WebSocket` upgrade carrying the same messages on one channel. |

The remote transport follows the protocol's request for discussion of 2026-11-04. That document is
not final, and the schema has no member for the connection identifier it introduces: the identifier
travels in the `initialize` answer's `_meta` and in an `Acp-Connection-Id` header.

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

## Consistency

The official conformance suite runs against the example agent on every push, and both official
SDKs are driven in both directions. Two things do not pass, and are listed rather than hidden:

- The suite's advisory requirement that an agent connect to the MCP servers a client names is not
  met. This library carries those records; connecting to them belongs to a library that speaks MCP.
- The remote transport has not been driven by the official Rust SDK's HTTP client, which the Rust
  SDK does not publish yet.

## License

Apache-2.0.
