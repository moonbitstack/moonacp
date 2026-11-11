// What the transport refuses rather than buffers without bound, and one connection's plumbing: the
// peer answering the agent's side, the queues feeding each stream, and the routing between them.

///|
/// The transport's bounds.
#derive(Eq)
pub(all) struct Limits {
  body_bytes : Int32
  backlog : Int32
  keepalive_ms : Int32
  reply_ms : Int32
}

///|
pub extend Limits with Eq::{equal, not_equal}

///|
/// The defaults: 1 MiB bodies, 256 buffered messages per stream, a keepalive every 15 seconds, and
/// half a minute for `initialize`.
pub let limits : Limits = {
  body_bytes: 1048576,
  backlog: 256,
  keepalive_ms: 15000,
  reply_ms: 30000,
}

///|
/// Messages a queue holds. A client that stops reading its stream loses the oldest messages rather
/// than growing the server's memory; the RFD leaves redelivery to v2.
fn stream_queue(backlog : Int32) -> @aqueue.Queue[String] {
  @aqueue.Queue::Queue(kind=@aqueue.Kind::DiscardOldest(backlog))
}

///|
/// Where a message goes: the stream of one session, the connection's own stream, or a POST that is
/// waiting for this very answer.
priv struct Routes {
  common : @aqueue.Queue[String]
  scopes : Map[String, @aqueue.Queue[String]]
  waiting : Map[String, @aqueue.Queue[String]]
  owners : Map[String, String]
  backlog : Int32
  /// A WebSocket has one channel, so every message goes out on the connection's queue.
  mut unified : Bool
}

///|
/// The routing key of a JSON-RPC identifier, the same text for the same identifier whichever form
/// it was written in.
fn id_key(json : Json) -> String {
  match json {
    String(text) => "s:\{text}"
    Number(number, repr~) =>
      match repr {
        Some(text) => "n:\{text}"
        None => "n:\{number}"
      }
    Null => "null"
    _ => "?"
  }
}

///|
/// A message's identifier, if it has one.
fn id_of(json : Json) -> String? {
  guard json is Object(fields) else { return None }
  match fields.get("id") {
    Some(id) => Some(id_key(id))
    None => None
  }
}

///|
/// The session a message belongs to: the one its parameters name. A result never counts, because the
/// answer to `session/new` has to travel on the connection's own stream — the client has no session
/// stream for that session yet.
fn session_of(json : Json) -> String? {
  guard json is Object(fields) else { return None }
  if fields.get("params") is Some(Object(params)) {
    if params.get("sessionId") is Some(String(id)) {
      return Some(id)
    }
  }
  None
}

///|
fn Routes::scope(self : Routes, session_id : String) -> @aqueue.Queue[String] {
  match self.scopes.get(session_id) {
    Some(queue) => queue
    None => {
      let queue = stream_queue(self.backlog)
      self.scopes[session_id] = queue
      queue
    }
  }
}

///|
/// The stream of a session, when the client has one open. A message for a session whose stream is
/// not open goes to the connection's own stream instead: an answer must not be lost because a
/// client chose to read one stream rather than one per session, which is what the transport's own
/// rules say happens.
fn Routes::open_scope(
  self : Routes,
  session_id : String,
) -> @aqueue.Queue[String]? {
  self.scopes.get(session_id)
}

///|
/// Sends a message on its way: to the POST waiting for it, else to the stream of its session when
/// that stream is open, else to the connection's stream.
fn Routes::deliver(self : Routes, text : String) -> Unit {
  let json = @json.parse(text) catch { _ => return }
  if id_of(json) is Some(key) {
    if self.waiting.get(key) is Some(queue) {
      offer(queue, text)
      return
    }
  }
  if self.unified {
    offer(self.common, text)
    return
  }
  let session = session_of(json)
  if id_of(json) is Some(key) {
    if self.owners.get(key) is Some(session_id) {
      if self.open_scope(session_id) is Some(queue) {
        offer(queue, text)
        return
      }
    }
  }
  if session is Some(session_id) {
    if self.open_scope(session_id) is Some(queue) {
      offer(queue, text)
      return
    }
  }
  offer(self.common, text)
}

///|
/// Hands a message to a queue without waiting. A full stream has already started dropping; the
/// alternative is a server that stalls because one client stopped reading.
fn offer(queue : @aqueue.Queue[String], text : String) -> Unit {
  ignore(queue.try_put(text) catch { _ => false })
}

///|
/// The peer's transport: what POSTs put in, and what the router decides to do with what comes out.
priv struct Wire {
  inbound : @aqueue.Queue[String]
  routes : Routes
}

///|
impl @peer.Frames for Wire with fn read(self) {
  let text = self.inbound.get() catch { _ => return None }
  Some(text)
}

///|
impl @peer.Frames for Wire with fn write(self, text) {
  self.routes.deliver(text)
}

///|
/// One open connection: what it routes. A peer is made per task that pumps it, because a peer that
/// has stopped reading cannot start again, while the connection outlives any single stream.
priv struct Connection {
  id : String
  wire : Wire
}

///|
fn Connection::new(id : String, limits : Limits) -> Connection {
  ignore(limits)
  let routes = {
    common: stream_queue(limits.backlog),
    scopes: Map([]),
    waiting: Map([]),
    owners: Map([]),
    backlog: limits.backlog,
    unified: false,
  }
  let inbound : @aqueue.Queue[String] = @aqueue.Queue::Queue(
    kind=@aqueue.Kind::Blocking(limits.backlog),
  )
  { id, wire: { inbound, routes, }, }
}

///|
/// Runs the agent's side of the connection on this transport until the connection is closed. Each
/// stream calls this once: the message loop has to be alive for anything to be answered.
async fn Connection::pump(self : Connection, agent : &@moonacp.Agent) -> Unit {
  let peer = @moonacp.serve(agent, self.wire)
  peer.run()
}

///|
/// Takes a POST body in. A request names the session it belongs to, so its answer finds the right
/// stream.
async fn Connection::post(self : Connection, text : String) -> Unit {
  let json = @json.parse(text) catch { _ => return }
  if json is Object(fields) {
    if fields.get("id") is Some(id) {
      let key = id_key(id)
      let named = match fields.get("method") {
        Some(String(name)) => name
        _ => ""
      }
      if named != "initialize" {
        if session_of(json) is Some(session_id) {
          self.wire.routes.owners[key] = session_id
        }
      }
    }
  }
  self.wire.inbound.put(text) catch {
    _ => ()
  }
}

///|
/// Closes everything this connection holds: the peer stops reading, and every stream ends.
fn Connection::close(self : Connection) -> Unit {
  self.wire.inbound.close()
  self.wire.routes.common.close()
  for entry in self.wire.routes.scopes.iter() {
    let (_, queue) = entry
    queue.close()
  }
  for entry in self.wire.routes.waiting.iter() {
    let (_, queue) = entry
    queue.close()
  }
}
