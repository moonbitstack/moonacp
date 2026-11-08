// An agent behind HTTP, and the address it is behind.

///|
/// An agent whose turn takes two chunks and a pause, so a client has something to stream and
/// something to cancel. It remembers nothing between requests beyond a counter, which is enough
/// to show that the connection, not the process, carries the conversation.
struct Slow {
  mut next : Int32
}

///|
impl @moonacp.Agent for Slow with fn initialize(self, request) {
  ignore(self)
  ignore(request)
  {
    ..@moonacp.Initialized::new(),
    capabilities: {
      ..@moonacp.AgentCapabilities::none(),
      load_session: true,
      session: { ..@moonacp.SessionCapabilities::none(), list: true, },
    },
    auth_methods: [],
    agent_info: Some(@moonacp.Implementation::new("slow", "0.1.0")),
    meta: None,
  }
}

///|
impl @moonacp.Agent for Slow with fn new_session(self, request) {
  ignore(request)
  self.next = self.next + 1
  {
    session_id: "slow-\{self.next}",
    modes: None,
    config_options: None,
    meta: None,
  }
}

///|
impl @moonacp.Agent for Slow with fn load_session(self, request, session) {
  ignore(self)
  session.update(
    @moonacp.UserMessageChunk({
      content: @moonacp.Text({
        text: "asked before the restart",
        annotations: None,
        meta: None,
      }),
      message_id: None,
      meta: None,
    }),
  )
  {
    session_id: request.session_id,
    modes: None,
    config_options: None,
    meta: None,
  }
}

///|
impl @moonacp.Agent for Slow with fn list_sessions(self, request) {
  ignore(self)
  ignore(request)
  let rows : Array[@moonacp.SessionInfo] = [
    {
      session_id: "slow-1",
      cwd: "/work",
      additional_directories: None,
      title: Some("a session"),
      updated_at: None,
      meta: None,
    },
  ]
  { sessions: rows, next_cursor: None, meta: None, }
}

///|
impl @moonacp.Agent for Slow with fn prompt(self, request, session) {
  ignore(self)
  let asked = request.prompt
    .map(block => {
      match block {
        @moonacp.Text(content) => content.text
        _ => ""
      }
    })
    .join(" ")
  session.update(
    @moonacp.AgentMessageChunk({
      content: @moonacp.Text({
        text: "you said: ",
        annotations: None,
        meta: None,
      }),
      message_id: None,
      meta: None,
    }),
  )
  @async.sleep(60)
  session.update(
    @moonacp.AgentMessageChunk({
      content: @moonacp.Text({ text: asked, annotations: None, meta: None, }),
      message_id: None,
      meta: None,
    }),
  )
  @moonacp.EndTurn
}

///|
impl @moonacp.Agent for Slow with fn cancel(self, id) {
  ignore(self)
  ignore(id)
}

///|
/// The port a command line names, or 0 — the system's own choice — when it names none.
fn port_of(text : String) -> Int32 {
  let mut port = 0
  for digit in text {
    if digit < '0' || digit > '9' {
      return 0
    }
    port = port * 10 + (digit.to_int() - '0'.to_int())
  }
  port
}

///|
async fn main {
  let arguments = @env.args()
  let port = if arguments.length() > 1 { port_of(arguments[1]) } else { 0 }
  let agent : &@moonacp.Agent = Slow::{ next: 0, }
  let app = @asgi.to_asgi(agent)
  println("serving on 127.0.0.1:\{port}")
  @mooncat.serve(app, host="127.0.0.1", port~)
}
