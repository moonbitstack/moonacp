---
name: moonacp
description: Implement an editor-to-agent conversation with the Agent Client Protocol — serve an agent over stdio or ASGI, drive one from an editor, or trace either side. Use when a MoonBit program has to run a coding agent behind an editor, act as the editor calling one, or record what a turn did.
---

# moonacp

The Agent Client Protocol for MoonBit. Two contracts, one per side, two transports, and a wrapper
that writes a trace of either side.

```
moon add moonbitstack/moonacp
```

## Serve an agent

Implement `Agent`. Only `initialize`, `new_session` and `prompt` are required; the rest default to
"unsupported", which is what the runtime answers with `-32601`.

```moonbit native
struct Bot {
  mut sessions : Int32
}

fn Bot::new() -> Bot {
  { sessions: 0 }
}

impl @moonacp.Agent for Bot with fn initialize(self, request) {
  ignore(self)
  ignore(request)
  {
    ..@moonacp.Initialized::new(),
    capabilities: { ..@moonacp.AgentCapabilities::none(), load_session: true },
    agent_info: Some(@moonacp.Implementation::new("bot", "0.1.0")),
  }
}

impl @moonacp.Agent for Bot with fn new_session(self, request) {
  ignore(request)
  self.sessions = self.sessions + 1
  {
    session_id: "s-\{self.sessions}",
    modes: None,
    config_options: None,
    meta: None,
  }
}

impl @moonacp.Agent for Bot with fn prompt(self, request, session) {
  ignore(request)
  session.update(
    @moonacp.SessionUpdate::AgentMessageChunk({
      content: @moonacp.ContentBlock::Text({
        text: "hello",
        annotations: None,
        meta: None,
      }),
      message_id: None,
      meta: None,
    }),
  )
  @moonacp.StopReason::EndTurn
}
```

stdio is what an editor uses when it launches the agent:

```moonbit native
@stdio.serve_stdio(Bot::new())
```

ASGI is one endpoint carrying HTTP streams and a WebSocket, handed to any ASGI server:

```moonbit native
let app = @asgi.to_asgi(Bot::new(), path="/acp")
ignore(app)
```

## Drive an agent

Implement `Client` for what the editor answers — `update` and `request_permission` are the two that
matter most — then run the connection in one task and call from another.

```moonbit native
struct Screen {
  mut text : String
}

impl @moonacp.Client for Screen with fn update(self, id, update) {
  ignore(id)
  if update is @moonacp.SessionUpdate::AgentMessageChunk(chunk) {
    if chunk.content is @moonacp.ContentBlock::Text(content) {
      self.text = self.text + content.text
    }
  }
}

impl @moonacp.Client for Screen with fn request_permission(self, ask) {
  ignore(self)
  match ask.options {
    [] => @moonacp.Outcome::Cancelled
    [first, ..] => @moonacp.Outcome::Selected(first.option_id)
  }
}

async fn main {
  let screen = Screen::{ text: "", }
  let child = @stdio.spawn(screen, ["my-agent", "--stdio"])
  let conn = child.conn()
  @async.with_task_group(async fn(group) {
    group.spawn_bg(async fn() { conn.run() })
    let answer = conn.prompt({
      session_id: "s-1",
      prompt: [
        @moonacp.ContentBlock::Text({ text: "hi", annotations: None, meta: None }),
      ],
      meta: None,
    })
    println(answer.stop_reason.to_string())
  })
}
```

## Asking the user, and the things that can say no

`session/request_permission`, `fs/*`, `terminal/*` and `elicitation/create` are all requests the
client may refuse. Ask only for what the client advertised in `initialize`; a client that did not
advertise one answers `-32601` and the call raises.

```moonbit native
async fn approve(
  session : @moonacp.Session,
  call : @moonacp.ToolCallUpdate,
) -> @moonacp.Outcome raise {
  session.request_permission({
    tool_call: call,
    options: [
      {
        option_id: "allow",
        name: "Allow",
        kind: @moonacp.PermissionOptionKind::AllowOnce,
        meta: None,
      },
    ],
    meta: None,
  })
}
```

## Trace and measure a conversation

`@otel` wraps either side. A turn becomes one span and one histogram observation; every file or
terminal request the agent makes of the editor becomes one more of each. All of them are the signals
the OpenTelemetry GenAI conventions define, named from `moontel/semconv`. Prompt and answer text is
never recorded.

```moonbit native
let tracer = @trace.Tracer::new(
  rand=width => Bytes::make(width, b'\x21'),
  sink=@trace.Recorder::new(),
  sampler=@trace.always,
)
@stdio.serve_stdio(@otel.traced(Bot::new(), tracer))
```

The editor's side is the same call with the other contract. `options` fills in the agent's name
where the editor has no `initialize` answer to read it from:

```moonbit native
let client : &@moonacp.Client = @otel.traced_client(
  Screen::{ text: "", },
  tracer,
  options={ agent_name: "bot", agent_version: "0.1.0" },
)
ignore(client)
```

Metrics are the same shape: `metered` and `metered_client` take an OTLP metrics exporter instead of
a tracer and record one observation of `gen_ai.invoke_agent.duration` or
`gen_ai.execute_tool.duration` per operation. The wrappers compose, in either order:

```moonbit native
let transport = @grpc.GrpcTransport::connect(host="127.0.0.1", port=4317)
let metrics = @otlp.MetricsExporter::new(
  transport~,
  encoding=@binary.protobuf,
  now=@async.now,
  rand=width => Bytes::make(width, b'\x21'),
)
let measured = @otel.metered(@otel.traced(Bot::new(), tracer), metrics)
ignore(measured)
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
- A traced agent keeps answering everything the wrapped one answered: the wrapper forwards every
  method, so a capability does not disappear because a span was added around it.
- A turn that fails ends its span as an error and still fails the caller; a turn that is cancelled
  ends as `Ok` with `cancelled` among its finish reasons.
- The metric and the span measure the same call, so a backend that has both should see one duration,
  not two. The conversation is not an attribute of either histogram: only the agent is, which keeps
  the series count from growing with every session.
