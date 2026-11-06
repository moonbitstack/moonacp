// An agent that keeps notes: every turn is stored, so a session can be listed, resumed, loaded and
// deleted after the editor restarts.

///|
/// One session's state, kept past the connection that made it.
struct Note {
  mut cwd : String
  title : String
  mut mode : String
  mut model : String
  turns : Array[Turn]
  /// The MCP servers the client asked for at `session/new`, already hand-shaken.
  servers : Array[McpClient]
}

///|
/// One exchanged turn, kept for `session/load` to replay.
struct Turn {
  asked : String
  answered : String
}

///|
/// The agent. A `mut` counter and a plain map: the value lives for the whole connection, and every
/// handler holds the same one.
struct Notes {
  mut next : Int32
  notes : Map[String, Note]
  mut client : @moonacp.ClientCapabilities
}

///|
let modes : Array[String] = ["ask", "edit"]

///|
fn mode_list() -> Array[@moonacp.SessionMode] {
  [
    {
      id: "ask",
      name: "Ask",
      description: Some("Answer questions, change nothing"),
      meta: None,
    },
    {
      id: "edit",
      name: "Edit",
      description: Some("Make the change as well"),
      meta: None,
    },
  ]
}

///|
/// The configuration picker: a model dropdown always, and a streaming switch only for a client that
/// said it can draw one.
fn Notes::config_list(
  self : Notes,
  note : Note,
) -> Array[@moonacp.ConfigOption] {
  let options : Array[@moonacp.ConfigOption] = [
    {
      id: "model",
      name: "Model",
      description: Some("How hard the agent thinks"),
      category: Some(@moonacp.ConfigCategory::Model),
      value: @moonacp.ConfigValue::Select(
        note.model,
        @moonacp.ConfigChoices::Flat([
          { value: "fast", name: "Fast", description: None, meta: None, },
          {
            value: "thorough",
            name: "Thorough",
            description: None,
            meta: None,
          },
        ]),
      ),
      meta: None,
    },
  ]
  let booleans = match self.client.session {
    Some(session) => session.booleans
    None => false
  }
  if booleans {
    options.push({
      id: "stream",
      name: "Stream the answer",
      description: None,
      category: None,
      value: @moonacp.ConfigValue::Boolean(true),
      meta: None,
    })
  }
  options
}

///|
fn Notes::started(
  self : Notes,
  note : Note,
  id : String,
) -> @moonacp.SessionStarted {
  {
    session_id: id,
    modes: Some({
      current_mode_id: note.mode,
      available_modes: mode_list(),
      meta: None,
    }),
    config_options: Some(self.config_list(note)),
    meta: None,
  }
}

///|
fn text_block(text : String) -> @moonacp.ContentBlock {
  @moonacp.ContentBlock::Text({ text, annotations: None, meta: None, })
}

///|
/// What the agent says about a prompt: the text it was given, plus a line for every media block.
fn answer_to(prompt : Array[@moonacp.ContentBlock], mode : String) -> String {
  let said : Array[String] = []
  let media : Array[String] = []
  for block in prompt {
    match block {
      @moonacp.Text(content) => said.push(content.text)
      @moonacp.Image(content) => media.push("an image (\{content.mime_type})")
      @moonacp.Audio(content) => media.push("audio (\{content.mime_type})")
      @moonacp.ResourceLink(content) =>
        media.push("the resource \{content.name}")
      @moonacp.Resource(content) =>
        media.push(
          match content.resource {
            @moonacp.Text(resource) => "the text of \{resource.uri}"
            @moonacp.Blob(resource) => "the bytes of \{resource.uri}"
          },
        )
    }
  }
  let mut out = "You said: \{said.join(" ")}"
  if !media.is_empty() {
    out = out + "\nI also received " + media.join(", ") + "."
  }
  if mode == "edit" {
    out = out + "\nI would edit the workspace now."
  } else {
    out = out + "\nI will not touch the workspace."
  }
  out
}

///|
impl @moonacp.Agent for Notes with fn initialize(self, request) {
  self.client = request.client_capabilities
  {
    protocol_version: @moonacp.protocol_version,
    capabilities: {
      load_session: true,
      prompt: { image: true, audio: true, embedded_context: true, meta: None, },
      mcp: { http: false, sse: false, meta: None, },
      session: {
        list: true,
        delete: true,
        additional_directories: true,
        resume_session: true,
        close: true,
        meta: None,
      },
      auth: Some({ logout: true, meta: None, }),
      meta: None,
    },
    auth_methods: [
      @moonacp.AuthMethod::Agent({
        id: "notes",
        name: "Notes",
        description: Some("No credentials needed"),
        meta: None,
      }),
    ],
    agent_info: Some(@moonacp.Implementation::new("notes-agent", "0.1.0")),
    meta: None,
  }
}

///|
impl @moonacp.Agent for Notes with fn authenticate(self, request) {
  ignore(self)
  if request.method_id != "notes" {
    raise @moonacp.Refused::Refused(
      code=@moonacp.invalid_params,
      message="Unknown authentication method",
      data=None,
    )
  }
}

///|
impl @moonacp.Agent for Notes with fn new_session(self, request) {
  self.next = self.next + 1
  let id = "notes-\{self.next}"
  // The client named the servers it wants; this agent launches the stdio ones, which is the only
  // transport it advertised.
  let servers : Array[McpClient] = []
  for server in request.mcp_servers {
    if server is @moonacp.Stdio(stdio) {
      match McpClient::connect(stdio) {
        Some(client) => servers.push(client)
        None => ()
      }
    }
  }
  let note = Note::{
    cwd: request.cwd,
    title: "Session \{self.next}",
    mode: "ask",
    model: "fast",
    turns: [],
    servers,
  }
  self.notes[id] = note
  self.started(note, id)
}

///|
impl @moonacp.Agent for Notes with fn load_session(self, request, session) {
  let note = match self.notes.get(request.session_id) {
    Some(note) => note
    None =>
      raise @moonacp.Refused::Refused(
        code=@moonacp.resource_not_found,
        message="No such session",
        data=None,
      )
  }
  note.cwd = request.cwd
  for turn in note.turns {
    session.update(
      @moonacp.SessionUpdate::UserMessageChunk({
        content: text_block(turn.asked),
        message_id: None,
        meta: None,
      }),
    )
    session.update(
      @moonacp.SessionUpdate::AgentMessageChunk({
        content: text_block(turn.answered),
        message_id: None,
        meta: None,
      }),
    )
  }
  self.started(note, request.session_id)
}

///|
impl @moonacp.Agent for Notes with fn resume_session(self, request, session) {
  ignore(session)
  let note = match self.notes.get(request.session_id) {
    Some(note) => note
    None =>
      raise @moonacp.Refused::Refused(
        code=@moonacp.resource_not_found,
        message="No such session",
        data=None,
      )
  }
  self.started(note, request.session_id)
}

///|
impl @moonacp.Agent for Notes with fn list_sessions(self, request) {
  let rows : Array[@moonacp.SessionInfo] = []
  for entry in self.notes.iter() {
    let (id, note) = entry
    if request.cwd is Some(cwd) && cwd != note.cwd {
      continue
    }
    rows.push({
      session_id: id,
      cwd: note.cwd,
      additional_directories: None,
      title: Some(note.title),
      updated_at: None,
      meta: None,
    })
  }
  { sessions: rows, next_cursor: None, meta: None, }
}

///|
impl @moonacp.Agent for Notes with fn delete_session(self, request) {
  match self.notes.get(request.session_id) {
    Some(note) => {
      for server in note.servers {
        server.close()
      }
      self.notes.remove(request.session_id)
    }
    None => ()
  }
}

///|
impl @moonacp.Agent for Notes with fn close_session(self, request) {
  match self.notes.get(request.session_id) {
    Some(note) =>
      for server in note.servers {
        server.close()
      }
    None => ()
  }
}

///|
impl @moonacp.Agent for Notes with fn set_mode(self, request) {
  match self.notes.get(request.session_id) {
    Some(note) =>
      if !modes.contains(request.mode_id) {
        raise @moonacp.Refused::Refused(
          code=@moonacp.invalid_params,
          message="Unknown mode",
          data=None,
        )
      } else {
        note.mode = request.mode_id
      }
    None =>
      raise @moonacp.Refused::Refused(
        code=@moonacp.resource_not_found,
        message="No such session",
        data=None,
      )
  }
}

///|
impl @moonacp.Agent for Notes with fn set_config_option(self, request) {
  let note = match self.notes.get(request.session_id) {
    Some(note) => note
    None =>
      raise @moonacp.Refused::Refused(
        code=@moonacp.resource_not_found,
        message="No such session",
        data=None,
      )
  }
  match request.config_id {
    "model" =>
      match request.value {
        @moonacp.ConfigValueId::Value(model) => note.model = model
        @moonacp.ConfigValueId::Boolean(_) =>
          raise @moonacp.Refused::Refused(
            code=@moonacp.invalid_params,
            message="The model is a choice, not a switch",
            data=None,
          )
      }
    "stream" => ()
    other =>
      raise @moonacp.Refused::Refused(
        code=@moonacp.invalid_params,
        message="Unknown configuration option \{other}",
        data=None,
      )
  }
  self.config_list(note)
}

///|
impl @moonacp.Agent for Notes with fn prompt(self, request, session) {
  let note = match self.notes.get(request.session_id) {
    Some(note) => note
    None =>
      raise @moonacp.Refused::Refused(
        code=@moonacp.resource_not_found,
        message="No such session",
        data=None,
      )
  }
  let mut asked = ""
  for block in request.prompt {
    if block is @moonacp.ContentBlock::Text(content) {
      asked = content.text
      break
    }
  }
  let answer = answer_to(request.prompt, note.mode) + tools_line(note.servers)
  // Two chunks, with a pause between them: an editor gets to show the answer growing, and a
  // `session/cancel` has somewhere to land.
  let cut = answer.length() / 2
  session.update(
    @moonacp.SessionUpdate::AgentMessageChunk({
      content: text_block(answer[0:cut].to_owned()),
      message_id: None,
      meta: None,
    }),
  )
  @async.sleep(120)
  session.update(
    @moonacp.SessionUpdate::AgentMessageChunk({
      content: text_block(answer[cut:].to_owned()),
      message_id: None,
      meta: None,
    }),
  )
  note.turns.push({ asked, answered: answer, })
  @moonacp.StopReason::EndTurn
}

///|
impl @moonacp.Agent for Notes with fn cancel(self, id) {
  ignore(self)
  ignore(id)
}

///|
async fn main {
  let agent = Notes::{
    next: 0,
    notes: Map([]),
    client: @moonacp.ClientCapabilities::none(),
  }
  @stdio.serve_stdio(agent)
}
