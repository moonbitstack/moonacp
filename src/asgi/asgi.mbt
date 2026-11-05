// The remote transport: one `/acp` endpoint taking POSTs, opening long-lived SSE streams, upgrading
// to a WebSocket, and terminating on DELETE.
//
// https://agentclientprotocol.com/rfds/streamable-http-websocket-transport — revision of 2026-11-04,
// status Active, not final.

///|
/// A case-insensitive header lookup, which is what HTTP is.
fn header(headers : Array[(String, String)], name : String) -> String? {
  let wanted = name.to_lower()
  for entry in headers {
    let (key, value) = entry
    if key.to_lower() == wanted {
      return Some(value)
    }
  }
  None
}

///|
/// Whether a comma-separated header carries a token, ignoring any parameters after `;`.
fn has_token(
  headers : Array[(String, String)],
  name : String,
  token : String,
) -> Bool {
  guard header(headers, name) is Some(value) else { return false }
  let wanted = token.to_lower()
  for part in value.split(",") {
    let bare = match part.find(";") {
      Some(at) => part[0:at].to_owned()
      None => part.to_owned()
    }
    if bare.trim().to_lower() == wanted {
      return true
    }
  }
  false
}

///|
/// The registries one app keeps: connections by identifier, and the counter that names them.
priv struct Registry {
  mut next : Int32
  connections : Map[String, Connection]
}

///|
fn Registry::name(self : Registry) -> String {
  self.next = self.next + 1
  "acp-\{self.next}-\{@async.now()}"
}

///|
/// An HTTP response, written whole.
async fn respond(
  send : @spec.Send,
  status : Int32,
  headers : Array[(String, String)],
  body : String,
) -> Unit {
  send(HttpResponseStart(status~, headers~, trailers=false))
  send(HttpResponseBody(body=@utf8.encode(body), more_body=false))
}

///|
/// A JSON-RPC error object with nobody's identifier: for a body that is not a message at all.
fn bare_error(code : Int32, message : String) -> String {
  Json::object({
    "jsonrpc": Json::string("2.0"),
    "id": Json::null(),
    "error": Json::object({
      "code": Json::number(code.to_double()),
      "message": Json::string(message),
    }),
  }).stringify()
}

///|
/// Reads a request body, refusing one over the limit instead of holding it.
async fn read_body(receive : @spec.Receive, limit : Int32) -> String? {
  let chunks = []
  let mut total = 0
  let mut done = false
  while !done {
    let event = receive()
    if event is HttpRequest(body~, more_body~) {
      total = total + body.length()
      if total > limit {
        return None
      }
      chunks.push(body)
      done = !more_body
    } else if event is HttpDisconnect {
      return None
    } else {
      done = true
    }
  }
  let mut joined = Bytes::new(0)
  for chunk in chunks {
    joined = joined.add(chunk)
  }
  Some(@utf8.decode_lossy(joined))
}

///|
/// One SSE frame: the message on `data`, a blank line after it.
fn sse_frame(text : String) -> Bytes {
  @utf8.encode(
    "data: " + text.replace_all(old="\n", new="\r\ndata: ") + "\r\n\r\n",
  )
}

///|
/// Holds a stream open: whatever the router hands this queue goes out as an SSE frame, a keepalive
/// goes out when nothing does, and the stream ends when the client disconnects.
async fn stream_out(
  send : @spec.Send,
  receive : @spec.Receive,
  queue : @aqueue.Queue[String],
  headers : Array[(String, String)],
  keepalive_ms : Int32,
) -> Unit {
  send(HttpResponseStart(status=200, headers~, trailers=false))
  @async.with_task_group(async fn(group) {
    group.spawn_bg(async fn() {
      while true {
        match receive() {
          HttpDisconnect => break
          _ => ()
        }
      }
      queue.close()
    })
    while true {
      let message = @async.with_timeout_opt(keepalive_ms, () => queue.get()) catch {
        _ => break
      }
      match message {
        Some(text) =>
          send(HttpResponseBody(body=sse_frame(text), more_body=true)) catch {
            _ => break
          }
        None =>
          send(HttpResponseBody(body=b": keepalive\r\n\r\n", more_body=true)) catch {
            _ => break
          }
      }
    }
  })
  send(HttpResponseBody(body=Bytes::new(0), more_body=false)) catch {
    _ => ()
  }
}

///|
/// Serves an agent over ASGI: one path, four verbs, and a WebSocket upgrade. Nothing is global, so
/// several agents can be mounted side by side.
pub fn to_asgi(
  agent : &@moonacp.Agent,
  path~ : String = "/acp",
  hosts? : Array[String],
  limits~ : Limits = limits,
) -> @moonasgi.AsgiApp {
  let registry : Registry = { next: 0, connections: Map([]), }
  async fn(scope, receive, send) {
    match scope {
      Lifespan(_) => {
        match receive() {
          LifespanStartup => send(LifespanStartupComplete) catch { _ => () }
          _ => ()
        }
        match receive() {
          LifespanShutdown => send(LifespanShutdownComplete) catch { _ => () }
          _ => ()
        }
      }
      Http(http) =>
        if http.path != path {
          respond(send, 404, [], "")
        } else {
          match allowed_host(hosts, http.headers) {
            Some(_) => handle_http(agent, registry, http, receive, send, limits)
            None => respond(send, 403, [], "")
          }
        }
      WebSocket(websocket) =>
        if websocket.path != path {
          send(WebSocketClose(code=1404, reason="not found")) catch {
            _ => ()
          }
        } else {
          handle_websocket(agent, registry, receive, send, limits)
        }
    }
  }
}

///|
/// Whether the request came in under a host the app serves. `hosts` empty means any.
fn allowed_host(
  hosts : Array[String]?,
  headers : Array[(String, String)],
) -> Unit? {
  guard hosts is Some(allowed) else { return Some(()) }
  guard header(headers, "host") is Some(host) else { return None }
  let bare = match host.find(":") {
    Some(at) => host[0:at].to_owned()
    None => host
  }
  if allowed.contains(bare) {
    Some(())
  } else {
    None
  }
}

///|
async fn handle_http(
  agent : &@moonacp.Agent,
  registry : Registry,
  http : @moonasgi.HttpScope,
  receive : @spec.Receive,
  send : @spec.Send,
  limits : Limits,
) -> Unit {
  match http.http_method {
    "POST" => handle_post(agent, registry, http, receive, send, limits)
    "GET" => handle_get(agent, registry, http, receive, send, limits)
    "DELETE" =>
      match header(http.headers, "acp-connection-id") {
        None => respond(send, 400, [], "")
        Some(id) =>
          match registry.connections.get(id) {
            None => respond(send, 404, [], "")
            Some(connection) => {
              registry.connections.remove(id)
              connection.close()
              respond(send, 202, [], "")
            }
          }
      }
    _ => respond(send, 405, [("allow", "GET, POST, DELETE")], "")
  }
}

///|
async fn handle_post(
  agent : &@moonacp.Agent,
  registry : Registry,
  http : @moonasgi.HttpScope,
  receive : @spec.Receive,
  send : @spec.Send,
  limits : Limits,
) -> Unit {
  if !has_token(http.headers, "content-type", "application/json") {
    respond(send, 415, [], "") catch {
      _ => ()
    }
    return
  }
  let body = match read_body(receive, limits.body_bytes) {
    Some(body) => body
    None => {
      respond(send, 413, [], "")
      return
    }
  }
  let parsed = @json.parse(body) catch {
    _ => {
      respond(send, 400, [], bare_error(@moonacp.parse_error, "Parse error"))
      return
    }
  }
  if parsed is Array(_) {
    respond(
      send,
      400,
      [],
      bare_error(@moonacp.invalid_request, "Invalid Request"),
    ) catch {
      _ => ()
    }
    return
  }
  let named = match parsed {
    Object(fields) =>
      match fields.get("method") {
        Some(String(name)) => name
        _ => ""
      }
    _ => ""
  }
  if named == "initialize" && header(http.headers, "acp-connection-id") is None {
    initialize(agent, registry, body, send, limits)
    return
  }
  let connection = match header(http.headers, "acp-connection-id") {
    Some(id) =>
      match registry.connections.get(id) {
        Some(connection) => connection
        None => {
          respond(send, 404, [], "") catch {
            _ => ()
          }
          return
        }
      }
    None => {
      respond(send, 400, [], "") catch {
        _ => ()
      }
      return
    }
  }
  if header(http.headers, "acp-session-id") is Some(session) {
    if session_of(parsed) is Some(claimed) && claimed != session {
      respond(
        send,
        400,
        [],
        bare_error(@moonacp.invalid_request, "Invalid Request"),
      ) catch {
        _ => ()
      }
      return
    }
    if session_of(parsed) is None {
      respond(
        send,
        400,
        [],
        bare_error(@moonacp.invalid_request, "Invalid Request"),
      ) catch {
        _ => ()
      }
      return
    }
  }
  connection.post(body)
  respond(send, 202, [], "") catch {
    _ => ()
  }
}

///|
/// `initialize` is the one POST that answers directly: the client needs the connection identifier
/// before it can open a stream.
async fn initialize(
  agent : &@moonacp.Agent,
  registry : Registry,
  body : String,
  send : @spec.Send,
  limits : Limits,
) -> Unit {
  let connection = Connection::new(registry.name(), limits)
  let key = @json.parse(body) catch { _ => return }
  let waited = match id_of(key) {
    Some(key) => key
    None => "null"
  }
  let answer : @aqueue.Queue[String] = @aqueue.Queue::Queue(
    kind=@aqueue.Kind::Blocking(4),
  )
  connection.wire.routes.waiting[waited] = answer
  registry.connections[connection.id] = connection
  let reply = @async.with_task_group(async fn(group) {
    group.spawn_bg(async fn() { connection.pump(agent) }, no_wait=true)
    connection.post(body)
    let outcome = @async.with_timeout_opt(limits.reply_ms, () => answer.get()) catch {
      _ => None
    }
    match outcome {
      Some(text) => text
      None => ""
    }
  })
  let headers : Array[(String, String)] = [
    ("content-type", "application/json"),
    ("acp-connection-id", connection.id),
  ]
  respond(send, 200, headers, reply) catch {
    _ => ()
  }
}

///|
async fn handle_get(
  agent : &@moonacp.Agent,
  registry : Registry,
  http : @moonasgi.HttpScope,
  receive : @spec.Receive,
  send : @spec.Send,
  limits : Limits,
) -> Unit {
  if !has_token(http.headers, "accept", "text/event-stream") {
    respond(send, 406, [], "") catch {
      _ => ()
    }
    return
  }
  let connection = match header(http.headers, "acp-connection-id") {
    Some(id) =>
      match registry.connections.get(id) {
        Some(connection) => connection
        None => {
          respond(send, 404, [], "") catch {
            _ => ()
          }
          return
        }
      }
    None => {
      respond(send, 400, [], "") catch {
        _ => ()
      }
      return
    }
  }
  let queue = match header(http.headers, "acp-session-id") {
    Some(session) =>
      if connection.knows(session) {
        connection.wire.routes.scope(session)
      } else {
        respond(send, 404, [], "") catch {
          _ => ()
        }
        return
      }
    None => connection.wire.routes.common
  }
  let headers : Array[(String, String)] = [
    ("content-type", "text/event-stream"),
    ("cache-control", "no-store"),
    ("x-accel-buffering", "no"),
  ]
  @async.with_task_group(async fn(group) {
    group.spawn_bg(async fn() { connection.pump(agent) }, no_wait=true)
    stream_out(send, receive, queue, headers, limits.keepalive_ms)
  })
}

///|
/// A WebSocket carries the same messages as the streams, so one queue serves the whole connection.
async fn handle_websocket(
  agent : &@moonacp.Agent,
  registry : Registry,
  receive : @spec.Receive,
  send : @spec.Send,
  limits : Limits,
) -> Unit {
  match receive() {
    WebSocketConnect => ()
    _ => return
  }
  let connection = Connection::new(registry.name(), limits)
  connection.wire.routes.unified = true
  registry.connections[connection.id] = connection
  send(
    WebSocketAccept(subprotocol=None, headers=[
      ("acp-connection-id", connection.id),
    ]),
  ) catch {
    _ => ()
  }
  @async.with_task_group(async fn(group) {
    group.spawn_bg(async fn() { connection.pump(agent) }, no_wait=true)
    group.spawn_bg(async fn() {
      while true {
        let text = connection.wire.routes.common.get() catch { _ => break }
        send(WebSocketSendText(text)) catch {
          _ => break
        }
      }
    })
    while true {
      match receive() {
        WebSocketReceive(text=Some(text), ..) => connection.post(text)
        WebSocketReceive(bytes=Some(_), ..) => ()
        WebSocketDisconnect(code~, ..) => {
          registry.connections.remove(connection.id)
          connection.close()
          ignore(code)
          break
        }
        _ => break
      }
    }
  })
}
