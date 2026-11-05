// The methods the client calls on the agent: their parameters and their answers, one type per
// method, named after the method.

///|
/// The protocol version this library speaks. It only changes when the protocol breaks.
pub let protocol_version : Int32 = 1

///|
/// Opens the conversation: versions and capabilities, once per connection.
#derive(Eq)
pub(all) struct Initialize {
  protocol_version : Int32
  client_capabilities : ClientCapabilities
  client_info : Implementation?
  meta : Json?
}

///|
pub extend Initialize with Eq::{equal, not_equal}

///|
pub extend Initialize with @json.ToJson::{to_json}

///|
pub impl ToJson for Initialize with fn to_json(self) {
  json_of([
    ("protocolVersion", json_int(Some(self.protocol_version.to_int64()))),
    ("clientCapabilities", Some(write(self.client_capabilities))),
    ("clientInfo", self.client_info.map(write)),
    ("_meta", self.meta),
  ])
}

///|
pub extend Initialize with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for Initialize with fn from_json(json, path) {
  let fields = expect_object(json, path)
  {
    protocol_version: int_of(
      required(fields, "protocolVersion", path),
      path.add_key("protocolVersion"),
    ).to_int(),
    client_capabilities: object_member(fields, "clientCapabilities", path).unwrap_or(
      ClientCapabilities::none(),
    ),
    client_info: object_member(fields, "clientInfo", path),
    meta: meta_of(fields, path),
  }
}

///|
/// The answer to `initialize`.
#derive(Eq)
pub(all) struct Initialized {
  protocol_version : Int32
  capabilities : AgentCapabilities
  auth_methods : Array[AuthMethod]
  agent_info : Implementation?
  meta : Json?
}

///|
pub extend Initialized with Eq::{equal, not_equal}

///|
/// A first answer for an agent that supports nothing beyond `session/new`: the version, no
/// capabilities, no authentication.
pub fn Initialized::new() -> Initialized {
  {
    protocol_version,
    capabilities: AgentCapabilities::none(),
    auth_methods: [],
    agent_info: None,
    meta: None,
  }
}

///|
pub extend Initialized with @json.ToJson::{to_json}

///|
pub impl ToJson for Initialized with fn to_json(self) {
  json_of([
    ("protocolVersion", json_int(Some(self.protocol_version.to_int64()))),
    ("agentCapabilities", Some(write(self.capabilities))),
    (
      "authMethods",
      Some(Json::array(self.auth_methods.map(value => write(value)))),
    ),
    ("agentInfo", self.agent_info.map(write)),
    ("_meta", self.meta),
  ])
}

///|
pub extend Initialized with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for Initialized with fn from_json(json, path) {
  let fields = expect_object(json, path)
  {
    protocol_version: int_of(
      required(fields, "protocolVersion", path),
      path.add_key("protocolVersion"),
    ).to_int(),
    capabilities: object_member(fields, "agentCapabilities", path).unwrap_or(
      AgentCapabilities::none(),
    ),
    auth_methods: list_member(fields, "authMethods", path, (value, at) => {
      read(value, at)
    }).unwrap_or([]),
    agent_info: object_member(fields, "agentInfo", path),
    meta: meta_of(fields, path),
  }
}

///|
/// Names one of the methods from `initialize`.
#derive(Eq)
pub(all) struct Authenticate {
  method_id : String
  meta : Json?
}

///|
pub extend Authenticate with Eq::{equal, not_equal}

///|
pub extend Authenticate with @json.ToJson::{to_json}

///|
pub impl ToJson for Authenticate with fn to_json(self) {
  json_of([
    ("methodId", Some(Json::string(self.method_id))),
    ("_meta", self.meta),
  ])
}

///|
pub extend Authenticate with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for Authenticate with fn from_json(json, path) {
  let fields = expect_object(json, path)
  {
    method_id: required_string(fields, "methodId", path),
    meta: meta_of(fields, path),
  }
}

///|
/// Starts a conversation. The working directory is where the agent reads and writes.
#derive(Eq)
pub(all) struct NewSession {
  cwd : String
  additional_directories : Array[String]?
  mcp_servers : Array[McpServer]
  meta : Json?
}

///|
pub extend NewSession with Eq::{equal, not_equal}

///|
pub extend NewSession with @json.ToJson::{to_json}

///|
pub impl ToJson for NewSession with fn to_json(self) {
  json_of([
    ("cwd", Some(Json::string(self.cwd))),
    (
      "additionalDirectories",
      json_list(self.additional_directories, Json::string),
    ),
    ("mcpServers", Some(Json::array(self.mcp_servers.map(write)))),
    ("_meta", self.meta),
  ])
}

///|
pub extend NewSession with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for NewSession with fn from_json(json, path) {
  let fields = expect_object(json, path)
  {
    cwd: required_string(fields, "cwd", path),
    additional_directories: list_member(fields, "additionalDirectories", path, (
      value,
      at,
    ) => text_of(value, at)),
    mcp_servers: required_list(fields, "mcpServers", path, (value, at) => {
      read(value, at)
    }),
    meta: meta_of(fields, path),
  }
}

///|
/// Reopens a session and replays its history as updates.
#derive(Eq)
pub(all) struct LoadSession {
  session_id : String
  cwd : String
  additional_directories : Array[String]?
  mcp_servers : Array[McpServer]
  meta : Json?
}

///|
pub extend LoadSession with Eq::{equal, not_equal}

///|
pub extend LoadSession with @json.ToJson::{to_json}

///|
pub impl ToJson for LoadSession with fn to_json(self) {
  json_of([
    ("sessionId", Some(Json::string(self.session_id))),
    ("cwd", Some(Json::string(self.cwd))),
    (
      "additionalDirectories",
      json_list(self.additional_directories, Json::string),
    ),
    ("mcpServers", Some(Json::array(self.mcp_servers.map(write)))),
    ("_meta", self.meta),
  ])
}

///|
pub extend LoadSession with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for LoadSession with fn from_json(json, path) {
  let fields = expect_object(json, path)
  {
    session_id: required_string(fields, "sessionId", path),
    cwd: required_string(fields, "cwd", path),
    additional_directories: list_member(fields, "additionalDirectories", path, (
      value,
      at,
    ) => text_of(value, at)),
    mcp_servers: required_list(fields, "mcpServers", path, (value, at) => {
      read(value, at)
    }),
    meta: meta_of(fields, path),
  }
}

///|
/// Reattaches to a session without replaying its history.
#derive(Eq)
pub(all) struct ResumeSession {
  session_id : String
  cwd : String
  additional_directories : Array[String]?
  mcp_servers : Array[McpServer]?
  meta : Json?
}

///|
pub extend ResumeSession with Eq::{equal, not_equal}

///|
pub extend ResumeSession with @json.ToJson::{to_json}

///|
pub impl ToJson for ResumeSession with fn to_json(self) {
  json_of([
    ("sessionId", Some(Json::string(self.session_id))),
    ("cwd", Some(Json::string(self.cwd))),
    (
      "additionalDirectories",
      json_list(self.additional_directories, Json::string),
    ),
    ("mcpServers", json_list_of(self.mcp_servers)),
    ("_meta", self.meta),
  ])
}

///|
pub extend ResumeSession with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for ResumeSession with fn from_json(json, path) {
  let fields = expect_object(json, path)
  {
    session_id: required_string(fields, "sessionId", path),
    cwd: required_string(fields, "cwd", path),
    additional_directories: list_member(fields, "additionalDirectories", path, (
      value,
      at,
    ) => text_of(value, at)),
    mcp_servers: list_member(fields, "mcpServers", path, (value, at) => {
      read(value, at)
    }),
    meta: meta_of(fields, path),
  }
}

///|
/// Asks for the sessions the agent remembers.
#derive(Eq)
pub(all) struct ListSessions {
  cwd : String?
  cursor : String?
  meta : Json?
}

///|
pub extend ListSessions with Eq::{equal, not_equal}

///|
pub extend ListSessions with @json.ToJson::{to_json}

///|
pub impl ToJson for ListSessions with fn to_json(self) {
  json_of([
    ("cwd", json_string(self.cwd)),
    ("cursor", json_string(self.cursor)),
    ("_meta", self.meta),
  ])
}

///|
pub extend ListSessions with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for ListSessions with fn from_json(json, path) {
  let fields = expect_object(json, path)
  {
    cwd: string_member(fields, "cwd", path),
    cursor: string_member(fields, "cursor", path),
    meta: meta_of(fields, path),
  }
}

///|
/// One row of `session/list`.
#derive(Eq)
pub(all) struct SessionInfo {
  session_id : String
  cwd : String
  additional_directories : Array[String]?
  title : String?
  updated_at : String?
  meta : Json?
}

///|
pub extend SessionInfo with Eq::{equal, not_equal}

///|
pub extend SessionInfo with @json.ToJson::{to_json}

///|
pub impl ToJson for SessionInfo with fn to_json(self) {
  json_of([
    ("sessionId", Some(Json::string(self.session_id))),
    ("cwd", Some(Json::string(self.cwd))),
    (
      "additionalDirectories",
      json_list(self.additional_directories, Json::string),
    ),
    ("title", json_string(self.title)),
    ("updatedAt", json_string(self.updated_at)),
    ("_meta", self.meta),
  ])
}

///|
pub extend SessionInfo with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for SessionInfo with fn from_json(json, path) {
  let fields = expect_object(json, path)
  {
    session_id: required_string(fields, "sessionId", path),
    cwd: required_string(fields, "cwd", path),
    additional_directories: list_member(fields, "additionalDirectories", path, (
      value,
      at,
    ) => text_of(value, at)),
    title: string_member(fields, "title", path),
    updated_at: string_member(fields, "updatedAt", path),
    meta: meta_of(fields, path),
  }
}

///|
/// The page of sessions, and the cursor for the next one.
#derive(Eq)
pub(all) struct SessionList {
  sessions : Array[SessionInfo]
  next_cursor : String?
  meta : Json?
}

///|
pub extend SessionList with Eq::{equal, not_equal}

///|
pub extend SessionList with @json.ToJson::{to_json}

///|
pub impl ToJson for SessionList with fn to_json(self) {
  json_of([
    ("sessions", Some(Json::array(self.sessions.map(write)))),
    ("nextCursor", json_string(self.next_cursor)),
    ("_meta", self.meta),
  ])
}

///|
pub extend SessionList with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for SessionList with fn from_json(json, path) {
  let fields = expect_object(json, path)
  {
    sessions: required_objects(fields, "sessions", path),
    next_cursor: string_member(fields, "nextCursor", path),
    meta: meta_of(fields, path),
  }
}

///|
/// Removes a session from what `session/list` returns.
#derive(Eq)
pub(all) struct DeleteSession {
  session_id : String
  meta : Json?
}

///|
pub extend DeleteSession with Eq::{equal, not_equal}

///|
pub extend DeleteSession with @json.ToJson::{to_json}

///|
pub impl ToJson for DeleteSession with fn to_json(self) {
  json_of([
    ("sessionId", Some(Json::string(self.session_id))),
    ("_meta", self.meta),
  ])
}

///|
pub extend DeleteSession with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for DeleteSession with fn from_json(json, path) {
  let fields = expect_object(json, path)
  {
    session_id: required_string(fields, "sessionId", path),
    meta: meta_of(fields, path),
  }
}

///|
/// Ends a session that is still running.
#derive(Eq)
pub(all) struct CloseSession {
  session_id : String
  meta : Json?
}

///|
pub extend CloseSession with Eq::{equal, not_equal}

///|
pub extend CloseSession with @json.ToJson::{to_json}

///|
pub impl ToJson for CloseSession with fn to_json(self) {
  json_of([
    ("sessionId", Some(Json::string(self.session_id))),
    ("_meta", self.meta),
  ])
}

///|
pub extend CloseSession with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for CloseSession with fn from_json(json, path) {
  let fields = expect_object(json, path)
  {
    session_id: required_string(fields, "sessionId", path),
    meta: meta_of(fields, path),
  }
}

///|
/// Picks a mode.
#derive(Eq)
pub(all) struct SetMode {
  session_id : String
  mode_id : String
  meta : Json?
}

///|
pub extend SetMode with Eq::{equal, not_equal}

///|
pub extend SetMode with @json.ToJson::{to_json}

///|
pub impl ToJson for SetMode with fn to_json(self) {
  json_of([
    ("sessionId", Some(Json::string(self.session_id))),
    ("modeId", Some(Json::string(self.mode_id))),
    ("_meta", self.meta),
  ])
}

///|
pub extend SetMode with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for SetMode with fn from_json(json, path) {
  let fields = expect_object(json, path)
  {
    session_id: required_string(fields, "sessionId", path),
    mode_id: required_string(fields, "modeId", path),
    meta: meta_of(fields, path),
  }
}

///|
/// Sets a configuration option. The wire has two shapes, a value id or a boolean, told apart by
/// `type`.
#derive(Eq)
pub(all) enum ConfigValueId {
  Value(String)
  Boolean(Bool)
}

///|
pub extend ConfigValueId with Eq::{equal, not_equal}

///|
/// Sets one configuration option.
#derive(Eq)
pub(all) struct SetConfigOption {
  session_id : String
  config_id : String
  value : ConfigValueId
  meta : Json?
}

///|
pub extend SetConfigOption with Eq::{equal, not_equal}

///|
pub extend SetConfigOption with @json.ToJson::{to_json}

///|
pub impl ToJson for SetConfigOption with fn to_json(self) {
  let base = json_of([
    ("sessionId", Some(Json::string(self.session_id))),
    ("configId", Some(Json::string(self.config_id))),
    ("_meta", self.meta),
  ])
  match self.value {
    Value(value) =>
      merge_json(base, json_of([("value", Some(Json::string(value)))]))
    Boolean(value) =>
      json_tagged(
        merge_json(base, json_of([("value", Some(Json::boolean(value)))])),
        "type",
        "boolean",
      )
  }
}

///|
pub extend SetConfigOption with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for SetConfigOption with fn from_json(json, path) {
  let fields = expect_object(json, path)
  let value = match string_member(fields, "type", path) {
    Some("boolean") =>
      ConfigValueId::Boolean(
        bool_of(required(fields, "value", path), path.add_key("value")),
      )
    _ => ConfigValueId::Value(required_string(fields, "value", path))
  }
  {
    session_id: required_string(fields, "sessionId", path),
    config_id: required_string(fields, "configId", path),
    value,
    meta: meta_of(fields, path),
  }
}

///|
/// One turn of the conversation.
#derive(Eq)
pub(all) struct Prompt {
  session_id : String
  prompt : Array[ContentBlock]
  meta : Json?
}

///|
pub extend Prompt with Eq::{equal, not_equal}

///|
pub extend Prompt with @json.ToJson::{to_json}

///|
pub impl ToJson for Prompt with fn to_json(self) {
  json_of([
    ("sessionId", Some(Json::string(self.session_id))),
    ("prompt", Some(Json::array(self.prompt.map(write)))),
    ("_meta", self.meta),
  ])
}

///|
pub extend Prompt with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for Prompt with fn from_json(json, path) {
  let fields = expect_object(json, path)
  {
    session_id: required_string(fields, "sessionId", path),
    prompt: required_list(fields, "prompt", path, (value, at) => read(value, at)),
    meta: meta_of(fields, path),
  }
}

///|
/// Why the agent stopped.
#derive(Eq)
pub(all) enum StopReason {
  EndTurn
  MaxTokens
  MaxTurnRequests
  Refusal
  Cancelled
}

///|
pub extend StopReason with Eq::{equal, not_equal}

///|
pub fn StopReason::to_string(self : StopReason) -> String {
  match self {
    EndTurn => "end_turn"
    MaxTokens => "max_tokens"
    MaxTurnRequests => "max_turn_requests"
    Refusal => "refusal"
    Cancelled => "cancelled"
  }
}

///|
pub fn StopReason::of(name : String) -> StopReason? {
  match name {
    "end_turn" => Some(EndTurn)
    "max_tokens" => Some(MaxTokens)
    "max_turn_requests" => Some(MaxTurnRequests)
    "refusal" => Some(Refusal)
    "cancelled" => Some(Cancelled)
    _ => None
  }
}

///|
pub extend StopReason with @json.ToJson::{to_json}

///|
pub impl ToJson for StopReason with fn to_json(self) {
  Json::string(self.to_string())
}

///|
pub extend StopReason with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for StopReason with fn from_json(json, path) {
  match StopReason::of(text_of(json, path)) {
    Some(reason) => reason
    None => raise want(path, "a stop reason", json)
  }
}

///|
/// The answer to a prompt: why the turn ended.
#derive(Eq)
pub(all) struct PromptResult {
  stop_reason : StopReason
  meta : Json?
}

///|
pub extend PromptResult with Eq::{equal, not_equal}

///|
pub extend PromptResult with @json.ToJson::{to_json}

///|
pub impl ToJson for PromptResult with fn to_json(self) {
  json_of([("stopReason", Some(write(self.stop_reason))), ("_meta", self.meta)])
}

///|
pub extend PromptResult with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for PromptResult with fn from_json(json, path) {
  let fields = expect_object(json, path)
  {
    stop_reason: required_enum(fields, "stopReason", path, StopReason::of),
    meta: meta_of(fields, path),
  }
}

///|
/// Stops whatever turn is running in a session. A notification, so it is never answered.
#derive(Eq)
pub(all) struct Cancel {
  session_id : String
  meta : Json?
}

///|
pub extend Cancel with Eq::{equal, not_equal}

///|
pub extend Cancel with @json.ToJson::{to_json}

///|
pub impl ToJson for Cancel with fn to_json(self) {
  json_of([
    ("sessionId", Some(Json::string(self.session_id))),
    ("_meta", self.meta),
  ])
}

///|
pub extend Cancel with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for Cancel with fn from_json(json, path) {
  let fields = expect_object(json, path)
  {
    session_id: required_string(fields, "sessionId", path),
    meta: meta_of(fields, path),
  }
}
