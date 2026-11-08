// What the wrappers write, driven over a pair of queues: the names, the attributes, the status,
// and the promise that a wrapped agent still answers everything it answered before.

///|
/// A conversation cut in half, so both sides run against each other with no transport.
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
/// A source of identifiers a test can read back: sixteen bytes that are never all zero, which is
/// what makes a trace identifier valid.
fn patterns(width : Int32) -> Bytes {
  Bytes::make(width, b'\x21')
}

///|
/// A tracer over a recorder, sampling everything so that a test sees every span the wrapper opens.
fn tracer(recorder : @trace.Recorder) -> @trace.Tracer {
  @trace.Tracer::new(
    rand=patterns,
    sink=recorder,
    sampler=@trace.parent_based(root=@trace.always),
  )
}

///|
fn attribute(span : @trace.SpanData, key : String) -> @trace.Value? {
  for entry in span.attributes {
    let (name, value) = entry
    if name == key {
      return Some(value)
    }
  }
  None
}

///|
/// A span by the name the conventions gave it, or nothing when the wrapper did not write one.
fn named(spans : Array[@trace.SpanData], name : String) -> @trace.SpanData? {
  for span in spans {
    if span.name == name {
      return Some(span)
    }
  }
  None
}

///|
/// An agent that answers one turn, reads one file through the client, or refuses — whichever the
/// test asked for.
struct Reader {
  mut fail : Bool
  mut reads : Bool
  mut loaded : Int32
}

///|
fn Reader::new() -> Reader {
  { fail: false, reads: false, loaded: 0, }
}

///|
impl @moonacp.Agent for Reader with fn initialize(self, request) {
  ignore(self)
  ignore(request)
  {
    ..@moonacp.Initialized::new(),
    capabilities: { ..@moonacp.AgentCapabilities::none(), load_session: true, },
    auth_methods: [],
    agent_info: Some(@moonacp.Implementation::new("echo", "0.1.0")),
  }
}

///|
impl @moonacp.Agent for Reader with fn new_session(self, request) {
  ignore(self)
  ignore(request)
  { session_id: "s-1", modes: None, config_options: None, meta: None, }
}

///|
impl @moonacp.Agent for Reader with fn load_session(self, request, session) {
  ignore(session)
  self.loaded = self.loaded + 1
  {
    session_id: request.session_id,
    modes: None,
    config_options: None,
    meta: None,
  }
}

///|
impl @moonacp.Agent for Reader with fn prompt(self, request, session) {
  ignore(request)
  if self.fail {
    raise @moonacp.Refused::Refused(
      code=@moonacp.internal_error,
      message="the model fell over",
      data=None,
    )
  }
  if self.reads {
    let text = session.read_text_file("/work/notes.md")
    session.update(
      @moonacp.AgentMessageChunk({
        content: @moonacp.Text({ text, annotations: None, meta: None, }),
        message_id: None,
        meta: None,
      }),
    )
  }
  @moonacp.EndTurn
}

///|
/// An editor that answers everything the agent may ask, and reads one file.
struct Editor {
  mut read : Int32
}

///|
fn Editor::new() -> Editor {
  { read: 0, }
}

///|
impl @moonacp.Client for Editor with fn update(self, id, update) {
  ignore(self)
  ignore(id)
  ignore(update)
}

///|
impl @moonacp.Client for Editor with fn request_permission(self, ask) {
  ignore(self)
  ignore(ask)
  @moonacp.Outcome::Cancelled
}

///|
impl @moonacp.Client for Editor with fn read_text_file(self, request) {
  self.read = self.read + 1
  "content of \{request.path}"
}

///|
impl @moonacp.Client for Editor with fn write_text_file(self, request) {
  ignore(self)
  ignore(request)
}

///|
async fn handshake(conn : @moonacp.Conn) -> @moonacp.Initialized {
  conn.initialize({
    protocol_version: @moonacp.protocol_version,
    client_capabilities: @moonacp.ClientCapabilities::none(),
    client_info: None,
    meta: None,
  })
}

///|
async fn open_session(conn : @moonacp.Conn) -> String {
  let started = conn.new_session({
    cwd: "/work",
    additional_directories: None,
    mcp_servers: [],
    meta: None,
  })
  started.session_id
}

///|
test "the names are the registry's, and the span name puts the subject after the operation" {
  assert_eq(operation_of(@semconv.gen_ai_invoke_agent_internal), "invoke_agent")
  assert_eq(operation_of(@semconv.gen_ai_execute_tool_internal), "execute_tool")
  assert_eq(
    span_name(@semconv.gen_ai_invoke_agent_internal, "notes"),
    "invoke_agent notes",
  )
  assert_eq(
    span_name(@semconv.gen_ai_execute_tool_internal, "fs/read_text_file"),
    "execute_tool fs/read_text_file",
  )
  assert_eq(
    span_name(@semconv.gen_ai_invoke_agent_internal, ""),
    "invoke_agent",
  )
}

///|
async test "a turn is one span, carrying the agent, the conversation and how it ended" {
  let recorder = @trace.Recorder::new()
  let (agent_wire, client_wire) = wire()
  let agent = Reader::new()
  let editor = Editor::new()
  let peer = @moonacp.serve(traced(agent, tracer(recorder)), agent_wire)
  let conn = @moonacp.connect(editor, client_wire)
  @async.with_task_group(async fn(group) {
    group.spawn_bg(async fn() { peer.run() })
    group.spawn_bg(async fn() { conn.run() })
    defer agent_wire.shut()
    defer client_wire.shut()
    ignore(handshake(conn))
    let id = open_session(conn)
    ignore(
      conn.prompt({
        session_id: id,
        prompt: [@moonacp.Text({ text: "hi", annotations: None, meta: None, })],
        meta: None,
      }),
    )
  })
  let spans = recorder.spans()
  assert_eq(spans.length(), 1)
  let span = spans[0]
  assert_eq(span.name, "invoke_agent echo")
  assert_eq(span.kind, @trace.Internal)
  assert_eq(span.status, @trace.Ok)
  assert_eq(
    attribute(span, @semconv.gen_ai_operation_name),
    Some(@trace.Str("invoke_agent")),
  )
  assert_eq(
    attribute(span, @semconv.gen_ai_agent_name),
    Some(@trace.Str("echo")),
  )
  assert_eq(
    attribute(span, @semconv.gen_ai_agent_version),
    Some(@trace.Str("0.1.0")),
  )
  assert_eq(
    attribute(span, @semconv.gen_ai_conversation_id),
    Some(@trace.Str("s-1")),
  )
  assert_eq(
    attribute(span, @semconv.gen_ai_response_finish_reasons),
    Some(@trace.Strs(["end_turn"])),
  )
}

///|
async test "a turn that fails ends as an error, and the client still sees the failure" {
  let recorder = @trace.Recorder::new()
  let (agent_wire, client_wire) = wire()
  let agent = Reader::new()
  agent.fail = true
  let editor = Editor::new()
  let peer = @moonacp.serve(traced(agent, tracer(recorder)), agent_wire)
  let conn = @moonacp.connect(editor, client_wire)
  @async.with_task_group(async fn(group) {
    group.spawn_bg(async fn() { peer.run() })
    group.spawn_bg(async fn() { conn.run() })
    defer agent_wire.shut()
    defer client_wire.shut()
    ignore(handshake(conn))
    let id = open_session(conn)
    let code = try {
      ignore(
        conn.prompt({
          session_id: id,
          prompt: [
            @moonacp.Text({ text: "hi", annotations: None, meta: None, }),
          ],
          meta: None,
        }),
      )
      0
    } catch {
      @moonacp.Refused(code~, ..) => code
      _ => -1
    }
    assert_eq(code, @moonacp.internal_error)
  })
  let spans = recorder.spans()
  assert_eq(spans.length(), 1)
  assert_eq(spans[0].status, @trace.Error("the model fell over"))
}

///|
async test "a file the agent reads through the client is a tool call on the editor's side" {
  let recorder = @trace.Recorder::new()
  let settings : Options = { agent_name: "echo", agent_version: "0.1.0", }
  let (agent_wire, client_wire) = wire()
  let agent = Reader::new()
  agent.reads = true
  let editor = Editor::new()
  let peer = @moonacp.serve(traced(agent, tracer(recorder)), agent_wire)
  let traced_editor = traced_client(editor, tracer(recorder), options=settings)
  let conn = @moonacp.connect(traced_editor, client_wire)
  @async.with_task_group(async fn(group) {
    group.spawn_bg(async fn() { peer.run() })
    group.spawn_bg(async fn() { conn.run() })
    defer agent_wire.shut()
    defer client_wire.shut()
    ignore(handshake(conn))
    let id = open_session(conn)
    ignore(
      conn.prompt({
        session_id: id,
        prompt: [
          @moonacp.Text({ text: "read it", annotations: None, meta: None, }),
        ],
        meta: None,
      }),
    )
  })
  assert_eq(editor.read, 1)
  let spans = recorder.spans()
  assert_eq(spans.length(), 2)
  let span = match named(spans, "execute_tool fs/read_text_file") {
    Some(span) => span
    None => abort("the tool call was not traced")
  }
  assert_eq(
    attribute(span, @semconv.gen_ai_operation_name),
    Some(@trace.Str("execute_tool")),
  )
  assert_eq(
    attribute(span, @semconv.gen_ai_tool_name),
    Some(@trace.Str("fs/read_text_file")),
  )
  assert_eq(
    attribute(span, @semconv.gen_ai_conversation_id),
    Some(@trace.Str("s-1")),
  )
}

///|
async test "a wrapped agent still answers the methods it always did" {
  let recorder = @trace.Recorder::new()
  let (agent_wire, client_wire) = wire()
  let agent = Reader::new()
  let editor = Editor::new()
  let peer = @moonacp.serve(traced(agent, tracer(recorder)), agent_wire)
  let conn = @moonacp.connect(editor, client_wire)
  @async.with_task_group(async fn(group) {
    group.spawn_bg(async fn() { peer.run() })
    group.spawn_bg(async fn() { conn.run() })
    defer agent_wire.shut()
    defer client_wire.shut()
    ignore(handshake(conn))
    let started = conn.load_session({
      session_id: "s-9",
      cwd: "/work",
      additional_directories: None,
      mcp_servers: [],
      meta: None,
    })
    assert_eq(started.session_id, "s-9")
  })
  assert_eq(agent.loaded, 1)
}

///|
/// A collector that keeps what it was sent, so a test can read the payload.
struct Exports {
  bodies : Array[String]
}

///|
fn Exports::new() -> Exports {
  { bodies: [], }
}

///|
impl @otlp.Transport for Exports with fn send(self, request) {
  self.bodies.push(@utf8.decode_lossy(request.body))
  { status: 200, headers: [], body: Bytes::new(0), }
}

///|
fn millis() -> Int64 {
  @async.now()
}

///|
/// An exporter over the recording transport, in the JSON encoding: readable payloads, and a
/// `flush` a test can wait on.
fn exporter(sink : Exports) -> @otlp.MetricsExporter {
  @otlp.MetricsExporter::new(
    transport=sink,
    endpoint="http://collector.example/v1/metrics",
    format=@otlp.BodyFormat::Json,
    now=millis,
    rand=patterns,
    attempts=1,
  )
}

///|
test "a histogram counts a value in the bucket its bound closes" {
  let seconds = Seconds::new()
  seconds.observe(0.005, 1L)
  seconds.observe(0.006, 2L)
  seconds.observe(20.0, 3L)
  assert_eq(seconds.count, 3L)
  assert_eq(seconds.total, 20.011)
  assert_eq(seconds.least, 0.005)
  assert_eq(seconds.most, 20.0)
  // Fourteen bounds make fifteen buckets: the last one is everything above the last bound.
  assert_eq(seconds.counts.length(), 15)
  assert_eq(seconds.counts[0], 1L)
  assert_eq(seconds.counts[1], 1L)
  assert_eq(seconds.counts[14], 1L)
}

///|
async test "a turn is one observation of the agent's duration, exported as OTLP" {
  let sink = Exports::new()
  let meter = exporter(sink)
  let (agent_wire, client_wire) = wire()
  let agent = Reader::new()
  let editor = Editor::new()
  let peer = @moonacp.serve(metered(agent, meter), agent_wire)
  let conn = @moonacp.connect(editor, client_wire)
  @async.with_task_group(async fn(group) {
    group.spawn_bg(async fn() { peer.run() })
    group.spawn_bg(async fn() { conn.run() })
    defer agent_wire.shut()
    defer client_wire.shut()
    ignore(handshake(conn))
    let id = open_session(conn)
    ignore(
      conn.prompt({
        session_id: id,
        prompt: [@moonacp.Text({ text: "hi", annotations: None, meta: None, })],
        meta: None,
      }),
    )
  })
  let report = meter.flush()
  assert_eq(report.delivered, 1)
  let text = sink.bodies[0]
  assert_true(text.contains(@semconv.gen_ai_invoke_agent_duration))
  assert_true(text.contains("\"unit\":\"s\""))
  assert_true(text.contains(@semconv.gen_ai_operation_name))
  assert_true(text.contains("\"invoke_agent\""))
  assert_true(text.contains(@semconv.gen_ai_agent_name))
}

///|
async test "a request the editor answers is one observation of the tool's duration" {
  let sink = Exports::new()
  let meter = exporter(sink)
  let (agent_wire, client_wire) = wire()
  let agent = Reader::new()
  agent.reads = true
  let editor = Editor::new()
  let peer = @moonacp.serve(agent, agent_wire)
  let conn = @moonacp.connect(
    metered_client(editor, meter, options={
      agent_name: "echo",
      agent_version: "0.1.0",
    }),
    client_wire,
  )
  @async.with_task_group(async fn(group) {
    group.spawn_bg(async fn() { peer.run() })
    group.spawn_bg(async fn() { conn.run() })
    defer agent_wire.shut()
    defer client_wire.shut()
    ignore(handshake(conn))
    let id = open_session(conn)
    ignore(
      conn.prompt({
        session_id: id,
        prompt: [
          @moonacp.Text({ text: "read it", annotations: None, meta: None, }),
        ],
        meta: None,
      }),
    )
  })
  assert_eq(editor.read, 1)
  let report = meter.flush()
  assert_eq(report.delivered, 1)
  let text = sink.bodies[0]
  assert_true(text.contains(@semconv.gen_ai_execute_tool_duration))
  assert_true(text.contains(@semconv.gen_ai_tool_name))
  assert_true(text.contains("fs/read_text_file"))
}
