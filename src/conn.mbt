// The client's side of the wire: outbound calls to the agent, and the handlers that answer the
// agent's own calls. Run the connection in one task and call from any other.

///|
/// A connection to an agent, from the editor's side. `run` takes messages in; the methods here send
/// them out and wait for their answers.
pub struct Conn {
  peer : @peer.Peer
  client : &Client
}

///|
/// Wires a client to a transport. The caller runs the returned connection, which is what delivers
/// updates and answers the agent's calls.
pub fn connect(client : &Client, frames : &@peer.Frames) -> Conn {
  let methods = @moonjrpc.Methods::new()
  let peer = @peer.Peer::new(frames, methods~, timeout_ms=None, batch=false)
  connect_methods(client, methods)
  { peer, client, }
}

///|
fn connect_methods(client : &Client, methods : @moonjrpc.Methods) -> Unit {
  methods.notice("session/update", async fn(params) {
    let notification : SessionNotification = params_of(params) catch {
      _ => return
    }
    client.update(notification.session_id, notification.update)
  })
  on_call(methods, "session/request_permission", async fn(params : Json) {
    let ask : Permission = read_root(params)
    write(client.request_permission(ask))
  })
  on_call(methods, "fs/read_text_file", async fn(request : ReadTextFile) {
    let content = client.read_text_file(request)
    write(FileText::{ content, meta: None, })
  })
  on_call(methods, "fs/write_text_file", async fn(request : WriteTextFile) {
    client.write_text_file(request)
    Json::empty_object()
  })
  on_call(methods, "terminal/create", async fn(request : TerminalCommand) {
    let terminal_id = client.create_terminal(request)
    write(TerminalOpened::{ terminal_id, meta: None, })
  })
  on_call(methods, "terminal/output", async fn(request : TerminalRequest) {
    write(client.terminal_output(request))
  })
  on_call(methods, "terminal/wait_for_exit", async fn(
    request : TerminalRequest,
  ) {
    write(client.wait_for_terminal_exit(request))
  })
  on_call(methods, "terminal/kill", async fn(request : TerminalRequest) {
    client.kill_terminal(request)
    Json::empty_object()
  })
  on_call(methods, "terminal/release", async fn(request : TerminalRequest) {
    client.release_terminal(request)
    Json::empty_object()
  })
  on_call(methods, "elicitation/create", async fn(request : Elicitation) {
    write(client.elicit(request))
  })
}

///|
/// Takes messages in until the other side goes away. Updates reach the client from here, so it has
/// to run in a task of its own while the other tasks call the agent.
pub async fn Conn::run(self : Conn) -> Unit {
  self.peer.run()
}

///|
/// A call the protocol does not name: send it raw and read the answer raw.
pub async fn Conn::call(
  self : Conn,
  name : String,
  params : Json,
) -> Json raise Refused {
  self.peer.call(name, params~) catch {
    @moonjrpc.Failed(failure) => raise refused_of(failure)
    @moonjrpc.TimedOut(name~, ..) =>
      raise Refused::Closed(reason="\{name} timed out")
    _ => raise Refused::Closed(reason="\{name}: the agent is gone")
  }
}

///|
/// A notice the protocol does not name.
pub async fn Conn::notify(
  self : Conn,
  name : String,
  params : Json,
) -> Unit raise Refused {
  self.peer.notify(name, params~) catch {
    @moonjrpc.Failed(failure) => raise refused_of(failure)
    _ => raise Refused::Closed(reason="\{name}: the agent is gone")
  }
}

///|
/// Negotiates the version and trades capabilities. Call it once, before anything else.
pub async fn Conn::initialize(
  self : Conn,
  request : Initialize,
) -> Initialized raise Refused {
  read_root(self.call("initialize", write(request)))
}

///|
/// Runs one of the agent's authentication methods.
pub async fn Conn::authenticate(
  self : Conn,
  request : Authenticate,
) -> Unit raise Refused {
  ignore(self.call("authenticate", write(request)))
}

///|
/// Drops whatever `authenticate` established.
pub async fn Conn::logout(self : Conn) -> Unit raise Refused {
  ignore(self.call("logout", json_of([])))
}

///|
/// Starts a session and returns what the agent says about it: identifier, modes, options.
pub async fn Conn::new_session(
  self : Conn,
  request : NewSession,
) -> SessionStarted raise Refused {
  read_root(self.call("session/new", write(request)))
}

///|
/// Reopens a session; the updates that replay its history arrive on `run`.
pub async fn Conn::load_session(
  self : Conn,
  request : LoadSession,
) -> SessionStarted raise Refused {
  read_root(self.call("session/load", write(request)))
}

///|
/// Reattaches to a live session without replaying anything.
pub async fn Conn::resume_session(
  self : Conn,
  request : ResumeSession,
) -> SessionStarted raise Refused {
  read_root(self.call("session/resume", write(request)))
}

///|
/// The sessions the agent remembers, one page at a time.
pub async fn Conn::list_sessions(
  self : Conn,
  request : ListSessions,
) -> SessionList raise Refused {
  read_root(self.call("session/list", write(request)))
}

///|
/// Forgets a session.
pub async fn Conn::delete_session(
  self : Conn,
  request : DeleteSession,
) -> Unit raise Refused {
  ignore(self.call("session/delete", write(request)))
}

///|
/// Ends a running session, as if `session/cancel` had been sent.
pub async fn Conn::close_session(
  self : Conn,
  request : CloseSession,
) -> Unit raise Refused {
  ignore(self.call("session/close", write(request)))
}

///|
/// Switches the session's mode.
pub async fn Conn::set_mode(
  self : Conn,
  request : SetMode,
) -> Unit raise Refused {
  ignore(self.call("session/set_mode", write(request)))
}

///|
/// Sets one configuration option and returns the whole list, as the protocol requires.
pub async fn Conn::set_config_option(
  self : Conn,
  request : SetConfigOption,
) -> Array[ConfigOption] raise Refused {
  let answer = self.call("session/set_config_option", write(request))
  let reply : SetConfigOptions = read_root(answer)
  reply.config_options
}

///|
/// Sends one turn and waits for its answer. Updates arrive through the client's `update` while this
/// waits, because the connection is being run in another task.
pub async fn Conn::prompt(
  self : Conn,
  request : Prompt,
) -> PromptResult raise Refused {
  read_root(self.call("session/prompt", write(request)))
}

///|
/// Asks the agent to stop the turn running in a session. A notice: nothing comes back, and the turn
/// answers `Cancelled` on its own.
pub async fn Conn::cancel(
  self : Conn,
  session_id : String,
) -> Unit raise Refused {
  self.notify("session/cancel", write(Cancel::{ session_id, meta: None, }))
}

///|
/// The client this connection feeds.
pub fn Conn::client(self : Conn) -> &Client {
  self.client
}
