// The agent's half of a session: the handle a prompt uses to talk back to the client.

///|
/// A call to the client, with the peer's failures turned into ours.
async fn call_peer(
  peer : @peer.Peer,
  name : String,
  params : Json,
) -> Json raise Refused {
  peer.call(name, params~) catch {
    @moonjrpc.Failed(failure) => raise refused_of(failure)
    @moonjrpc.TimedOut(name~, ..) =>
      raise Refused::Closed(reason="\{name} timed out")
    _ => raise Refused::Closed(reason="\{name}: the client is gone")
  }
}

///|
/// A notice to the client, with the peer's failures turned into ours.
async fn notify_peer(
  peer : @peer.Peer,
  name : String,
  params : Json,
) -> Unit raise Refused {
  peer.notify(name, params~) catch {
    @moonjrpc.Failed(failure) => raise refused_of(failure)
    @moonjrpc.TimedOut(name~, ..) =>
      raise Refused::Closed(reason="\{name} timed out")
    _ => raise Refused::Closed(reason="\{name}: the client is gone")
  }
}

///|
/// One session, as the agent sees it inside `prompt`. Everything here is a call to the client:
/// updates, permission, files, terminals, elicitation.
pub struct Session {
  peer : @peer.Peer
  id : String
}

///|
/// The session's identifier, the one the client sent with `session/new`.
pub fn Session::id(self : Session) -> String {
  self.id
}

///|
/// Sends one update. Updates are notifications, so they are never answered and never fail the turn
/// by themselves; the connection going away raises `Closed`.
pub async fn Session::update(
  self : Session,
  update : SessionUpdate,
) -> Unit raise Refused {
  let params = json_of([
    ("sessionId", Some(Json::string(self.id))),
    ("update", Some(write(update))),
  ])
  notify_peer(self.peer, "session/update", params)
}

///|
/// Asks the user to allow a tool call. The client answers with the option it picked, or `Cancelled`
/// when the prompt was dismissed; a client that never answers blocks the turn, so keep the ask in
/// the turn's own task.
pub async fn Session::request_permission(
  self : Session,
  ask : Permission,
) -> Outcome raise Refused {
  let params = merge_json(
    write(ask),
    json_of([("sessionId", Some(Json::string(self.id)))]),
  )
  read_root(call_peer(self.peer, "session/request_permission", params))
}

///|
/// Reads a text file through the client, sliced from `line` when one is given.
pub async fn Session::read_text_file(
  self : Session,
  path : String,
  line? : Int64,
  limit? : Int64,
) -> String raise Refused {
  let params = json_of([
    ("sessionId", Some(Json::string(self.id))),
    ("path", Some(Json::string(path))),
    ("line", json_int(line)),
    ("limit", json_int(limit)),
  ])
  let reply : FileText = read_root(
    call_peer(self.peer, "fs/read_text_file", params),
  )
  reply.content
}

///|
/// Writes a text file through the client.
pub async fn Session::write_text_file(
  self : Session,
  path : String,
  content : String,
) -> Unit raise Refused {
  let params = json_of([
    ("sessionId", Some(Json::string(self.id))),
    ("path", Some(Json::string(path))),
    ("content", Some(Json::string(content))),
  ])
  ignore(call_peer(self.peer, "fs/write_text_file", params))
}

///|
/// Runs a command in a terminal the client owns. The returned handle reads, waits for, kills and
/// releases it.
pub async fn Session::terminal(
  self : Session,
  command : String,
  args? : Array[String],
  env? : Array[EnvVariable],
  cwd? : String,
  output_byte_limit? : Int64,
) -> Terminal raise Refused {
  let params = json_of([
    ("sessionId", Some(Json::string(self.id))),
    ("command", Some(Json::string(command))),
    ("args", json_list(args, Json::string)),
    ("env", json_list_of(env)),
    ("cwd", json_string(cwd)),
    ("outputByteLimit", json_int(output_byte_limit)),
  ])
  let opened : TerminalOpened = read_root(
    call_peer(self.peer, "terminal/create", params),
  )
  Terminal::{ session: self, terminal_id: opened.terminal_id, }
}

///|
/// Asks the user for a few fields or for a visit to a URL. The ask is scoped to this session, and to
/// the tool call it came from when one is given.
pub async fn Session::elicit(
  self : Session,
  ask : Elicitation,
) -> Answer raise Refused {
  let params = match ask {
    Form(request) =>
      write(
        Form({
          ..request,
          scope: ElicitScope::OfSession(self.id, request.scope.tool_call_id()),
        }),
      )
    Url(request) =>
      write(
        Url({
          ..request,
          scope: ElicitScope::OfSession(self.id, request.scope.tool_call_id()),
        }),
      )
  }
  read_root(call_peer(self.peer, "elicitation/create", params))
}

///|
/// The tool call an elicitation is tied to, when the ask came from one.
fn ElicitScope::tool_call_id(self : ElicitScope) -> String? {
  match self {
    OfSession(_, tool_call_id) => tool_call_id
    OfRequest(_) => None
  }
}

///|
/// A command running in a terminal the client owns. Holding one is not owning a process: `release`
/// hands the terminal back, and the exit status is only known after `wait`.
pub struct Terminal {
  session : Session
  terminal_id : String
}

///|
/// The identifier the client gave this terminal.
pub fn Terminal::id(self : Terminal) -> String {
  self.terminal_id
}

///|
/// Everything the command has printed so far.
pub async fn Terminal::output(self : Terminal) -> TerminalOutput raise Refused {
  read_root(call_peer(self.session.peer, "terminal/output", self.params()))
}

///|
/// Waits for the command to exit and reports how it did.
pub async fn Terminal::wait(self : Terminal) -> ExitStatus raise Refused {
  read_root(
    call_peer(self.session.peer, "terminal/wait_for_exit", self.params()),
  )
}

///|
/// Stops the command without giving the terminal back.
pub async fn Terminal::kill(self : Terminal) -> Unit raise Refused {
  ignore(call_peer(self.session.peer, "terminal/kill", self.params()))
}

///|
/// Gives the terminal back. The client may reuse it for the next command.
pub async fn Terminal::release(self : Terminal) -> Unit raise Refused {
  ignore(call_peer(self.session.peer, "terminal/release", self.params()))
}

///|
/// The terminal as a tool call refers to it, for `ToolCallContent`.
pub fn Terminal::reference(self : Terminal) -> TerminalRef {
  TerminalRef::{ terminal_id: self.terminal_id, meta: None, }
}

///|
fn Terminal::params(self : Terminal) -> Json {
  json_of([
    ("sessionId", Some(Json::string(self.session.id))),
    ("terminalId", Some(Json::string(self.terminal_id))),
  ])
}
