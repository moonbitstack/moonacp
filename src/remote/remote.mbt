// The editor's half of the remote transport: one connection, opened by its first `initialize`,
// kept open by the streams the answers arrive on, and ended by a DELETE.
//
// One task reads one stream, as the HTTP client underneath requires, so a connection runs inside
// `Remote::run`: every stream it opens gets a task of its own, and the peer reads one queue.

///|
/// How long a stream may go without a byte before the transport calls the connection dead. The
/// server writes a comment every fifteen seconds, so a minute of silence is nobody holding it.
pub let stream_ms : Int32 = 60000

///|
/// A connection to an agent across the network: the value `open` hands back.
pub struct Remote {
  http : @moonfetch.Client
  url : String
  headers : Array[(String, String)]
  timeout : Int32
  inbound : @aqueue.Queue[String]
  mut connection : String
  mut common : @moonfetch.Stream?
  mut sessions : Map[String, @moonfetch.Stream]
  /// The bytes of each stream that have arrived and not yet formed a whole event, keyed by the
  /// stream they came from — the empty key for the connection's own stream. Two streams are read
  /// by two tasks, and half an event from one must not be spliced onto the head of another.
  buffers : Map[String, Bytes]
  mut closed : Bool
  group : Ref[@async.TaskGroup[Unit]?]
  conn : Ref[@moonacp.Conn?]
}

///|
/// Talks to the agent at `url`, which is the endpoint itself — the path the server mounted the
/// application on, `/acp` by default. `headers` go on every request the transport makes, for a
/// deployment behind a proxy that wants a token of its own.
///
/// Nothing is sent until the first message: opening a connection does no I/O, so a program can
/// build it before the network is there, and `initialize` is what fails when it is not.
pub fn open(
  client : &@moonacp.Client,
  url : String,
  headers? : Array[(String, String)],
  timeout? : Int32,
) -> Remote raise @moonacp.Refused {
  let http = @moonfetch.Client::new() catch {
    _ =>
      raise @moonacp.Refused::Closed(reason="the HTTP client cannot be built")
  }
  let remote = Remote::{
    http,
    url,
    headers: headers.unwrap_or([]),
    timeout: timeout.unwrap_or(stream_ms),
    inbound: @aqueue.Queue::Queue(kind=@aqueue.Kind::Blocking(64)),
    connection: "",
    common: None,
    sessions: Map([]),
    buffers: Map([]),
    closed: false,
    group: Ref(None),
    conn: Ref(None),
  }
  let conn = @moonacp.connect(client, remote)
  remote.conn.val = Some(conn)
  remote
}

///|
/// The connection to talk through, for the calls this side makes.
pub fn Remote::conn(self : Remote) -> @moonacp.Conn {
  match self.conn.val {
    Some(conn) => conn
    None => abort("the transport was never wired to a connection")
  }
}

///|
/// Runs the connection until it ends: what the agent says arrives while this runs, and `close` (or
/// the stream ending) is what returns from it. Run it in a task of its own, as with every other
/// transport.
pub async fn Remote::run(self : Remote) -> Unit {
  @async.with_task_group(async fn(group) {
    self.group.val = Some(group)
    self.conn().run()
  })
}

///|
/// Ends the connection: the server drops what it holds for it, and the streams end.
pub async fn Remote::close(self : Remote) -> Unit {
  self.hang_up()
}

///|
/// The session a message belongs to, when it names one.
fn session_of(text : String) -> String? {
  let parsed = @moonjson.loads(text, @moonjson.strict) catch {
    _ => return None
  }
  guard parsed is Object(fields) else { return None }
  guard fields.get("params") is Some(Object(params)) else { return None }
  match params.get("sessionId") {
    Some(String(session)) => Some(session)
    _ => None
  }
}

///|
/// Gives up: the streams are let go, the queue is closed, and a reader waiting for a message is
/// told there will be no more.
///
/// A stream is not closed here. Its reader is a task of its own, and a stream closed from another
/// task leaves that reader waiting on it for ever; what actually ends them is the DELETE, which
/// the server answers by finishing the responses.
fn Remote::fail(self : Remote) -> Unit {
  if self.closed {
    return
  }
  self.closed = true
  self.common = None
  self.sessions = Map([])
  self.inbound.close()
}

///|
/// The heads a POST carries: the caller's, the content type, and the connection it belongs to once
/// there is one.
fn Remote::post_headers(self : Remote) -> Array[(String, String)] {
  let out = self.headers.copy()
  out.push(("content-type", "application/json"))
  if self.connection != "" {
    out.push(("acp-connection-id", self.connection))
  }
  out
}

///|
/// One event from a stream, with that stream's own carry-over of bytes that did not yet complete
/// one. A keepalive is skipped; `None` means the stream has ended.
async fn Remote::read_from(
  self : Remote,
  stream : @moonfetch.Stream,
  key : String,
) -> String? {
  let mut found : String? = None
  let mut reading = true
  while reading {
    let buffer = self.buffers.get(key).unwrap_or(Bytes::new(0))
    match event_end(buffer) {
      Some((at, width)) => {
        let frame = buffer.exact_view(start=0, end=at)
        self.buffers[key] = buffer.exact_view(start=at + width).to_owned()
        if event_text(frame) is Some(text) {
          found = Some(text)
          reading = false
        }
      }
      None => {
        let chunk = stream.next() catch { _ => None }
        match chunk {
          None => reading = false
          Some(@moonfetch.Chunk::Data(bytes)) =>
            self.buffers[key] = buffer + bytes
          Some(@moonfetch.Chunk::End(_)) => reading = false
        }
      }
    }
  }
  found
}

///|
/// Reads one stream until it ends, handing each message to the peer through the one queue. The
/// connection's own stream ending is the connection ending; a session's stream ending is that
/// session ending, and the rest of the connection goes on.
async fn Remote::pump(
  self : Remote,
  stream : @moonfetch.Stream,
  key : String,
) -> Unit {
  let mut open = true
  while open {
    match self.read_from(stream, key) {
      Some(text) => self.inbound.put(text) catch { _ => open = false }
      None => open = false
    }
  }
  if key == "" {
    self.fail()
  } else {
    self.sessions.remove(key)
  }
}

///|
/// Starts reading a stream in a task of its own, or says that there is no task group to start it
/// in — a connection whose `run` is not running cannot receive anything.
fn Remote::spawn_pump(
  self : Remote,
  stream : @moonfetch.Stream,
  key : String,
) -> Bool {
  match self.group.val {
    Some(group) => {
      group.spawn_bg(async fn() { self.pump(stream, key) }, no_wait=true)
      true
    }
    None => false
  }
}

///|
/// Opens the stream a session's messages arrive on. A session's stream is where its turn's updates
/// and its call's answer go, so it is opened before the call that needs it, not after.
async fn Remote::open_session(self : Remote, session : String) -> Bool {
  if self.sessions.contains(session) {
    return true
  }
  let stream = self.http.stream(
    @method.Get,
    self.url,
    headers=[
      ("accept", "text/event-stream"),
      ("acp-connection-id", self.connection),
      ("acp-session-id", session),
    ],
    timeout=self.timeout,
  )
  if stream.status() != 200 {
    stream.close()
    return false
  }
  self.sessions[session] = stream
  self.spawn_pump(stream, session)
}

///|
/// Opens the connection's own stream, which carries everything that belongs to no session:
/// `initialize` beyond its answer, `session/new`, and the answers to calls that name none.
async fn Remote::open_common(self : Remote) -> Bool {
  let stream = self.http.stream(
    @method.Get,
    self.url,
    headers=[
      ("accept", "text/event-stream"),
      ("acp-connection-id", self.connection),
    ],
    timeout=self.timeout,
  )
  if stream.status() != 200 {
    stream.close()
    return false
  }
  self.common = Some(stream)
  self.spawn_pump(stream, "")
}

///|
/// Sends what the editor says. The answer to `initialize` comes back in this response and is the
/// message that opens the connection; every other answer arrives on a stream, so the POST itself
/// only says whether it was taken.
async fn Remote::send(self : Remote, text : String) -> Unit {
  if self.connection != "" {
    // A call that names a session is answered on that session's stream, and its updates arrive
    // there too, so the stream has to be open before the call goes out.
    if session_of(text) is Some(session) {
      if !self.open_session(session) {
        self.fail()
        return
      }
    } else if self.common is None {
      if !self.open_common() {
        self.fail()
        return
      }
    }
  }
  let response = self.http.post(
    self.url,
    body=@moonfetch.Body::Text(text),
    headers=self.post_headers(),
  ) catch {
    _ => {
      self.fail()
      return
    }
  }
  match response.status {
    200 => {
      match response.header("acp-connection-id") {
        Some(id) => self.connection = id
        None => ()
      }
      let answer = response.text()
      if answer != "" {
        self.inbound.put(answer) catch {
          _ => ()
        }
      }
    }
    // Taken, and the answer goes out on a stream.
    202 => ()
    _ => self.fail()
  }
}

///|
/// Ends the exchange: the streams are given up and the server is told the connection is over,
/// which is what releases what it holds for it.
async fn Remote::hang_up(self : Remote) -> Unit {
  // The DELETE goes first: it is what ends the streams on the server's side, and a stream that is
  // being read only returns once something arrives on it.
  if self.connection != "" {
    let reply = self.http.delete(self.url, headers=[
      ("acp-connection-id", self.connection),
    ]) catch {
      _ => {
        self.fail()
        return
      }
    }
    ignore(reply)
    self.connection = ""
  }
  self.fail()
}

///|
impl @peer.Frames for Remote with fn read(self) {
  let text = self.inbound.get() catch { _ => return None }
  Some(text)
}

///|
impl @peer.Frames for Remote with fn write(self, text) {
  self.send(text)
}
