---
name: moonacp
description: Implement an editor-to-agent conversation with the Agent Client Protocol — serve an agent over stdio or ASGI, or drive one from an editor. Use when a MoonBit program has to run a coding agent behind an editor, or act as the editor calling one.
---

# moonacp

The Agent Client Protocol for MoonBit. Two contracts, one per side, and two transports.

```
moon add moonbitstack/moonacp
```

## Serve an agent

Implement `Agent`. Only `initialize`, `new_session` and `prompt` are required; the rest default to
"unsupported", which is what the runtime answers with `-32601`.

```moonbit
impl @moonacp.Agent for Bot with fn initialize(self, request) {
  ignore(self)
  ignore(request)
  {
    ..@moonacp.Initialized::new(),
    capabilities: { ..@moonacp.AgentCapabilities::none(), load_session: true },
  }
}

impl @moonacp.Agent for Bot with fn new_session(self, request) {
  ignore(request)
  { session_id: "s-1", modes: None, config_options: None, meta: None }
}

impl @moonacp.Agent for Bot with fn prompt(self, request, session) {
  ignore(request)
  session.update(@moonacp.SessionUpdate::AgentMessageChunk({
    content: @moonacp.ContentBlock::Text({ text: "hello", annotations: None, meta: None }),
    message_id: None,
    meta: None,
  }))
  @moonacp.StopReason::EndTurn
}
```

Then pick a transport. stdio is what an editor uses when it launches the agent; ASGI is one endpoint
carrying HTTP streams and a WebSocket.

```moonbit
async fn main {
  @stdio.serve_stdio(Bot::new())
}
```

```moonbit
let app = @asgi.to_asgi(Bot::new(), path="/acp")
```

## Drive an agent

Implement `Client` for what the editor answers — `update` and `request_permission` are the two that
matter most — then run the connection in one task and call from another.

```moonbit
let child = @stdio.spawn(editor, ["my-agent", "--stdio"])
let conn = child.conn()
@async.with_task_group(async fn(group) {
  group.spawn_bg(async fn() { conn.run() })
  let answer = conn.prompt({
    session_id: "s-1",
    prompt: [@moonacp.ContentBlock::Text({ text: "hi", annotations: None, meta: None })],
    meta: None,
  })
  println(answer.stop_reason.to_string())
})
```

## Asking the user, and the things that can say no

`session/request_permission`, `fs/*`, `terminal/*` and `elicitation/create` are all requests the
client may refuse. Ask only for what the client advertised in `initialize`; a client that did not
advertise one answers `-32601` and the call raises.

```moonbit
let outcome = session.request_permission({
  tool_call: {
    tool_call_id: "c-1",
    kind: Some(@moonacp.ToolKind::Edit),
    status: Some(@moonacp.ToolCallStatus::Pending),
    title: Some("write notes.md"),
    name: None,
    content: None,
    locations: None,
    raw_input: None,
    raw_output: None,
    meta: None,
  },
  options: [
    { option_id: "allow", name: "Allow", kind: @moonacp.PermissionOptionKind::AllowOnce, meta: None },
  ],
  meta: None,
})
```

## Rules worth knowing

- A capability in `initialize` is a promise: leave a method out and it must not be advertised.
- `prompt` runs in a task of its own, and `session/cancel` cancels that task. A turn that never
  awaits cannot be stopped, so put awaits in a long turn.
- Updates are notifications: they are never answered, and they never fail a turn by themselves.
- The turn's answer is one `stopReason`. A cancelled turn answers `cancelled` — not an error.
- Wire names are the schema's; the MoonBit names are snake case of the same thing
  (`loadSession` is `load_session`).
- `_meta` on every message is the only place for extensions. Do not add root-level fields.
- The MCP servers a client names in `session/new` are records here; launching and speaking to them
  is MCP, and the example (`src/examples/02-notes-agent/mcp.mbt`) shows the shape: spawn, hand-shake,
  `tools/list`.
