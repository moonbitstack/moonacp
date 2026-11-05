// The two contracts a user implements: one to be an agent, one to be a client. Anything left out
// keeps the default body, which raises `Unsupported` and travels as -32601, so an agent only
// declares in `initialize` what it actually answers.

///|
/// The agent side. Implement what the agent can do and leave the rest: `initialize` and
/// `new_session` and `prompt` are the three every agent has, the others have defaults that report
/// themselves as unsupported.
pub(open) trait Agent {
  ///|
  /// Negotiates the version and trades capabilities. Called once per connection, before anything
  /// else.
  async fn initialize(Self, Initialize) -> Initialized raise Refused

  ///|
  /// Runs the agent's own authentication flow for the method the client picked.
  async fn authenticate(Self, Authenticate) -> Unit raise Refused = _

  ///|
  /// Drops whatever `authenticate` established.
  async fn logout(Self) -> Unit raise Refused = _

  ///|
  /// Starts a session in `cwd`. The working directories and MCP servers come from the client.
  async fn new_session(Self, NewSession) -> SessionStarted raise Refused

  ///|
  /// Reopens a session and replays its history through the `Session` handle before answering.
  async fn load_session(Self, LoadSession, Session) -> SessionStarted raise Refused = _

  ///|
  /// Reattaches to a live session without replaying anything.
  async fn resume_session(Self, ResumeSession, Session) -> SessionStarted raise Refused = _

  ///|
  /// The sessions this agent remembers.
  async fn list_sessions(Self, ListSessions) -> SessionList raise Refused = _

  ///|
  /// Forgets a session.
  async fn delete_session(Self, DeleteSession) -> Unit raise Refused = _

  ///|
  /// Ends a running session and frees what it holds.
  async fn close_session(Self, CloseSession) -> Unit raise Refused = _

  ///|
  /// Switches the session's mode.
  async fn set_mode(Self, SetMode) -> Unit raise Refused = _

  ///|
  /// Sets one configuration option and answers with the whole option list.
  async fn set_config_option(Self, SetConfigOption) -> Array[ConfigOption] raise Refused = _

  ///|
  /// Runs one turn. Updates go out through the `Session`, and the answer says why the turn ended.
  /// `session/cancel` cancels the task this runs in, so an await is where a turn can be stopped.
  async fn prompt(Self, Prompt, Session) -> StopReason raise Refused

  ///|
  /// The client asked for the turn in `id` to stop. Called from the read loop: return quickly, and
  /// do not wait for the turn.
  async fn cancel(Self, id : String) -> Unit = _
}

///|
impl Agent with fn authenticate(self, request) {
  ignore(self)
  ignore(request)
  raise Refused::Unsupported(name="authenticate")
}

///|
impl Agent with fn logout(self) {
  ignore(self)
  raise Refused::Unsupported(name="logout")
}

///|
impl Agent with fn load_session(self, request, session) {
  ignore(self)
  ignore(request)
  ignore(session)
  raise Refused::Unsupported(name="session/load")
}

///|
impl Agent with fn resume_session(self, request, session) {
  ignore(self)
  ignore(request)
  ignore(session)
  raise Refused::Unsupported(name="session/resume")
}

///|
impl Agent with fn list_sessions(self, request) {
  ignore(self)
  ignore(request)
  raise Refused::Unsupported(name="session/list")
}

///|
impl Agent with fn delete_session(self, request) {
  ignore(self)
  ignore(request)
  raise Refused::Unsupported(name="session/delete")
}

///|
impl Agent with fn close_session(self, request) {
  ignore(self)
  ignore(request)
  raise Refused::Unsupported(name="session/close")
}

///|
impl Agent with fn set_mode(self, request) {
  ignore(self)
  ignore(request)
  raise Refused::Unsupported(name="session/set_mode")
}

///|
impl Agent with fn set_config_option(self, request) {
  ignore(self)
  ignore(request)
  raise Refused::Unsupported(name="session/set_config_option")
}

///|
impl Agent with fn cancel(self, id) {
  ignore(self)
  ignore(id)
}

///|
/// The client side. `update` is the only method the protocol requires; the rest exist so the agent
/// can ask for them, and a client that leaves one out answers -32601 when the agent asks.
pub(open) trait Client {
  ///|
  /// One update from the agent. Notifications are not answered, so a failure here is the client's
  /// own business; it must not stop the turn.
  async fn update(Self, String, SessionUpdate) -> Unit

  ///|
  /// The user is asked whether a tool call may run.
  async fn request_permission(Self, Permission) -> Outcome raise Refused

  ///|
  /// Reads a text file the agent wants to see.
  async fn read_text_file(Self, ReadTextFile) -> String raise Refused = _

  ///|
  /// Writes a text file the agent produced.
  async fn write_text_file(Self, WriteTextFile) -> Unit raise Refused = _

  ///|
  /// Starts a command and gives back its terminal identifier.
  async fn create_terminal(Self, TerminalCommand) -> String raise Refused = _

  ///|
  /// Everything the terminal has printed so far.
  async fn terminal_output(Self, TerminalRequest) -> TerminalOutput raise Refused = _

  ///|
  /// Waits for the command in a terminal to exit.
  async fn wait_for_terminal_exit(Self, TerminalRequest) -> ExitStatus raise Refused = _

  ///|
  /// Stops the command without giving the terminal back.
  async fn kill_terminal(Self, TerminalRequest) -> Unit raise Refused = _

  ///|
  /// Gives the terminal back.
  async fn release_terminal(Self, TerminalRequest) -> Unit raise Refused = _

  ///|
  /// Puts a form or a link in front of the user.
  async fn elicit(Self, Elicitation) -> Answer raise Refused = _
}

///|
impl Client with fn read_text_file(self, request) {
  ignore(self)
  ignore(request)
  raise Refused::Unsupported(name="fs/read_text_file")
}

///|
impl Client with fn write_text_file(self, request) {
  ignore(self)
  ignore(request)
  raise Refused::Unsupported(name="fs/write_text_file")
}

///|
impl Client with fn create_terminal(self, request) {
  ignore(self)
  ignore(request)
  raise Refused::Unsupported(name="terminal/create")
}

///|
impl Client with fn terminal_output(self, request) {
  ignore(self)
  ignore(request)
  raise Refused::Unsupported(name="terminal/output")
}

///|
impl Client with fn wait_for_terminal_exit(self, request) {
  ignore(self)
  ignore(request)
  raise Refused::Unsupported(name="terminal/wait_for_exit")
}

///|
impl Client with fn kill_terminal(self, request) {
  ignore(self)
  ignore(request)
  raise Refused::Unsupported(name="terminal/kill")
}

///|
impl Client with fn release_terminal(self, request) {
  ignore(self)
  ignore(request)
  raise Refused::Unsupported(name="terminal/release")
}

///|
impl Client with fn elicit(self, request) {
  ignore(self)
  ignore(request)
  raise Refused::Unsupported(name="elicitation/create")
}
