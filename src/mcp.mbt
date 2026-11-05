// MCP servers a client may hand to a session. The protocol carries their configuration; connecting
// to them is the agent's business, so these are records and nothing more.

///|
/// One header sent to an MCP server.
#derive(Eq)
pub(all) struct HttpHeader {
  name : String
  value : String
  meta : Json?
}

///|
pub extend HttpHeader with Eq::{equal, not_equal}

///|
pub extend HttpHeader with @json.ToJson::{to_json}

///|
pub impl ToJson for HttpHeader with fn to_json(self) {
  json_of([
    ("name", Some(Json::string(self.name))),
    ("value", Some(Json::string(self.value))),
    ("_meta", self.meta),
  ])
}

///|
pub extend HttpHeader with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for HttpHeader with fn from_json(json, path) {
  let fields = expect_object(json, path)
  {
    name: required_string(fields, "name", path),
    value: required_string(fields, "value", path),
    meta: meta_of(fields, path),
  }
}

///|
/// One environment variable for a spawned MCP server.
#derive(Eq)
pub(all) struct EnvVariable {
  name : String
  value : String
  meta : Json?
}

///|
pub extend EnvVariable with Eq::{equal, not_equal}

///|
pub extend EnvVariable with @json.ToJson::{to_json}

///|
pub impl ToJson for EnvVariable with fn to_json(self) {
  json_of([
    ("name", Some(Json::string(self.name))),
    ("value", Some(Json::string(self.value))),
    ("_meta", self.meta),
  ])
}

///|
pub extend EnvVariable with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for EnvVariable with fn from_json(json, path) {
  let fields = expect_object(json, path)
  {
    name: required_string(fields, "name", path),
    value: required_string(fields, "value", path),
    meta: meta_of(fields, path),
  }
}

///|
/// An MCP server reached over HTTP.
#derive(Eq)
pub(all) struct McpHttp {
  name : String
  url : String
  headers : Array[HttpHeader]
  meta : Json?
}

///|
pub extend McpHttp with Eq::{equal, not_equal}

///|
pub extend McpHttp with @json.ToJson::{to_json}

///|
pub impl ToJson for McpHttp with fn to_json(self) {
  json_of([
    ("name", Some(Json::string(self.name))),
    ("url", Some(Json::string(self.url))),
    ("headers", Some(Json::array(self.headers.map(write)))),
    ("_meta", self.meta),
  ])
}

///|
pub extend McpHttp with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for McpHttp with fn from_json(json, path) {
  let fields = expect_object(json, path)
  {
    name: required_string(fields, "name", path),
    url: required_string(fields, "url", path),
    headers: required_objects(fields, "headers", path),
    meta: meta_of(fields, path),
  }
}

///|
/// An MCP server reached over the older HTTP plus SSE transport.
#derive(Eq)
pub(all) struct McpSse {
  name : String
  url : String
  headers : Array[HttpHeader]
  meta : Json?
}

///|
pub extend McpSse with Eq::{equal, not_equal}

///|
pub extend McpSse with @json.ToJson::{to_json}

///|
pub impl ToJson for McpSse with fn to_json(self) {
  json_of([
    ("name", Some(Json::string(self.name))),
    ("url", Some(Json::string(self.url))),
    ("headers", Some(Json::array(self.headers.map(write)))),
    ("_meta", self.meta),
  ])
}

///|
pub extend McpSse with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for McpSse with fn from_json(json, path) {
  let fields = expect_object(json, path)
  {
    name: required_string(fields, "name", path),
    url: required_string(fields, "url", path),
    headers: required_objects(fields, "headers", path),
    meta: meta_of(fields, path),
  }
}

///|
/// An MCP server the client is to launch as a child process.
#derive(Eq)
pub(all) struct McpStdio {
  name : String
  command : String
  args : Array[String]
  env : Array[EnvVariable]
  meta : Json?
}

///|
pub extend McpStdio with Eq::{equal, not_equal}

///|
pub extend McpStdio with @json.ToJson::{to_json}

///|
pub impl ToJson for McpStdio with fn to_json(self) {
  json_of([
    ("name", Some(Json::string(self.name))),
    ("command", Some(Json::string(self.command))),
    ("args", Some(Json::array(self.args.map(Json::string)))),
    ("env", Some(Json::array(self.env.map(write)))),
    ("_meta", self.meta),
  ])
}

///|
pub extend McpStdio with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for McpStdio with fn from_json(json, path) {
  let fields = expect_object(json, path)
  {
    name: required_string(fields, "name", path),
    command: required_string(fields, "command", path),
    args: required_list(fields, "args", path, (value, at) => text_of(value, at)),
    env: required_objects(fields, "env", path),
    meta: meta_of(fields, path),
  }
}

///|
/// An MCP server a session may use. The wire tells the two HTTP shapes apart by `type`; the stdio
/// shape carries no tag at all.
#derive(Eq)
pub(all) enum McpServer {
  Http(McpHttp)
  Sse(McpSse)
  Stdio(McpStdio)
}

///|
pub extend McpServer with Eq::{equal, not_equal}

///|
pub extend McpServer with @json.ToJson::{to_json}

///|
pub impl ToJson for McpServer with fn to_json(self) {
  match self {
    Http(server) => json_tagged(write(server), "type", "http")
    Sse(server) => json_tagged(write(server), "type", "sse")
    Stdio(server) => write(server)
  }
}

///|
pub extend McpServer with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for McpServer with fn from_json(json, path) {
  let fields = expect_object(json, path)
  match string_member(fields, "type", path) {
    Some("http") => Http(read(json, path))
    Some("sse") => Sse(read(json, path))
    Some(other) =>
      raise @json.JsonDecodeError(
        (path.add_key("type"), "unknown MCP transport \{other}"),
      )
    None => Stdio(read(json, path))
  }
}
