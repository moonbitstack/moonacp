// A conversation cut in half with two queues, so the agent and the client can be driven against each
// other without a transport.

///|
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
/// Closes both halves, so a `run` in another task returns.
fn Wire::shut(self : Wire) -> Unit {
  self.inbox.close()
  self.outbox.close()
}

///|
/// An agent that answers one turn with one chunk, and can be told to wait so a cancel has something
/// to stop.
struct EchoAgent {
  mut greeted : Int32
  gate : @aqueue.Queue[Unit]
  mut waited : Bool
}

///|
fn EchoAgent::new() -> EchoAgent {
  {
    greeted: 0,
    gate: @aqueue.Queue::Queue(kind=@aqueue.Kind::Unbounded),
    waited: false,
  }
}

///|
impl @moonacp.Agent for EchoAgent with fn initialize(self, request) {
  ignore(self)
  ignore(request)
  {
    ..@moonacp.Initialized::new(),
    capabilities: {
      ..@moonacp.AgentCapabilities::none(),
      load_session: true,
      prompt: { image: true, audio: false, embedded_context: true, meta: None, },
    },
    auth_methods: [],
    agent_info: Some(@moonacp.Implementation::new("echo", "0.1.0")),
  }
}

///|
impl @moonacp.Agent for EchoAgent with fn new_session(self, request) {
  ignore(self)
  ignore(request)
  { session_id: "s-1", modes: None, config_options: None, meta: None, }
}

///|
impl @moonacp.Agent for EchoAgent with fn prompt(self, request, session) {
  ignore(request)
  if self.waited {
    // A turn that never finishes on its own, so a cancel has something to stop.
    self.gate.get() catch {
      _ => ()
    }
  }
  self.greeted = self.greeted + 1
  session.update(
    @moonacp.AgentMessageChunk({
      content: @moonacp.Text({ text: "hello", annotations: None, meta: None, }),
      message_id: None,
      meta: None,
    }),
  )
  @moonacp.EndTurn
}

///|
impl @moonacp.Agent for EchoAgent with fn cancel(self, id) {
  ignore(self)
  ignore(id)
}

///|
/// A client that keeps every update it is told about.
struct Recorder {
  updates : Array[(String, @moonacp.SessionUpdate)]
  asked : Array[@moonacp.Permission]
}

///|
fn Recorder::new() -> Recorder {
  { updates: [], asked: [], }
}

///|
impl @moonacp.Client for Recorder with fn update(self, id, update) {
  self.updates.push((id, update))
}

///|
impl @moonacp.Client for Recorder with fn request_permission(self, ask) {
  self.asked.push(ask)
  @moonacp.Selected("allow")
}

///|
impl @moonacp.Client for Recorder with fn read_text_file(_, request) {
  "content of \{request.path}"
}

///|
async fn handshake(conn : @moonacp.Conn) -> @moonacp.Initialized {
  conn.initialize({
    protocol_version: @moonacp.protocol_version,
    client_capabilities: @moonacp.ClientCapabilities::none(),
    client_info: Some(@moonacp.Implementation::new("editor", "1.0")),
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
async test "initialize answers with the version and the capabilities the agent declares" {
  let (agent_wire, client_wire) = wire()
  let agent : &@moonacp.Agent = EchoAgent::new()
  let client : &@moonacp.Client = Recorder::new()
  let peer = @moonacp.serve(agent, agent_wire)
  let conn = @moonacp.connect(client, client_wire)
  let answer = @async.with_task_group(async fn(group) {
    group.spawn_bg(async fn() { peer.run() })
    group.spawn_bg(async fn() { conn.run() })
    defer agent_wire.shut()
    defer client_wire.shut()
    handshake(conn)
  })
  assert_eq(answer.protocol_version, @moonacp.protocol_version)
  assert_true(answer.capabilities.load_session)
  assert_true(answer.capabilities.prompt.image)
  assert_false(answer.capabilities.prompt.audio)
  assert_eq(answer.agent_info.map(info => info.name), Some("echo"))
}

///|
async test "a prompt streams its updates before the answer arrives" {
  let (agent_wire, client_wire) = wire()
  let agent = EchoAgent::new()
  let client = Recorder::new()
  let peer = @moonacp.serve(agent, agent_wire)
  let conn = @moonacp.connect(client, client_wire)
  @async.with_task_group(async fn(group) {
    group.spawn_bg(async fn() { peer.run() })
    group.spawn_bg(async fn() { conn.run() })
    defer agent_wire.shut()
    defer client_wire.shut()
    ignore(handshake(conn))
    let id = open_session(conn)
    let answer = conn.prompt({
      session_id: id,
      prompt: [@moonacp.Text({ text: "hi", annotations: None, meta: None, })],
      meta: None,
    })
    assert_true(answer.stop_reason == @moonacp.EndTurn)
  })
  assert_eq(client.updates.length(), 1)
  let (id, update) = client.updates[0]
  assert_eq(id, "s-1")
  guard update is @moonacp.AgentMessageChunk(chunk) else {
    abort("want an agent chunk")
  }
  guard chunk.content is @moonacp.Text(text) else { abort("want text") }
  assert_eq(text.text, "hello")
  assert_eq(agent.greeted, 1)
}

///|
async test "an unsupported method answers -32601 and leaves the connection usable" {
  let (agent_wire, client_wire) = wire()
  let agent : &@moonacp.Agent = EchoAgent::new()
  let client : &@moonacp.Client = Recorder::new()
  let peer = @moonacp.serve(agent, agent_wire)
  let conn = @moonacp.connect(client, client_wire)
  @async.with_task_group(async fn(group) {
    group.spawn_bg(async fn() { peer.run() })
    group.spawn_bg(async fn() { conn.run() })
    defer agent_wire.shut()
    defer client_wire.shut()
    ignore(handshake(conn))
    let code = try conn.logout() catch {
      @moonacp.Refused(code~, ..) => code
      _ => 0
    } noraise {
      _ => 0
    }
    assert_eq(code, @moonacp.method_not_found)
    // The connection still works afterwards.
    let id = open_session(conn)
    assert_eq(id, "s-1")
  })
}

///|
async test "cancel stops the turn and it answers cancelled" {
  let (agent_wire, client_wire) = wire()
  let agent = EchoAgent::new()
  agent.waited = true
  let client : &@moonacp.Client = Recorder::new()
  let peer = @moonacp.serve(agent, agent_wire)
  let conn = @moonacp.connect(client, client_wire)
  @async.with_task_group(async fn(group) {
    group.spawn_bg(async fn() { peer.run() })
    group.spawn_bg(async fn() { conn.run() })
    defer agent_wire.shut()
    defer client_wire.shut()
    ignore(handshake(conn))
    let id = open_session(conn)
    let answer = group.spawn(async fn() {
      conn.prompt({
        session_id: id,
        prompt: [@moonacp.Text({ text: "hi", annotations: None, meta: None, })],
        meta: None,
      })
    })
    conn.cancel(id)
    assert_eq(answer.wait().stop_reason.to_string(), "cancelled")
  })
}
