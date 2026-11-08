// A traced agent and a traced editor talking over a pair of queues, with every span they write
// leaving the process over OTLP/gRPC.

///|
/// The two ends of one conversation, with no transport in between: what one writes, the other
/// reads.
struct Wire {
  inbox : @aqueue.Queue[String]
  outbox : @aqueue.Queue[String]
}

///|
fn wire() -> (Wire, Wire) {
  let left : @aqueue.Queue[String] = @aqueue.Queue::Queue(
    kind=@aqueue.Kind::Unbounded,
  )
  let right : @aqueue.Queue[String] = @aqueue.Queue::Queue(
    kind=@aqueue.Kind::Unbounded,
  )
  ({ inbox: left, outbox: right, }, { inbox: right, outbox: left, })
}

///|
impl @peer.Frames for Wire with fn read(self) {
  let text = self.inbox.get() catch { _ => return None }
  Some(text)
}

///|
impl @peer.Frames for Wire with fn write(self, text) {
  self.outbox.put(text) catch {
    _ => ()
  }
}

///|
fn Wire::shut(self : Wire) -> Unit {
  self.inbox.close()
  self.outbox.close()
}

///|
/// The agent: it reads one file through the editor, and the second turn fails on purpose so the
/// trace holds a span that ended badly as well as one that did not.
struct Notes {
  mut turns : Int32
}

///|
impl @moonacp.Agent for Notes with fn initialize(self, request) {
  ignore(self)
  ignore(request)
  {
    ..@moonacp.Initialized::new(),
    capabilities: { ..@moonacp.AgentCapabilities::none(), load_session: true, },
    auth_methods: [],
    agent_info: Some(@moonacp.Implementation::new("notes", "1.0.0")),
    meta: None,
  }
}

///|
impl @moonacp.Agent for Notes with fn new_session(self, request) {
  ignore(self)
  ignore(request)
  { session_id: "notes-1", modes: None, config_options: None, meta: None, }
}

///|
impl @moonacp.Agent for Notes with fn prompt(self, request, session) {
  ignore(request)
  self.turns = self.turns + 1
  if self.turns > 1 {
    raise @moonacp.Refused::Refused(
      code=@moonacp.internal_error,
      message="the notes are gone",
      data=None,
    )
  }
  let text = session.read_text_file("/work/notes.md")
  session.update(
    @moonacp.AgentMessageChunk({
      content: @moonacp.Text({ text, annotations: None, meta: None, }),
      message_id: None,
      meta: None,
    }),
  )
  @moonacp.EndTurn
}

///|
/// The editor: it answers the agent's request for a file, and prints what comes back.
struct Editor {
  mut answer : String
}

///|
impl @moonacp.Client for Editor with fn update(self, id, update) {
  ignore(id)
  if update is @moonacp.AgentMessageChunk(chunk) {
    if chunk.content is @moonacp.Text(text) {
      self.answer = self.answer + text.text
    }
  }
}

///|
impl @moonacp.Client for Editor with fn request_permission(self, ask) {
  ignore(self)
  ignore(ask)
  @moonacp.Outcome::Cancelled
}

///|
impl @moonacp.Client for Editor with fn read_text_file(self, request) {
  ignore(self)
  "the notes in \{request.path}"
}

///|
/// `host:port`, or `host` alone with the protocol's default port.
fn host_and_port(address : String) -> (String, Int32) {
  match address.rev_find(":") {
    Some(at) => (address[:at].to_owned(), port_of(address[at + 1:]))
    None => (address, 4317)
  }
}

///|
/// The port a `host:port` names, or 4317 when the text is not a number.
fn port_of(text : StringView) -> Int32 {
  let mut port = 0
  for digit in text {
    if digit < '0' || digit > '9' {
      return 4317
    }
    port = port * 10 + (digit.to_int() - '0'.to_int())
  }
  if port == 0 {
    4317
  } else {
    port
  }
}

///|
/// The clock the exporter batches by: the runtime's monotonic clock counts milliseconds.
fn millis() -> Int64 {
  @async.now()
}

///|
/// Sixteen bytes from the platform's entropy source, for the identifiers of a trace and a span.
fn random_bytes(width : Int32) -> Bytes {
  @moonseed.bytes(width, @system.source) catch {
    _ => abort("the platform has no entropy source")
  }
}

///|
async fn main {
  let arguments = @env.args()
  let address = if arguments.length() > 1 {
    arguments[1]
  } else {
    "127.0.0.1:4317"
  }
  let required = arguments.length() > 1
  let (host, port) = host_and_port(address)
  let transport = @grpc.GrpcTransport::connect(host~, port~)
  // gRPC carries the binary encoding only, so the exporter is built for it.
  let traces = @otlp.TraceExporter::new(
    transport~,
    endpoint="http://\{address}",
    resource=@otlp.Resource::of_service("moonacp-example"),
    scope=@otlp.Scope::new(name="moonbitstack/moonacp/otel"),
    format=@otlp.BodyFormat::Protobuf,
    now=millis,
    rand=random_bytes,
    attempts=if required { 5 } else { 1 },
  )
  let tracer = @trace.Tracer::new(
    sink=traces,
    rand=random_bytes,
    sampler=@trace.always,
  )
  let agent = Notes::{ turns: 0, }
  let editor = Editor::{ answer: "", }
  let (agent_wire, client_wire) = wire()
  let peer = @moonacp.serve(@otel.traced(agent, tracer), agent_wire)
  let conn = @moonacp.connect(
    @otel.traced_client(editor, tracer, options={
      agent_name: "notes",
      agent_version: "1.0.0",
    }),
    client_wire,
  )
  @async.with_task_group(async fn(group) {
    group.spawn_bg(async fn() { peer.run() })
    group.spawn_bg(async fn() { conn.run() })
    defer agent_wire.shut()
    defer client_wire.shut()
    ignore(
      conn.initialize({
        protocol_version: @moonacp.protocol_version,
        client_capabilities: @moonacp.ClientCapabilities::none(),
        client_info: Some(
          @moonacp.Implementation::new("example-editor", "1.0.0"),
        ),
        meta: None,
      }),
    )
    let started = conn.new_session({
      cwd: "/work",
      additional_directories: None,
      mcp_servers: [],
      meta: None,
    })
    let first = conn.prompt({
      session_id: started.session_id,
      prompt: [
        @moonacp.Text({
          text: "what is in my notes?",
          annotations: None,
          meta: None,
        }),
      ],
      meta: None,
    })
    println("first turn: \{first.stop_reason.to_string()}")
    let second = try {
      ignore(
        conn.prompt({
          session_id: started.session_id,
          prompt: [
            @moonacp.Text({ text: "and now?", annotations: None, meta: None, }),
          ],
          meta: None,
        }),
      )
      "answered"
    } catch {
      @moonacp.Refused::Refused(message~, ..) => "refused: \{message}"
      _ => "refused"
    }
    println("second turn: \{second}")
  })
  println("the editor read: \{editor.answer}")
  let report = traces.flush()
  transport.close()
  println(
    "OTLP/gRPC: delivered \{report.delivered}, rejected \{report.rejected}, dropped \{report.dropped}, requests \{report.attempts}",
  )
  if required && report.delivered == 0 {
    abort("no span reached the collector at \{address}")
  }
}
