// The methods the agent calls on the client: reading and writing files, running commands, asking
// the user, and the answers each one gives.

///|
/// A text file to read.
#derive(Eq)
pub(all) struct ReadTextFile {
  session_id : String
  path : String
  line : Int64?
  limit : Int64?
  meta : Json?
}

///|
pub extend ReadTextFile with Eq::{equal, not_equal}

///|
pub extend ReadTextFile with @json.ToJson::{to_json}

///|
pub impl ToJson for ReadTextFile with fn to_json(self) {
  json_of([
    ("sessionId", Some(Json::string(self.session_id))),
    ("path", Some(Json::string(self.path))),
    ("line", json_int(self.line)),
    ("limit", json_int(self.limit)),
    ("_meta", self.meta),
  ])
}

///|
pub extend ReadTextFile with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for ReadTextFile with fn from_json(json, path) {
  let fields = expect_object(json, path)
  {
    session_id: required_string(fields, "sessionId", path),
    path: required_string(fields, "path", path),
    line: int_member(fields, "line", path),
    limit: int_member(fields, "limit", path),
    meta: meta_of(fields, path),
  }
}

///|
/// What a read returns.
#derive(Eq)
pub(all) struct FileText {
  content : String
  meta : Json?
}

///|
pub extend FileText with Eq::{equal, not_equal}

///|
pub extend FileText with @json.ToJson::{to_json}

///|
pub impl ToJson for FileText with fn to_json(self) {
  json_of([("content", Some(Json::string(self.content))), ("_meta", self.meta)])
}

///|
pub extend FileText with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for FileText with fn from_json(json, path) {
  let fields = expect_object(json, path)
  {
    content: required_string(fields, "content", path),
    meta: meta_of(fields, path),
  }
}

///|
/// A text file to write, whole.
#derive(Eq)
pub(all) struct WriteTextFile {
  session_id : String
  path : String
  content : String
  meta : Json?
}

///|
pub extend WriteTextFile with Eq::{equal, not_equal}

///|
pub extend WriteTextFile with @json.ToJson::{to_json}

///|
pub impl ToJson for WriteTextFile with fn to_json(self) {
  json_of([
    ("sessionId", Some(Json::string(self.session_id))),
    ("path", Some(Json::string(self.path))),
    ("content", Some(Json::string(self.content))),
    ("_meta", self.meta),
  ])
}

///|
pub extend WriteTextFile with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for WriteTextFile with fn from_json(json, path) {
  let fields = expect_object(json, path)
  {
    session_id: required_string(fields, "sessionId", path),
    path: required_string(fields, "path", path),
    content: required_string(fields, "content", path),
    meta: meta_of(fields, path),
  }
}

///|
/// A command to run in a new terminal.
#derive(Eq)
pub(all) struct TerminalCommand {
  session_id : String
  command : String
  args : Array[String]?
  env : Array[EnvVariable]?
  cwd : String?
  output_byte_limit : Int64?
  meta : Json?
}

///|
pub extend TerminalCommand with Eq::{equal, not_equal}

///|
pub extend TerminalCommand with @json.ToJson::{to_json}

///|
pub impl ToJson for TerminalCommand with fn to_json(self) {
  json_of([
    ("sessionId", Some(Json::string(self.session_id))),
    ("command", Some(Json::string(self.command))),
    ("args", json_list(self.args, Json::string)),
    ("env", json_list_of(self.env)),
    ("cwd", json_string(self.cwd)),
    ("outputByteLimit", json_int(self.output_byte_limit)),
    ("_meta", self.meta),
  ])
}

///|
pub extend TerminalCommand with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for TerminalCommand with fn from_json(json, path) {
  let fields = expect_object(json, path)
  {
    session_id: required_string(fields, "sessionId", path),
    command: required_string(fields, "command", path),
    args: list_member(fields, "args", path, (value, at) => text_of(value, at)),
    env: list_member(fields, "env", path, (value, at) => read(value, at)),
    cwd: string_member(fields, "cwd", path),
    output_byte_limit: int_member(fields, "outputByteLimit", path),
    meta: meta_of(fields, path),
  }
}

///|
/// The identifier of the terminal the client opened.
#derive(Eq)
pub(all) struct TerminalOpened {
  terminal_id : String
  meta : Json?
}

///|
pub extend TerminalOpened with Eq::{equal, not_equal}

///|
pub extend TerminalOpened with @json.ToJson::{to_json}

///|
pub impl ToJson for TerminalOpened with fn to_json(self) {
  json_of([
    ("terminalId", Some(Json::string(self.terminal_id))),
    ("_meta", self.meta),
  ])
}

///|
pub extend TerminalOpened with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for TerminalOpened with fn from_json(json, path) {
  let fields = expect_object(json, path)
  {
    terminal_id: required_string(fields, "terminalId", path),
    meta: meta_of(fields, path),
  }
}

///|
/// Names an existing terminal, for `terminal/output`, `terminal/wait_for_exit`, `terminal/kill` and
/// `terminal/release`.
#derive(Eq)
pub(all) struct TerminalRequest {
  session_id : String
  terminal_id : String
  meta : Json?
}

///|
pub extend TerminalRequest with Eq::{equal, not_equal}

///|
pub extend TerminalRequest with @json.ToJson::{to_json}

///|
pub impl ToJson for TerminalRequest with fn to_json(self) {
  json_of([
    ("sessionId", Some(Json::string(self.session_id))),
    ("terminalId", Some(Json::string(self.terminal_id))),
    ("_meta", self.meta),
  ])
}

///|
pub extend TerminalRequest with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for TerminalRequest with fn from_json(json, path) {
  let fields = expect_object(json, path)
  {
    session_id: required_string(fields, "sessionId", path),
    terminal_id: required_string(fields, "terminalId", path),
    meta: meta_of(fields, path),
  }
}

///|
/// How a command ended.
#derive(Eq)
pub(all) struct ExitStatus {
  exit_code : Int64?
  signal : String?
  meta : Json?
}

///|
pub extend ExitStatus with Eq::{equal, not_equal}

///|
pub extend ExitStatus with @json.ToJson::{to_json}

///|
pub impl ToJson for ExitStatus with fn to_json(self) {
  json_of([
    ("exitCode", json_int(self.exit_code)),
    ("signal", json_string(self.signal)),
    ("_meta", self.meta),
  ])
}

///|
pub extend ExitStatus with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for ExitStatus with fn from_json(json, path) {
  let fields = expect_object(json, path)
  {
    exit_code: int_member(fields, "exitCode", path),
    signal: string_member(fields, "signal", path),
    meta: meta_of(fields, path),
  }
}

///|
/// What a terminal has printed so far, and whether it has exited.
#derive(Eq)
pub(all) struct TerminalOutput {
  output : String
  truncated : Bool
  exit_status : ExitStatus?
  meta : Json?
}

///|
pub extend TerminalOutput with Eq::{equal, not_equal}

///|
pub extend TerminalOutput with @json.ToJson::{to_json}

///|
pub impl ToJson for TerminalOutput with fn to_json(self) {
  json_of([
    ("output", Some(Json::string(self.output))),
    ("truncated", Some(Json::boolean(self.truncated))),
    ("exitStatus", self.exit_status.map(write)),
    ("_meta", self.meta),
  ])
}

///|
pub extend TerminalOutput with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for TerminalOutput with fn from_json(json, path) {
  let fields = expect_object(json, path)
  {
    output: required_string(fields, "output", path),
    truncated: bool_of(
      required(fields, "truncated", path),
      path.add_key("truncated"),
    ),
    exit_status: object_member(fields, "exitStatus", path),
    meta: meta_of(fields, path),
  }
}
