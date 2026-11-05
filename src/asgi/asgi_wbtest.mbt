// Driving the app the way an ASGI server does: one event stream in, one out, per request.

///|
/// The two ends of one request: what the server sends the app, and what the app sends back.
struct Side {
  inbox : @aqueue.Queue[@spec.Event]
  outbox : @aqueue.Queue[@spec.Event]
}

///|
fn Side::new() -> Side {
  {
    inbox: @aqueue.Queue::Queue(kind=@aqueue.Kind::Blocking(32)),
    outbox: @aqueue.Queue::Queue(kind=@aqueue.Kind::Blocking(64)),
  }
}

///|
/// Starts the app for one scope and hands back the two ends.
fn Side::start(
  self : Side,
  app : @moonasgi.AsgiApp,
  group : @async.TaskGroup[Unit],
  scope : @spec.Scope,
) -> Unit {
  group.spawn_bg(
    async fn() {
      app(scope, async fn() { self.inbox.get() }, async fn(event) {
        self.outbox.put(event)
      })
    },
    allow_failure=true,
  )
}

///|
fn http_scope(verb : String, headers : Array[(String, String)]) -> @spec.Scope {
  Http(@moonasgi.HttpScope::new(http_method=verb, path="/acp", headers~))
}

///|
/// Sends a POST and reads the two events a whole response takes.
async fn post(
  app : @moonasgi.AsgiApp,
  group : @async.TaskGroup[Unit],
  body : String,
  headers : Array[(String, String)],
) -> (Int32, Array[(String, String)], String) {
  let side = Side::new()
  side.start(app, group, http_scope("POST", headers))
  side.inbox.put(HttpRequest(body=@utf8.encode(body), more_body=false))
  let start = side.outbox.get()
  guard start is HttpResponseStart(status~, headers~, ..) else {
    abort("no response start")
  }
  let chunk = side.outbox.get()
  let text = match chunk {
    HttpResponseBody(body~, ..) => @utf8.decode_lossy(body)
    _ => ""
  }
  ignore(status)
  (status, headers, text)
}

///|
fn header_of(headers : Array[(String, String)], name : String) -> String? {
  for entry in headers {
    let (key, value) = entry
    if key.to_lower() == name.to_lower() {
      return Some(value)
    }
  }
  None
}

///|
/// Reads one SSE frame: everything up to the blank line.
async fn frame(side : Side) -> String {
  let mut text = ""
  while true {
    guard side.outbox.get() is HttpResponseBody(body~, ..) else {
      abort("stream closed")
    }
    text = text + @utf8.decode_lossy(body)
    if text.contains("\r\n\r\n") {
      return text
    }
  }
  text
}

///|
/// The payload of a frame, without the `data: ` prefix.
fn payload(frame : String) -> String {
  frame
  .replace_all(old="data: ", new="")
  .replace_all(old="\r\n\r\n", new="")
  .trim()
  .to_owned()
}

///|
/// An agent that answers one turn with one update.
struct Echo {
  mut sessions : Int32
}

///|
impl @moonacp.Agent for Echo with fn initialize(self, request) {
  ignore(self)
  ignore(request)
  @moonacp.Initialized::new()
}

///|
impl @moonacp.Agent for Echo with fn new_session(self, request) {
  ignore(request)
  self.sessions = self.sessions + 1
  {
    session_id: "s-\{self.sessions}",
    modes: None,
    config_options: None,
    meta: None,
  }
}

///|
impl @moonacp.Agent for Echo with fn prompt(self, request, session) {
  ignore(self)
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

///|
async test "initialize answers in the POST and names the connection" {
  let agent = Echo::{ sessions: 0, }
  let app = to_asgi(agent)
  @async.with_task_group(async fn(group) {
    let (status, headers, body) = post(
      app,
      group,
      "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":1}}",
      [("content-type", "application/json")],
    )
    assert_eq(status, 200)
    assert_true(header_of(headers, "acp-connection-id") is Some(_))
    let reply = @json.parse(body) catch { _ => abort("not json") }
    guard reply is Object(fields) else { abort("not an object") }
    assert_true(fields.get("result") is Some(_))
  })
}

///|
async test "a POST without a connection is refused, and a plain type is not JSON" {
  let agent = Echo::{ sessions: 0, }
  let app = to_asgi(agent)
  @async.with_task_group(async fn(group) {
    let (status, _, _) = post(app, group, "{}", [("content-type", "text/plain")])
    assert_eq(status, 415)
  })
  @async.with_task_group(async fn(group) {
    let (status, _, _) = post(
      app,
      group,
      "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"session/new\",\"params\":{\"cwd\":\"/w\",\"mcpServers\":[]}}",
      [("content-type", "application/json")],
    )
    assert_eq(status, 400)
  })
}

///|
async test "a batch body is refused with one -32600" {
  let agent = Echo::{ sessions: 0, }
  let app = to_asgi(agent)
  @async.with_task_group(async fn(group) {
    let (status, _, body) = post(
      app,
      group,
      "[{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\"}]",
      [("content-type", "application/json")],
    )
    assert_eq(status, 400)
    assert_true(body.contains("-32600"))
  })
}

///|
async test "a session stream carries the updates and the answer of its POSTs" {
  let agent = Echo::{ sessions: 0, }
  let app = to_asgi(agent)
  let stream_side = Side::new()
  @async.with_task_group(async fn(group) {
    let (_, headers, _) = post(
      app,
      group,
      "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":1}}",
      [("content-type", "application/json")],
    )
    let connection = match header_of(headers, "acp-connection-id") {
      Some(id) => id
      None => abort("no connection id")
    }
    // The connection stream answers session/new.
    let common = Side::new()
    common.start(
      app,
      group,
      http_scope("GET", [
        ("accept", "text/event-stream"),
        ("acp-connection-id", connection),
      ]),
    )
    common.inbox.put(HttpRequest(body=Bytes::new(0), more_body=false))
    guard common.outbox.get() is HttpResponseStart(status~, ..) else {
      abort("no stream")
    }
    assert_eq(status, 200)

    // session/new is a call, so it needs a POST of its own.
    let (status, _, detail) = post(
      app,
      group,
      "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"session/new\",\"params\":{\"cwd\":\"/work\",\"mcpServers\":[]}}",
      [("content-type", "application/json"), ("acp-connection-id", connection)],
    )
    assert_eq(detail, "")
    assert_eq(status, 202)
    let new_session = payload(frame(common))
    assert_true(new_session.contains("\"s-1\""))

    // The session stream carries the turn.
    stream_side.start(
      app,
      group,
      http_scope("GET", [
        ("accept", "text/event-stream"),
        ("acp-connection-id", connection),
        ("acp-session-id", "s-1"),
      ]),
    )
    stream_side.inbox.put(HttpRequest(body=Bytes::new(0), more_body=false))
    guard stream_side.outbox.get() is HttpResponseStart(..) else {
      abort("no stream")
    }

    let (status, _, _) = post(
      app,
      group,
      "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"session/prompt\",\"params\":{\"sessionId\":\"s-1\",\"prompt\":[{\"type\":\"text\",\"text\":\"hi\"}]}}",
      [
        ("content-type", "application/json"),
        ("acp-connection-id", connection),
        ("acp-session-id", "s-1"),
      ],
    )
    assert_eq(status, 202)
    let update = payload(frame(stream_side))
    assert_true(update.contains("agent_message_chunk"))
    let answer = payload(frame(stream_side))
    assert_true(answer.contains("end_turn"))
    stream_side.inbox.put(HttpDisconnect) catch {
      _ => ()
    }
    common.inbox.put(HttpDisconnect) catch {
      _ => ()
    }
  })
}

///|
async test "a WebSocket carries the whole conversation" {
  let agent = Echo::{ sessions: 0, }
  let app = to_asgi(agent)
  let side = Side::new()
  @async.with_task_group(async fn(group) {
    side.start(
      app,
      group,
      WebSocket(
        @moonasgi.WebSocketScope::new(path="/acp", headers=[
          ("host", "localhost"),
        ]),
      ),
    )
    side.inbox.put(WebSocketConnect)
    guard side.outbox.get() is WebSocketAccept(..) else {
      abort("not accepted")
    }
    side.inbox.put(
      WebSocketReceive(
        text=Some(
          "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":1}}",
        ),
        bytes=None,
      ),
    )
    let reply = match side.outbox.get() {
      WebSocketSendText(text) => text
      _ => abort("no reply")
    }
    assert_true(reply.contains("\"result\""))
    side.inbox.put(WebSocketDisconnect(code=1000, reason=None))
  })
}
