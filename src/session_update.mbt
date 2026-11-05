// What the agent streams back while a prompt runs. One union, fourteen shapes, tagged by
// `sessionUpdate` on the wire.

///|
/// One streamed item of content.
#derive(Eq)
pub(all) struct ContentChunk {
  content : ContentBlock
  message_id : String?
  meta : Json?
}

///|
pub extend ContentChunk with Eq::{equal, not_equal}

///|
pub extend ContentChunk with @json.ToJson::{to_json}

///|
pub impl ToJson for ContentChunk with fn to_json(self) {
  json_of([
    ("content", Some(write(self.content))),
    ("messageId", json_string(self.message_id)),
    ("_meta", self.meta),
  ])
}

///|
pub extend ContentChunk with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for ContentChunk with fn from_json(json, path) {
  let fields = expect_object(json, path)
  {
    content: required_object(fields, "content", path),
    message_id: string_member(fields, "messageId", path),
    meta: meta_of(fields, path),
  }
}

///|
/// How urgent a plan entry is.
#derive(Eq)
pub(all) enum PlanEntryPriority {
  High
  Medium
  Low
}

///|
pub extend PlanEntryPriority with Eq::{equal, not_equal}

///|
/// The name the priority travels as.
pub fn PlanEntryPriority::to_string(self : PlanEntryPriority) -> String {
  match self {
    High => "high"
    Medium => "medium"
    Low => "low"
  }
}

///|
/// The priority with that name, or `None`.
pub fn PlanEntryPriority::of(name : String) -> PlanEntryPriority? {
  match name {
    "high" => Some(High)
    "medium" => Some(Medium)
    "low" => Some(Low)
    _ => None
  }
}

///|
pub extend PlanEntryPriority with @json.ToJson::{to_json}

///|
pub impl ToJson for PlanEntryPriority with fn to_json(self) {
  Json::string(self.to_string())
}

///|
pub extend PlanEntryPriority with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for PlanEntryPriority with fn from_json(json, path) {
  match PlanEntryPriority::of(text_of(json, path)) {
    Some(priority) => priority
    None => raise want(path, "a plan entry priority", json)
  }
}

///|
/// How far a plan entry got.
#derive(Eq)
pub(all) enum PlanEntryStatus {
  Pending
  InProgress
  Completed
}

///|
pub extend PlanEntryStatus with Eq::{equal, not_equal}

///|
/// The name the status travels as.
pub fn PlanEntryStatus::to_string(self : PlanEntryStatus) -> String {
  match self {
    Pending => "pending"
    InProgress => "in_progress"
    Completed => "completed"
  }
}

///|
/// The status with that name, or `None`.
pub fn PlanEntryStatus::of(name : String) -> PlanEntryStatus? {
  match name {
    "pending" => Some(Pending)
    "in_progress" => Some(InProgress)
    "completed" => Some(Completed)
    _ => None
  }
}

///|
pub extend PlanEntryStatus with @json.ToJson::{to_json}

///|
pub impl ToJson for PlanEntryStatus with fn to_json(self) {
  Json::string(self.to_string())
}

///|
pub extend PlanEntryStatus with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for PlanEntryStatus with fn from_json(json, path) {
  match PlanEntryStatus::of(text_of(json, path)) {
    Some(status) => status
    None => raise want(path, "a plan entry status", json)
  }
}

///|
/// One step of the agent's plan.
#derive(Eq)
pub(all) struct PlanEntry {
  content : String
  priority : PlanEntryPriority
  status : PlanEntryStatus
  meta : Json?
}

///|
pub extend PlanEntry with Eq::{equal, not_equal}

///|
pub extend PlanEntry with @json.ToJson::{to_json}

///|
pub impl ToJson for PlanEntry with fn to_json(self) {
  json_of([
    ("content", Some(Json::string(self.content))),
    ("priority", Some(write(self.priority))),
    ("status", Some(write(self.status))),
    ("_meta", self.meta),
  ])
}

///|
pub extend PlanEntry with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for PlanEntry with fn from_json(json, path) {
  let fields = expect_object(json, path)
  {
    content: required_string(fields, "content", path),
    priority: required_enum(fields, "priority", path, PlanEntryPriority::of),
    status: required_enum(fields, "status", path, PlanEntryStatus::of),
    meta: meta_of(fields, path),
  }
}

///|
/// The whole plan, replacing whatever came before.
#derive(Eq)
pub(all) struct Plan {
  entries : Array[PlanEntry]
  meta : Json?
}

///|
pub extend Plan with Eq::{equal, not_equal}

///|
pub extend Plan with @json.ToJson::{to_json}

///|
pub impl ToJson for Plan with fn to_json(self) {
  json_of([
    ("entries", Some(Json::array(self.entries.map(write)))),
    ("_meta", self.meta),
  ])
}

///|
pub extend Plan with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for Plan with fn from_json(json, path) {
  let fields = expect_object(json, path)
  {
    entries: required_objects(fields, "entries", path),
    meta: meta_of(fields, path),
  }
}

///|
/// The text typed after a command's name, offered to the user as a hint.
#derive(Eq)
pub(all) struct CommandInput {
  hint : String
  meta : Json?
}

///|
pub extend CommandInput with Eq::{equal, not_equal}

///|
pub extend CommandInput with @json.ToJson::{to_json}

///|
pub impl ToJson for CommandInput with fn to_json(self) {
  json_of([("hint", Some(Json::string(self.hint))), ("_meta", self.meta)])
}

///|
pub extend CommandInput with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for CommandInput with fn from_json(json, path) {
  let fields = expect_object(json, path)
  { hint: required_string(fields, "hint", path), meta: meta_of(fields, path), }
}

///|
/// A slash command the user may type.
#derive(Eq)
pub(all) struct AvailableCommand {
  name : String
  description : String
  input : CommandInput?
  meta : Json?
}

///|
pub extend AvailableCommand with Eq::{equal, not_equal}

///|
pub extend AvailableCommand with @json.ToJson::{to_json}

///|
pub impl ToJson for AvailableCommand with fn to_json(self) {
  json_of([
    ("name", Some(Json::string(self.name))),
    ("description", Some(Json::string(self.description))),
    ("input", self.input.map(write)),
    ("_meta", self.meta),
  ])
}

///|
pub extend AvailableCommand with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for AvailableCommand with fn from_json(json, path) {
  let fields = expect_object(json, path)
  {
    name: required_string(fields, "name", path),
    description: required_string(fields, "description", path),
    input: object_member(fields, "input", path),
    meta: meta_of(fields, path),
  }
}

///|
/// The command list, replacing whatever came before.
#derive(Eq)
pub(all) struct AvailableCommands {
  available_commands : Array[AvailableCommand]
  meta : Json?
}

///|
pub extend AvailableCommands with Eq::{equal, not_equal}

///|
pub extend AvailableCommands with @json.ToJson::{to_json}

///|
pub impl ToJson for AvailableCommands with fn to_json(self) {
  json_of([
    ("availableCommands", Some(Json::array(self.available_commands.map(write)))),
    ("_meta", self.meta),
  ])
}

///|
pub extend AvailableCommands with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for AvailableCommands with fn from_json(json, path) {
  let fields = expect_object(json, path)
  {
    available_commands: required_objects(fields, "availableCommands", path),
    meta: meta_of(fields, path),
  }
}

///|
/// The session's mode changed.
#derive(Eq)
pub(all) struct ModeChanged {
  current_mode_id : String
  meta : Json?
}

///|
pub extend ModeChanged with Eq::{equal, not_equal}

///|
pub extend ModeChanged with @json.ToJson::{to_json}

///|
pub impl ToJson for ModeChanged with fn to_json(self) {
  json_of([
    ("currentModeId", Some(Json::string(self.current_mode_id))),
    ("_meta", self.meta),
  ])
}

///|
pub extend ModeChanged with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for ModeChanged with fn from_json(json, path) {
  let fields = expect_object(json, path)
  {
    current_mode_id: required_string(fields, "currentModeId", path),
    meta: meta_of(fields, path),
  }
}

///|
/// The session's metadata changed; only the fields that changed are present.
#derive(Eq)
pub(all) struct SessionInfoChanged {
  title : String?
  updated_at : String?
  meta : Json?
}

///|
pub extend SessionInfoChanged with Eq::{equal, not_equal}

///|
pub extend SessionInfoChanged with @json.ToJson::{to_json}

///|
pub impl ToJson for SessionInfoChanged with fn to_json(self) {
  json_of([
    ("title", json_string(self.title)),
    ("updatedAt", json_string(self.updated_at)),
    ("_meta", self.meta),
  ])
}

///|
pub extend SessionInfoChanged with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for SessionInfoChanged with fn from_json(json, path) {
  let fields = expect_object(json, path)
  {
    title: string_member(fields, "title", path),
    updated_at: string_member(fields, "updatedAt", path),
    meta: meta_of(fields, path),
  }
}

///|
/// What the turn cost, in whatever currency the agent bills in.
#derive(Eq)
pub(all) struct Cost {
  amount : Double
  currency : String
  meta : Json?
}

///|
pub extend Cost with Eq::{equal, not_equal}

///|
pub extend Cost with @json.ToJson::{to_json}

///|
pub impl ToJson for Cost with fn to_json(self) {
  json_of([
    ("amount", Some(Json::number(self.amount))),
    ("currency", Some(Json::string(self.currency))),
    ("_meta", self.meta),
  ])
}

///|
pub extend Cost with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for Cost with fn from_json(json, path) {
  let fields = expect_object(json, path)
  {
    amount: float_of(required(fields, "amount", path), path.add_key("amount")),
    currency: required_string(fields, "currency", path),
    meta: meta_of(fields, path),
  }
}

///|
/// How much of the context window the conversation fills.
#derive(Eq)
pub(all) struct Usage {
  used : Int64
  size : Int64
  cost : Cost?
  meta : Json?
}

///|
pub extend Usage with Eq::{equal, not_equal}

///|
pub extend Usage with @json.ToJson::{to_json}

///|
pub impl ToJson for Usage with fn to_json(self) {
  json_of([
    ("used", json_int(Some(self.used))),
    ("size", json_int(Some(self.size))),
    ("cost", self.cost.map(write)),
    ("_meta", self.meta),
  ])
}

///|
pub extend Usage with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for Usage with fn from_json(json, path) {
  let fields = expect_object(json, path)
  {
    used: int_of(required(fields, "used", path), path.add_key("used")),
    size: int_of(required(fields, "size", path), path.add_key("size")),
    cost: object_member(fields, "cost", path),
    meta: meta_of(fields, path),
  }
}

///|
/// How loud a notice is. Unknown severities are kept as they came.
#derive(Eq)
pub(all) enum Severity {
  Info
  Warning
  Error
  Other(String)
}

///|
pub extend Severity with Eq::{equal, not_equal}

///|
/// The name the severity travels as.
pub fn Severity::to_string(self : Severity) -> String {
  match self {
    Info => "info"
    Warning => "warning"
    Error => "error"
    Other(name) => name
  }
}

///|
/// The severity with that name; unknown names are kept as they came.
pub fn Severity::of(name : String) -> Severity {
  match name {
    "info" => Info
    "warning" => Warning
    "error" => Error
    other => Other(other)
  }
}

///|
pub extend Severity with @json.ToJson::{to_json}

///|
pub impl ToJson for Severity with fn to_json(self) {
  Json::string(self.to_string())
}

///|
pub extend Severity with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for Severity with fn from_json(json, path) {
  Severity::of(text_of(json, path))
}

///|
/// Something to tell the user that is not part of the conversation.
#derive(Eq)
pub(all) struct Notice {
  severity : Severity
  title : String
  description : String?
  meta : Json?
}

///|
pub extend Notice with Eq::{equal, not_equal}

///|
pub extend Notice with @json.ToJson::{to_json}

///|
pub impl ToJson for Notice with fn to_json(self) {
  json_of([
    ("severity", Some(write(self.severity))),
    ("title", Some(Json::string(self.title))),
    ("description", json_string(self.description)),
    ("_meta", self.meta),
  ])
}

///|
pub extend Notice with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for Notice with fn from_json(json, path) {
  let fields = expect_object(json, path)
  {
    severity: required_enum(fields, "severity", path, name => {
      Some(Severity::of(name))
    }),
    title: required_string(fields, "title", path),
    description: string_member(fields, "description", path),
    meta: meta_of(fields, path),
  }
}

///|
/// Where a context compaction got to. Unknown states are kept as they came.
#derive(Eq)
pub(all) enum CompactionStatus {
  InProgress
  Completed
  Failed
  Cancelled
  Other(String)
}

///|
pub extend CompactionStatus with Eq::{equal, not_equal}

///|
/// The name the state travels as.
pub fn CompactionStatus::to_string(self : CompactionStatus) -> String {
  match self {
    InProgress => "in_progress"
    Completed => "completed"
    Failed => "failed"
    Cancelled => "cancelled"
    Other(name) => name
  }
}

///|
/// The state with that name; unknown names are kept as they came.
pub fn CompactionStatus::of(name : String) -> CompactionStatus {
  match name {
    "in_progress" => InProgress
    "completed" => Completed
    "failed" => Failed
    "cancelled" => Cancelled
    other => Other(other)
  }
}

///|
pub extend CompactionStatus with @json.ToJson::{to_json}

///|
pub impl ToJson for CompactionStatus with fn to_json(self) {
  Json::string(self.to_string())
}

///|
pub extend CompactionStatus with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for CompactionStatus with fn from_json(json, path) {
  CompactionStatus::of(text_of(json, path))
}

///|
/// A compaction, created the first time its identifier is seen and updated after that.
#derive(Eq)
pub(all) struct Compaction {
  compaction_id : String
  status : CompactionStatus
  summary : Array[ContentBlock]?
  error : String?
  meta : Json?
}

///|
pub extend Compaction with Eq::{equal, not_equal}

///|
pub extend Compaction with @json.ToJson::{to_json}

///|
pub impl ToJson for Compaction with fn to_json(self) {
  json_of([
    ("compactionId", Some(Json::string(self.compaction_id))),
    ("status", Some(write(self.status))),
    ("summary", json_list_of(self.summary)),
    ("error", json_string(self.error)),
    ("_meta", self.meta),
  ])
}

///|
pub extend Compaction with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for Compaction with fn from_json(json, path) {
  let fields = expect_object(json, path)
  {
    compaction_id: required_string(fields, "compactionId", path),
    status: required_enum(fields, "status", path, name => {
      Some(CompactionStatus::of(name))
    }),
    summary: list_member(fields, "summary", path, (value, at) => read(value, at)),
    error: string_member(fields, "error", path),
    meta: meta_of(fields, path),
  }
}

///|
/// One more block of a compaction's retained summary.
#derive(Eq)
pub(all) struct CompactionSummary {
  compaction_id : String
  content : ContentBlock
  meta : Json?
}

///|
pub extend CompactionSummary with Eq::{equal, not_equal}

///|
pub extend CompactionSummary with @json.ToJson::{to_json}

///|
pub impl ToJson for CompactionSummary with fn to_json(self) {
  json_of([
    ("compactionId", Some(Json::string(self.compaction_id))),
    ("content", Some(write(self.content))),
    ("_meta", self.meta),
  ])
}

///|
pub extend CompactionSummary with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for CompactionSummary with fn from_json(json, path) {
  let fields = expect_object(json, path)
  {
    compaction_id: required_string(fields, "compactionId", path),
    content: required_object(fields, "content", path),
    meta: meta_of(fields, path),
  }
}

///|
/// Everything the agent may tell the client mid-turn, tagged by `sessionUpdate` on the wire.
#derive(Eq)
pub(all) enum SessionUpdate {
  UserMessageChunk(ContentChunk)
  AgentMessageChunk(ContentChunk)
  AgentThoughtChunk(ContentChunk)
  ToolCall(ToolCall)
  ToolCallUpdate(ToolCallUpdate)
  Plan(Plan)
  AvailableCommands(AvailableCommands)
  ModeChanged(ModeChanged)
  ConfigOptionChanged(Array[ConfigOption])
  SessionInfoChanged(SessionInfoChanged)
  Usage(Usage)
  Notice(Notice)
  Compaction(Compaction)
  CompactionSummary(CompactionSummary)
}

///|
pub extend SessionUpdate with Eq::{equal, not_equal}

///|
pub extend SessionUpdate with @json.ToJson::{to_json}

///|
pub impl ToJson for SessionUpdate with fn to_json(self) {
  match self {
    UserMessageChunk(chunk) =>
      json_tagged(write(chunk), "sessionUpdate", "user_message_chunk")
    AgentMessageChunk(chunk) =>
      json_tagged(write(chunk), "sessionUpdate", "agent_message_chunk")
    AgentThoughtChunk(chunk) =>
      json_tagged(write(chunk), "sessionUpdate", "agent_thought_chunk")
    ToolCall(call) => json_tagged(write(call), "sessionUpdate", "tool_call")
    ToolCallUpdate(update) =>
      json_tagged(write(update), "sessionUpdate", "tool_call_update")
    Plan(plan) => json_tagged(write(plan), "sessionUpdate", "plan")
    AvailableCommands(commands) =>
      json_tagged(write(commands), "sessionUpdate", "available_commands_update")
    ModeChanged(change) =>
      json_tagged(write(change), "sessionUpdate", "current_mode_update")
    ConfigOptionChanged(options) =>
      json_tagged(
        json_of([("configOptions", Some(Json::array(options.map(write))))]),
        "sessionUpdate",
        "config_option_update",
      )
    SessionInfoChanged(change) =>
      json_tagged(write(change), "sessionUpdate", "session_info_update")
    Usage(usage) => json_tagged(write(usage), "sessionUpdate", "usage_update")
    Notice(notice) => json_tagged(write(notice), "sessionUpdate", "notice")
    Compaction(compaction) =>
      json_tagged(write(compaction), "sessionUpdate", "compaction_update")
    CompactionSummary(chunk) =>
      json_tagged(write(chunk), "sessionUpdate", "compaction_summary_chunk")
  }
}

///|
pub extend SessionUpdate with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for SessionUpdate with fn from_json(json, path) {
  let fields = expect_object(json, path)
  match required_string(fields, "sessionUpdate", path) {
    "user_message_chunk" => UserMessageChunk(read(json, path))
    "agent_message_chunk" => AgentMessageChunk(read(json, path))
    "agent_thought_chunk" => AgentThoughtChunk(read(json, path))
    "tool_call" => ToolCall(read(json, path))
    "tool_call_update" => ToolCallUpdate(read(json, path))
    "plan" => Plan(read(json, path))
    "available_commands_update" => AvailableCommands(read(json, path))
    "current_mode_update" => ModeChanged(read(json, path))
    "config_option_update" =>
      ConfigOptionChanged(required_objects(fields, "configOptions", path))
    "session_info_update" => SessionInfoChanged(read(json, path))
    "usage_update" => Usage(read(json, path))
    "notice" => Notice(read(json, path))
    "compaction_update" => Compaction(read(json, path))
    "compaction_summary_chunk" => CompactionSummary(read(json, path))
    other =>
      raise @json.JsonDecodeError(
        (path.add_key("sessionUpdate"), "unknown update \{other}"),
      )
  }
}

///|
/// One update as it travels: the session it belongs to and the update itself.
#derive(Eq)
pub(all) struct SessionNotification {
  session_id : String
  update : SessionUpdate
  meta : Json?
}

///|
pub extend SessionNotification with Eq::{equal, not_equal}

///|
pub extend SessionNotification with @json.ToJson::{to_json}

///|
pub impl ToJson for SessionNotification with fn to_json(self) {
  json_of([
    ("sessionId", Some(Json::string(self.session_id))),
    ("update", Some(write(self.update))),
    ("_meta", self.meta),
  ])
}

///|
pub extend SessionNotification with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for SessionNotification with fn from_json(json, path) {
  let fields = expect_object(json, path)
  {
    session_id: required_string(fields, "sessionId", path),
    update: required_object(fields, "update", path),
    meta: meta_of(fields, path),
  }
}
