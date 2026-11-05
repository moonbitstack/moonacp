// Tool calls: what the model asked to run, what it produced, and the permission prompt around it.

///|
/// What kind of thing a tool does, for a client that wants to pick an icon.
#derive(Eq)
pub(all) enum ToolKind {
  Read
  Edit
  Delete
  Move
  Search
  Execute
  Think
  Fetch
  SwitchMode
  Other
}

///|
pub extend ToolKind with Eq::{equal, not_equal}

///|
/// The name the kind travels as.
pub fn ToolKind::to_string(self : ToolKind) -> String {
  match self {
    Read => "read"
    Edit => "edit"
    Delete => "delete"
    Move => "move"
    Search => "search"
    Execute => "execute"
    Think => "think"
    Fetch => "fetch"
    SwitchMode => "switch_mode"
    Other => "other"
  }
}

///|
/// The kind with that name, or `None`.
pub fn ToolKind::of(name : String) -> ToolKind? {
  match name {
    "read" => Some(Read)
    "edit" => Some(Edit)
    "delete" => Some(Delete)
    "move" => Some(Move)
    "search" => Some(Search)
    "execute" => Some(Execute)
    "think" => Some(Think)
    "fetch" => Some(Fetch)
    "switch_mode" => Some(SwitchMode)
    "other" => Some(Other)
    _ => None
  }
}

///|
pub extend ToolKind with @json.ToJson::{to_json}

///|
pub impl ToJson for ToolKind with fn to_json(self) {
  Json::string(self.to_string())
}

///|
pub extend ToolKind with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for ToolKind with fn from_json(json, path) {
  match ToolKind::of(text_of(json, path)) {
    Some(kind) => kind
    None => raise want(path, "a tool kind", json)
  }
}

///|
/// How far a tool call got.
#derive(Eq)
pub(all) enum ToolCallStatus {
  Pending
  InProgress
  Completed
  Failed
}

///|
pub extend ToolCallStatus with Eq::{equal, not_equal}

///|
/// The name the status travels as.
pub fn ToolCallStatus::to_string(self : ToolCallStatus) -> String {
  match self {
    Pending => "pending"
    InProgress => "in_progress"
    Completed => "completed"
    Failed => "failed"
  }
}

///|
/// The status with that name, or `None`.
pub fn ToolCallStatus::of(name : String) -> ToolCallStatus? {
  match name {
    "pending" => Some(Pending)
    "in_progress" => Some(InProgress)
    "completed" => Some(Completed)
    "failed" => Some(Failed)
    _ => None
  }
}

///|
pub extend ToolCallStatus with @json.ToJson::{to_json}

///|
pub impl ToJson for ToolCallStatus with fn to_json(self) {
  Json::string(self.to_string())
}

///|
pub extend ToolCallStatus with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for ToolCallStatus with fn from_json(json, path) {
  match ToolCallStatus::of(text_of(json, path)) {
    Some(status) => status
    None => raise want(path, "a tool call status", json)
  }
}

///|
/// A tool call the model has asked for.
#derive(Eq)
pub(all) struct ToolCall {
  tool_call_id : String
  title : String
  name : String?
  kind : ToolKind?
  status : ToolCallStatus?
  content : Array[ToolCallContent]?
  locations : Array[ToolCallLocation]?
  raw_input : Json?
  raw_output : Json?
  meta : Json?
}

///|
pub extend ToolCall with Eq::{equal, not_equal}

///|
pub extend ToolCall with @json.ToJson::{to_json}

///|
pub impl ToJson for ToolCall with fn to_json(self) {
  json_of([
    ("toolCallId", Some(Json::string(self.tool_call_id))),
    ("title", Some(Json::string(self.title))),
    ("name", json_string(self.name)),
    ("kind", self.kind.map(write)),
    ("status", self.status.map(write)),
    ("content", json_list_of(self.content)),
    ("locations", json_list_of(self.locations)),
    ("rawInput", self.raw_input),
    ("rawOutput", self.raw_output),
    ("_meta", self.meta),
  ])
}

///|
pub extend ToolCall with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for ToolCall with fn from_json(json, path) {
  let fields = expect_object(json, path)
  {
    tool_call_id: required_string(fields, "toolCallId", path),
    title: required_string(fields, "title", path),
    name: string_member(fields, "name", path),
    kind: enum_member(fields, "kind", path, ToolKind::of),
    status: enum_member(fields, "status", path, ToolCallStatus::of),
    content: list_member(fields, "content", path, (value, at) => read(value, at)),
    locations: list_member(fields, "locations", path, (value, at) => {
      read(value, at)
    }),
    raw_input: field_of(fields, "rawInput", path),
    raw_output: field_of(fields, "rawOutput", path),
    meta: meta_of(fields, path),
  }
}

///|
/// A later change to a tool call: only what changed is present.
#derive(Eq)
pub(all) struct ToolCallUpdate {
  tool_call_id : String
  kind : ToolKind?
  status : ToolCallStatus?
  title : String?
  name : String?
  content : Array[ToolCallContent]?
  locations : Array[ToolCallLocation]?
  raw_input : Json?
  raw_output : Json?
  meta : Json?
}

///|
pub extend ToolCallUpdate with Eq::{equal, not_equal}

///|
pub extend ToolCallUpdate with @json.ToJson::{to_json}

///|
pub impl ToJson for ToolCallUpdate with fn to_json(self) {
  json_of([
    ("toolCallId", Some(Json::string(self.tool_call_id))),
    ("kind", self.kind.map(write)),
    ("status", self.status.map(write)),
    ("title", json_string(self.title)),
    ("name", json_string(self.name)),
    ("content", json_list_of(self.content)),
    ("locations", json_list_of(self.locations)),
    ("rawInput", self.raw_input),
    ("rawOutput", self.raw_output),
    ("_meta", self.meta),
  ])
}

///|
pub extend ToolCallUpdate with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for ToolCallUpdate with fn from_json(json, path) {
  let fields = expect_object(json, path)
  {
    tool_call_id: required_string(fields, "toolCallId", path),
    kind: enum_member(fields, "kind", path, ToolKind::of),
    status: enum_member(fields, "status", path, ToolCallStatus::of),
    title: string_member(fields, "title", path),
    name: string_member(fields, "name", path),
    content: list_member(fields, "content", path, (value, at) => read(value, at)),
    locations: list_member(fields, "locations", path, (value, at) => {
      read(value, at)
    }),
    raw_input: field_of(fields, "rawInput", path),
    raw_output: field_of(fields, "rawOutput", path),
    meta: meta_of(fields, path),
  }
}

///|
/// What choosing an option means, so a client can group the buttons.
#derive(Eq)
pub(all) enum PermissionOptionKind {
  AllowOnce
  AllowAlways
  RejectOnce
  RejectAlways
}

///|
pub extend PermissionOptionKind with Eq::{equal, not_equal}

///|
/// The name the option kind travels as.
pub fn PermissionOptionKind::to_string(self : PermissionOptionKind) -> String {
  match self {
    AllowOnce => "allow_once"
    AllowAlways => "allow_always"
    RejectOnce => "reject_once"
    RejectAlways => "reject_always"
  }
}

///|
/// The option kind with that name, or `None`.
pub fn PermissionOptionKind::of(name : String) -> PermissionOptionKind? {
  match name {
    "allow_once" => Some(AllowOnce)
    "allow_always" => Some(AllowAlways)
    "reject_once" => Some(RejectOnce)
    "reject_always" => Some(RejectAlways)
    _ => None
  }
}

///|
pub extend PermissionOptionKind with @json.ToJson::{to_json}

///|
pub impl ToJson for PermissionOptionKind with fn to_json(self) {
  Json::string(self.to_string())
}

///|
pub extend PermissionOptionKind with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for PermissionOptionKind with fn from_json(json, path) {
  match PermissionOptionKind::of(text_of(json, path)) {
    Some(kind) => kind
    None => raise want(path, "a permission option kind", json)
  }
}

///|
/// One button in a permission prompt.
#derive(Eq)
pub(all) struct PermissionOption {
  option_id : String
  name : String
  kind : PermissionOptionKind
  meta : Json?
}

///|
pub extend PermissionOption with Eq::{equal, not_equal}

///|
pub extend PermissionOption with @json.ToJson::{to_json}

///|
pub impl ToJson for PermissionOption with fn to_json(self) {
  json_of([
    ("optionId", Some(Json::string(self.option_id))),
    ("name", Some(Json::string(self.name))),
    ("kind", Some(write(self.kind))),
    ("_meta", self.meta),
  ])
}

///|
pub extend PermissionOption with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for PermissionOption with fn from_json(json, path) {
  let fields = expect_object(json, path)
  {
    option_id: required_string(fields, "optionId", path),
    name: required_string(fields, "name", path),
    kind: required_enum(fields, "kind", path, PermissionOptionKind::of),
    meta: meta_of(fields, path),
  }
}

///|
/// The ask the agent makes: run this tool call, and here is what the user may choose.
#derive(Eq)
pub(all) struct Permission {
  tool_call : ToolCallUpdate
  options : Array[PermissionOption]
  meta : Json?
}

///|
pub extend Permission with Eq::{equal, not_equal}

///|
pub extend Permission with @json.ToJson::{to_json}

///|
pub impl ToJson for Permission with fn to_json(self) {
  json_of([
    ("toolCall", Some(write(self.tool_call))),
    ("options", Some(Json::array(self.options.map(write)))),
    ("_meta", self.meta),
  ])
}

///|
pub extend Permission with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for Permission with fn from_json(json, path) {
  let fields = expect_object(json, path)
  {
    tool_call: required_object(fields, "toolCall", path),
    options: required_objects(fields, "options", path),
    meta: meta_of(fields, path),
  }
}

///|
/// What came back: one option chosen, or the ask dismissed.
#derive(Eq)
pub(all) enum Outcome {
  Selected(String)
  Cancelled
}

///|
pub extend Outcome with Eq::{equal, not_equal}

///|
pub extend Outcome with @json.ToJson::{to_json}

///|
pub impl ToJson for Outcome with fn to_json(self) {
  match self {
    Selected(option_id) =>
      json_tagged(
        json_of([("optionId", Some(Json::string(option_id)))]),
        "outcome",
        "selected",
      )
    Cancelled => json_tagged(Json::empty_object(), "outcome", "cancelled")
  }
}

///|
pub extend Outcome with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for Outcome with fn from_json(json, path) {
  let fields = expect_object(json, path)
  match required_string(fields, "outcome", path) {
    "selected" => Selected(required_string(fields, "optionId", path))
    "cancelled" => Cancelled
    other =>
      raise @json.JsonDecodeError(
        (path.add_key("outcome"), "unknown outcome \{other}"),
      )
  }
}
