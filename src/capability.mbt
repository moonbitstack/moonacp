// What each side says it can do. A capability is a promise: whatever is advertised here is tested
// by the other side, and whatever is left out must never be used.

///|
/// Content kinds the agent accepts inside a prompt.
#derive(Eq)
pub(all) struct PromptCapabilities {
  image : Bool
  audio : Bool
  embedded_context : Bool
  meta : Json?
}

///|
pub extend PromptCapabilities with Eq::{equal, not_equal}

///|
pub fn PromptCapabilities::none() -> PromptCapabilities {
  { image: false, audio: false, embedded_context: false, meta: None, }
}

///|
pub extend PromptCapabilities with @json.ToJson::{to_json}

///|
pub impl ToJson for PromptCapabilities with fn to_json(self) {
  json_of([
    ("image", json_bool(true_or_none(self.image))),
    ("audio", json_bool(true_or_none(self.audio))),
    ("embeddedContext", json_bool(true_or_none(self.embedded_context))),
    ("_meta", self.meta),
  ])
}

///|
fn true_or_none(value : Bool) -> Bool? {
  if value {
    Some(true)
  } else {
    None
  }
}

///|
pub extend PromptCapabilities with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for PromptCapabilities with fn from_json(json, path) {
  let fields = expect_object(json, path)
  {
    image: bool_member(fields, "image", path).unwrap_or(false),
    audio: bool_member(fields, "audio", path).unwrap_or(false),
    embedded_context: bool_member(fields, "embeddedContext", path).unwrap_or(
      false,
    ),
    meta: meta_of(fields, path),
  }
}

///|
/// MCP transports the agent can connect to.
#derive(Eq)
pub(all) struct McpCapabilities {
  http : Bool
  sse : Bool
  meta : Json?
}

///|
pub extend McpCapabilities with Eq::{equal, not_equal}

///|
pub fn McpCapabilities::none() -> McpCapabilities {
  { http: false, sse: false, meta: None, }
}

///|
pub extend McpCapabilities with @json.ToJson::{to_json}

///|
pub impl ToJson for McpCapabilities with fn to_json(self) {
  json_of([
    ("http", json_bool(true_or_none(self.http))),
    ("sse", json_bool(true_or_none(self.sse))),
    ("_meta", self.meta),
  ])
}

///|
pub extend McpCapabilities with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for McpCapabilities with fn from_json(json, path) {
  let fields = expect_object(json, path)
  {
    http: bool_member(fields, "http", path).unwrap_or(false),
    sse: bool_member(fields, "sse", path).unwrap_or(false),
    meta: meta_of(fields, path),
  }
}

///|
/// Session methods beyond `session/new`. Each flag is a promise to answer that method.
#derive(Eq)
pub(all) struct SessionCapabilities {
  list : Bool
  delete : Bool
  additional_directories : Bool
  resume_session : Bool
  close : Bool
  meta : Json?
}

///|
pub extend SessionCapabilities with Eq::{equal, not_equal}

///|
pub fn SessionCapabilities::none() -> SessionCapabilities {
  {
    list: false,
    delete: false,
    additional_directories: false,
    resume_session: false,
    close: false,
    meta: None,
  }
}

///|
pub extend SessionCapabilities with @json.ToJson::{to_json}

///|
pub impl ToJson for SessionCapabilities with fn to_json(self) {
  json_of([
    ("list", presence(self.list)),
    ("delete", presence(self.delete)),
    ("additionalDirectories", presence(self.additional_directories)),
    ("resume", presence(self.resume_session)),
    ("close", presence(self.close)),
    ("_meta", self.meta),
  ])
}

///|
/// The schema marks a supported feature with an empty object rather than `true`.
fn presence(value : Bool) -> Json? {
  if value {
    Some(Json::empty_object())
  } else {
    None
  }
}

///|
fn presence_of(fields : Map[String, Json], key : String) -> Bool {
  match fields.get(key) {
    Some(Object(_)) => true
    Some(True) => true
    _ => false
  }
}

///|
pub extend SessionCapabilities with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for SessionCapabilities with fn from_json(json, path) {
  let fields = expect_object(json, path)
  {
    list: presence_of(fields, "list"),
    delete: presence_of(fields, "delete"),
    additional_directories: presence_of(fields, "additionalDirectories"),
    resume_session: presence_of(fields, "resume"),
    close: presence_of(fields, "close"),
    meta: meta_of(fields, path),
  }
}

///|
/// Authentication the agent offers.
#derive(Eq)
pub(all) struct AgentAuthCapabilities {
  logout : Bool
  meta : Json?
}

///|
pub extend AgentAuthCapabilities with Eq::{equal, not_equal}

///|
pub fn AgentAuthCapabilities::none() -> AgentAuthCapabilities {
  { logout: false, meta: None, }
}

///|
pub extend AgentAuthCapabilities with @json.ToJson::{to_json}

///|
pub impl ToJson for AgentAuthCapabilities with fn to_json(self) {
  json_of([
    ("logout", if self.logout { Some(Json::empty_object()) } else { None }),
    ("_meta", self.meta),
  ])
}

///|
pub extend AgentAuthCapabilities with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for AgentAuthCapabilities with fn from_json(json, path) {
  let fields = expect_object(json, path)
  { logout: presence_of(fields, "logout"), meta: meta_of(fields, path), }
}

///|
/// Everything the agent says it can do, sent back from `initialize`.
#derive(Eq)
pub(all) struct AgentCapabilities {
  load_session : Bool
  prompt : PromptCapabilities
  mcp : McpCapabilities
  session : SessionCapabilities
  auth : AgentAuthCapabilities?
  meta : Json?
}

///|
pub extend AgentCapabilities with Eq::{equal, not_equal}

///|
pub fn AgentCapabilities::none() -> AgentCapabilities {
  {
    load_session: false,
    prompt: PromptCapabilities::none(),
    mcp: McpCapabilities::none(),
    session: SessionCapabilities::none(),
    auth: None,
    meta: None,
  }
}

///|
pub extend AgentCapabilities with @json.ToJson::{to_json}

///|
pub impl ToJson for AgentCapabilities with fn to_json(self) {
  json_of([
    ("loadSession", json_bool(true_or_none(self.load_session))),
    ("promptCapabilities", Some(write(self.prompt))),
    ("mcpCapabilities", Some(write(self.mcp))),
    ("sessionCapabilities", Some(write(self.session))),
    ("auth", self.auth.map(write)),
    ("_meta", self.meta),
  ])
}

///|
pub extend AgentCapabilities with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for AgentCapabilities with fn from_json(json, path) {
  let fields = expect_object(json, path)
  {
    load_session: bool_member(fields, "loadSession", path).unwrap_or(false),
    prompt: object_member(fields, "promptCapabilities", path).unwrap_or(
      PromptCapabilities::none(),
    ),
    mcp: object_member(fields, "mcpCapabilities", path).unwrap_or(
      McpCapabilities::none(),
    ),
    session: object_member(fields, "sessionCapabilities", path).unwrap_or(
      SessionCapabilities::none(),
    ),
    auth: object_member(fields, "auth", path),
    meta: meta_of(fields, path),
  }
}

///|
/// Files the client lets the agent read and write on its behalf.
#derive(Eq)
pub(all) struct FileSystemCapabilities {
  read_text_file : Bool
  write_text_file : Bool
  meta : Json?
}

///|
pub extend FileSystemCapabilities with Eq::{equal, not_equal}

///|
pub fn FileSystemCapabilities::none() -> FileSystemCapabilities {
  { read_text_file: false, write_text_file: false, meta: None, }
}

///|
pub extend FileSystemCapabilities with @json.ToJson::{to_json}

///|
pub impl ToJson for FileSystemCapabilities with fn to_json(self) {
  json_of([
    ("readTextFile", json_bool(true_or_none(self.read_text_file))),
    ("writeTextFile", json_bool(true_or_none(self.write_text_file))),
    ("_meta", self.meta),
  ])
}

///|
pub extend FileSystemCapabilities with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for FileSystemCapabilities with fn from_json(json, path) {
  let fields = expect_object(json, path)
  {
    read_text_file: bool_member(fields, "readTextFile", path).unwrap_or(false),
    write_text_file: bool_member(fields, "writeTextFile", path).unwrap_or(false),
    meta: meta_of(fields, path),
  }
}

///|
/// Whether the client runs terminal commands for the agent.
#derive(Eq)
pub(all) struct ClientAuthCapabilities {
  terminal : Bool
  meta : Json?
}

///|
pub extend ClientAuthCapabilities with Eq::{equal, not_equal}

///|
pub fn ClientAuthCapabilities::none() -> ClientAuthCapabilities {
  { terminal: false, meta: None, }
}

///|
pub extend ClientAuthCapabilities with @json.ToJson::{to_json}

///|
pub impl ToJson for ClientAuthCapabilities with fn to_json(self) {
  json_of([
    ("terminal", json_bool(true_or_none(self.terminal))),
    ("_meta", self.meta),
  ])
}

///|
pub extend ClientAuthCapabilities with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for ClientAuthCapabilities with fn from_json(json, path) {
  let fields = expect_object(json, path)
  {
    terminal: bool_member(fields, "terminal", path).unwrap_or(false),
    meta: meta_of(fields, path),
  }
}

///|
/// The client's support for supplementary session features.
#derive(Eq)
pub(all) struct ClientSessionCapabilities {
  compaction : Bool
  config_options : Bool
  booleans : Bool
  notices : Bool
  meta : Json?
}

///|
pub extend ClientSessionCapabilities with Eq::{equal, not_equal}

///|
pub fn ClientSessionCapabilities::none() -> ClientSessionCapabilities {
  {
    compaction: false,
    config_options: false,
    booleans: false,
    notices: false,
    meta: None,
  }
}

///|
pub extend ClientSessionCapabilities with @json.ToJson::{to_json}

///|
pub impl ToJson for ClientSessionCapabilities with fn to_json(self) {
  json_of([
    ("compaction", presence(self.compaction)),
    (
      "configOptions",
      if self.config_options {
        Some(json_of([("boolean", presence(self.booleans))]))
      } else {
        None
      },
    ),
    ("notices", presence(self.notices)),
    ("_meta", self.meta),
  ])
}

///|
pub extend ClientSessionCapabilities with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for ClientSessionCapabilities with fn from_json(
  json,
  path,
) {
  let fields = expect_object(json, path)
  let booleans = match field_of(fields, "configOptions", path) {
    None => false
    Some(value) =>
      presence_of(
        expect_object(value, path.add_key("configOptions")),
        "boolean",
      )
  }
  {
    compaction: presence_of(fields, "compaction"),
    config_options: fields.contains("configOptions"),
    booleans,
    notices: presence_of(fields, "notices"),
    meta: meta_of(fields, path),
  }
}

///|
/// Elicitation kinds the client can show.
#derive(Eq)
pub(all) struct ElicitationCapabilities {
  form : Bool
  url : Bool
  meta : Json?
}

///|
pub extend ElicitationCapabilities with Eq::{equal, not_equal}

///|
pub fn ElicitationCapabilities::none() -> ElicitationCapabilities {
  { form: false, url: false, meta: None, }
}

///|
pub extend ElicitationCapabilities with @json.ToJson::{to_json}

///|
pub impl ToJson for ElicitationCapabilities with fn to_json(self) {
  json_of([
    ("form", presence(self.form)),
    ("url", presence(self.url)),
    ("_meta", self.meta),
  ])
}

///|
pub extend ElicitationCapabilities with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for ElicitationCapabilities with fn from_json(
  json,
  path,
) {
  let fields = expect_object(json, path)
  {
    form: presence_of(fields, "form"),
    url: presence_of(fields, "url"),
    meta: meta_of(fields, path),
  }
}

///|
/// Everything the client says it can do, sent with `initialize`.
#derive(Eq)
pub(all) struct ClientCapabilities {
  fs : FileSystemCapabilities
  terminal : Bool
  session : ClientSessionCapabilities?
  auth : ClientAuthCapabilities?
  elicitation : ElicitationCapabilities?
  meta : Json?
}

///|
pub extend ClientCapabilities with Eq::{equal, not_equal}

///|
pub fn ClientCapabilities::none() -> ClientCapabilities {
  {
    fs: FileSystemCapabilities::none(),
    terminal: false,
    session: None,
    auth: None,
    elicitation: None,
    meta: None,
  }
}

///|
pub extend ClientCapabilities with @json.ToJson::{to_json}

///|
pub impl ToJson for ClientCapabilities with fn to_json(self) {
  json_of([
    ("fs", Some(write(self.fs))),
    ("terminal", json_bool(true_or_none(self.terminal))),
    ("session", self.session.map(write)),
    ("auth", self.auth.map(write)),
    ("elicitation", self.elicitation.map(write)),
    ("_meta", self.meta),
  ])
}

///|
pub extend ClientCapabilities with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for ClientCapabilities with fn from_json(json, path) {
  let fields = expect_object(json, path)
  {
    fs: object_member(fields, "fs", path).unwrap_or(
      FileSystemCapabilities::none(),
    ),
    terminal: bool_member(fields, "terminal", path).unwrap_or(false),
    session: object_member(fields, "session", path),
    auth: object_member(fields, "auth", path),
    elicitation: object_member(fields, "elicitation", path),
    meta: meta_of(fields, path),
  }
}

///|
/// A name and version, for the log and the about box.
#derive(Eq)
pub(all) struct Implementation {
  name : String
  version : String
  title : String?
  meta : Json?
}

///|
pub extend Implementation with Eq::{equal, not_equal}

///|
pub fn Implementation::new(name : String, version : String) -> Implementation {
  { name, version, title: None, meta: None, }
}

///|
pub extend Implementation with @json.ToJson::{to_json}

///|
pub impl ToJson for Implementation with fn to_json(self) {
  json_of([
    ("name", Some(Json::string(self.name))),
    ("version", Some(Json::string(self.version))),
    ("title", json_string(self.title)),
    ("_meta", self.meta),
  ])
}

///|
pub extend Implementation with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for Implementation with fn from_json(json, path) {
  let fields = expect_object(json, path)
  {
    name: required_string(fields, "name", path),
    version: required_string(fields, "version", path),
    title: string_member(fields, "title", path),
    meta: meta_of(fields, path),
  }
}

///|
/// An authentication method the agent offers, one of two shapes tagged by `type` on the wire; the
/// agent-driven one carries no tag.
#derive(Eq)
pub(all) enum AuthMethod {
  Terminal(AuthMethodTerminal)
  Agent(AuthMethodAgent)
}

///|
pub extend AuthMethod with Eq::{equal, not_equal}

///|
/// The client runs a command to authenticate.
#derive(Eq)
pub(all) struct AuthMethodTerminal {
  id : String
  name : String
  description : String?
  args : Array[String]?
  env : Map[String, String]?
  meta : Json?
}

///|
pub extend AuthMethodTerminal with Eq::{equal, not_equal}

///|
pub extend AuthMethodTerminal with @json.ToJson::{to_json}

///|
pub impl ToJson for AuthMethodTerminal with fn to_json(self) {
  json_of([
    ("id", Some(Json::string(self.id))),
    ("name", Some(Json::string(self.name))),
    ("description", json_string(self.description)),
    ("args", json_list(self.args, Json::string)),
    (
      "env",
      self.env.map(env => {
        let out : Map[String, Json] = Map([])
        env.each(fn(key, value) { out[key] = Json::string(value) })
        Json::object(out)
      }),
    ),
    ("_meta", self.meta),
  ])
}

///|
pub extend AuthMethodTerminal with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for AuthMethodTerminal with fn from_json(json, path) {
  let fields = expect_object(json, path)
  let env = match field_of(fields, "env", path) {
    None => None
    Some(value) => {
      let values = expect_object(value, path.add_key("env"))
      let out : Map[String, String] = Map([])
      for entry in values.iter() {
        let (key, item) = entry
        out[key] = text_of(item, path.add_key("env").add_key(key))
      }
      Some(out)
    }
  }
  {
    id: required_string(fields, "id", path),
    name: required_string(fields, "name", path),
    description: string_member(fields, "description", path),
    args: list_member(fields, "args", path, (value, at) => text_of(value, at)),
    env,
    meta: meta_of(fields, path),
  }
}

///|
/// The agent runs the flow itself once `authenticate` is called.
#derive(Eq)
pub(all) struct AuthMethodAgent {
  id : String
  name : String
  description : String?
  meta : Json?
}

///|
pub extend AuthMethodAgent with Eq::{equal, not_equal}

///|
pub extend AuthMethodAgent with @json.ToJson::{to_json}

///|
pub impl ToJson for AuthMethodAgent with fn to_json(self) {
  json_of([
    ("id", Some(Json::string(self.id))),
    ("name", Some(Json::string(self.name))),
    ("description", json_string(self.description)),
    ("_meta", self.meta),
  ])
}

///|
pub extend AuthMethodAgent with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for AuthMethodAgent with fn from_json(json, path) {
  let fields = expect_object(json, path)
  {
    id: required_string(fields, "id", path),
    name: required_string(fields, "name", path),
    description: string_member(fields, "description", path),
    meta: meta_of(fields, path),
  }
}

///|
pub extend AuthMethod with @json.ToJson::{to_json}

///|
pub impl ToJson for AuthMethod with fn to_json(self) {
  match self {
    Terminal(terminal) => json_tagged(write(terminal), "type", "terminal")
    Agent(agent) => write(agent)
  }
}

///|
pub extend AuthMethod with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for AuthMethod with fn from_json(json, path) {
  let fields = expect_object(json, path)
  if string_member(fields, "type", path) == Some("terminal") {
    Terminal(read(json, path))
  } else {
    Agent(read(json, path))
  }
}
