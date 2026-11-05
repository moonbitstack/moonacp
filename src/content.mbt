// What travels inside a prompt and inside a tool call's result: text, media, resources and diffs.

///|
/// Who a piece of content is for.
#derive(Eq)
pub(all) enum Role {
  Assistant
  User
}

///|
pub extend Role with Eq::{equal, not_equal}

///|
/// The name the role travels as.
pub fn Role::to_string(self : Role) -> String {
  match self {
    Assistant => "assistant"
    User => "user"
  }
}

///|
/// The role with that name, or `None`.
pub fn Role::of(name : String) -> Role? {
  match name {
    "assistant" => Some(Assistant)
    "user" => Some(User)
    _ => None
  }
}

///|
pub extend Role with @json.ToJson::{to_json}

///|
pub impl ToJson for Role with fn to_json(self) {
  Json::string(self.to_string())
}

///|
pub extend Role with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for Role with fn from_json(json, path) {
  match Role::of(text_of(json, path)) {
    Some(role) => role
    None => raise want(path, "a role", json)
  }
}

///|
/// Hints for how a client shows a piece of content.
#derive(Eq)
pub(all) struct Annotations {
  audience : Array[Role]?
  last_modified : String?
  priority : Double?
  meta : Json?
}

///|
pub extend Annotations with Eq::{equal, not_equal}

///|
pub extend Annotations with @json.ToJson::{to_json}

///|
pub impl ToJson for Annotations with fn to_json(self) {
  json_of([
    ("audience", json_list_of(self.audience)),
    ("lastModified", json_string(self.last_modified)),
    ("priority", json_float(self.priority)),
    ("_meta", self.meta),
  ])
}

///|
pub extend Annotations with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for Annotations with fn from_json(json, path) {
  let fields = expect_object(json, path)
  {
    audience: list_member(fields, "audience", path, (value, at) => {
      read(value, at)
    }),
    last_modified: string_member(fields, "lastModified", path),
    priority: float_member(fields, "priority", path),
    meta: meta_of(fields, path),
  }
}

///|
/// Text the model reads or writes.
#derive(Eq)
pub(all) struct TextContent {
  text : String
  annotations : Annotations?
  meta : Json?
}

///|
pub extend TextContent with Eq::{equal, not_equal}

///|
pub extend TextContent with @json.ToJson::{to_json}

///|
pub impl ToJson for TextContent with fn to_json(self) {
  json_of([
    ("text", Some(Json::string(self.text))),
    ("annotations", self.annotations.map(write)),
    ("_meta", self.meta),
  ])
}

///|
pub extend TextContent with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for TextContent with fn from_json(json, path) {
  let fields = expect_object(json, path)
  {
    text: required_string(fields, "text", path),
    annotations: object_member(fields, "annotations", path),
    meta: meta_of(fields, path),
  }
}

///|
/// An image, base64 in `data`.
#derive(Eq)
pub(all) struct ImageContent {
  data : String
  mime_type : String
  uri : String?
  annotations : Annotations?
  meta : Json?
}

///|
pub extend ImageContent with Eq::{equal, not_equal}

///|
pub extend ImageContent with @json.ToJson::{to_json}

///|
pub impl ToJson for ImageContent with fn to_json(self) {
  json_of([
    ("data", Some(Json::string(self.data))),
    ("mimeType", Some(Json::string(self.mime_type))),
    ("uri", json_string(self.uri)),
    ("annotations", self.annotations.map(write)),
    ("_meta", self.meta),
  ])
}

///|
pub extend ImageContent with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for ImageContent with fn from_json(json, path) {
  let fields = expect_object(json, path)
  {
    data: required_string(fields, "data", path),
    mime_type: required_string(fields, "mimeType", path),
    uri: string_member(fields, "uri", path),
    annotations: object_member(fields, "annotations", path),
    meta: meta_of(fields, path),
  }
}

///|
/// Audio, base64 in `data`.
#derive(Eq)
pub(all) struct AudioContent {
  data : String
  mime_type : String
  annotations : Annotations?
  meta : Json?
}

///|
pub extend AudioContent with Eq::{equal, not_equal}

///|
pub extend AudioContent with @json.ToJson::{to_json}

///|
pub impl ToJson for AudioContent with fn to_json(self) {
  json_of([
    ("data", Some(Json::string(self.data))),
    ("mimeType", Some(Json::string(self.mime_type))),
    ("annotations", self.annotations.map(write)),
    ("_meta", self.meta),
  ])
}

///|
pub extend AudioContent with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for AudioContent with fn from_json(json, path) {
  let fields = expect_object(json, path)
  {
    data: required_string(fields, "data", path),
    mime_type: required_string(fields, "mimeType", path),
    annotations: object_member(fields, "annotations", path),
    meta: meta_of(fields, path),
  }
}

///|
/// A resource the client can read, named by URI rather than by value.
#derive(Eq)
pub(all) struct ResourceLink {
  uri : String
  name : String
  title : String?
  description : String?
  mime_type : String?
  size : Int64?
  annotations : Annotations?
  meta : Json?
}

///|
pub extend ResourceLink with Eq::{equal, not_equal}

///|
pub extend ResourceLink with @json.ToJson::{to_json}

///|
pub impl ToJson for ResourceLink with fn to_json(self) {
  json_of([
    ("uri", Some(Json::string(self.uri))),
    ("name", Some(Json::string(self.name))),
    ("title", json_string(self.title)),
    ("description", json_string(self.description)),
    ("mimeType", json_string(self.mime_type)),
    ("size", json_int(self.size)),
    ("annotations", self.annotations.map(write)),
    ("_meta", self.meta),
  ])
}

///|
pub extend ResourceLink with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for ResourceLink with fn from_json(json, path) {
  let fields = expect_object(json, path)
  {
    uri: required_string(fields, "uri", path),
    name: required_string(fields, "name", path),
    title: string_member(fields, "title", path),
    description: string_member(fields, "description", path),
    mime_type: string_member(fields, "mimeType", path),
    size: int_member(fields, "size", path),
    annotations: object_member(fields, "annotations", path),
    meta: meta_of(fields, path),
  }
}

///|
/// Resource contents carried as text.
#derive(Eq)
pub(all) struct TextResource {
  uri : String
  text : String
  mime_type : String?
  meta : Json?
}

///|
pub extend TextResource with Eq::{equal, not_equal}

///|
pub extend TextResource with @json.ToJson::{to_json}

///|
pub impl ToJson for TextResource with fn to_json(self) {
  json_of([
    ("uri", Some(Json::string(self.uri))),
    ("text", Some(Json::string(self.text))),
    ("mimeType", json_string(self.mime_type)),
    ("_meta", self.meta),
  ])
}

///|
pub extend TextResource with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for TextResource with fn from_json(json, path) {
  let fields = expect_object(json, path)
  {
    uri: required_string(fields, "uri", path),
    text: required_string(fields, "text", path),
    mime_type: string_member(fields, "mimeType", path),
    meta: meta_of(fields, path),
  }
}

///|
/// Resource contents carried as base64 in `blob`.
#derive(Eq)
pub(all) struct BlobResource {
  uri : String
  blob : String
  mime_type : String?
  meta : Json?
}

///|
pub extend BlobResource with Eq::{equal, not_equal}

///|
pub extend BlobResource with @json.ToJson::{to_json}

///|
pub impl ToJson for BlobResource with fn to_json(self) {
  json_of([
    ("uri", Some(Json::string(self.uri))),
    ("blob", Some(Json::string(self.blob))),
    ("mimeType", json_string(self.mime_type)),
    ("_meta", self.meta),
  ])
}

///|
pub extend BlobResource with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for BlobResource with fn from_json(json, path) {
  let fields = expect_object(json, path)
  {
    uri: required_string(fields, "uri", path),
    blob: required_string(fields, "blob", path),
    mime_type: string_member(fields, "mimeType", path),
    meta: meta_of(fields, path),
  }
}

///|
/// Either kind of embedded resource contents, told apart by `text` against `blob`.
#derive(Eq)
pub(all) enum Resource {
  Text(TextResource)
  Blob(BlobResource)
}

///|
pub extend Resource with Eq::{equal, not_equal}

///|
pub extend Resource with @json.ToJson::{to_json}

///|
pub impl ToJson for Resource with fn to_json(self) {
  match self {
    Text(resource) => write(resource)
    Blob(resource) => write(resource)
  }
}

///|
pub extend Resource with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for Resource with fn from_json(json, path) {
  let fields = expect_object(json, path)
  if fields.contains("text") {
    Text(read(json, path))
  } else if fields.contains("blob") {
    Blob(read(json, path))
  } else {
    raise @json.JsonDecodeError((path, "want a resource with text or blob"))
  }
}

///|
/// A resource carried by value inside a message.
#derive(Eq)
pub(all) struct EmbeddedResource {
  resource : Resource
  annotations : Annotations?
  meta : Json?
}

///|
pub extend EmbeddedResource with Eq::{equal, not_equal}

///|
pub extend EmbeddedResource with @json.ToJson::{to_json}

///|
pub impl ToJson for EmbeddedResource with fn to_json(self) {
  json_of([
    ("resource", Some(write(self.resource))),
    ("annotations", self.annotations.map(write)),
    ("_meta", self.meta),
  ])
}

///|
pub extend EmbeddedResource with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for EmbeddedResource with fn from_json(json, path) {
  let fields = expect_object(json, path)
  {
    resource: required_object(fields, "resource", path),
    annotations: object_member(fields, "annotations", path),
    meta: meta_of(fields, path),
  }
}

///|
/// One displayable piece of a prompt or of a tool's output, tagged by `type` on the wire.
#derive(Eq)
pub(all) enum ContentBlock {
  Text(TextContent)
  Image(ImageContent)
  Audio(AudioContent)
  ResourceLink(ResourceLink)
  Resource(EmbeddedResource)
}

///|
pub extend ContentBlock with Eq::{equal, not_equal}

///|
pub extend ContentBlock with @json.ToJson::{to_json}

///|
pub impl ToJson for ContentBlock with fn to_json(self) {
  match self {
    Text(content) => json_tagged(write(content), "type", "text")
    Image(content) => json_tagged(write(content), "type", "image")
    Audio(content) => json_tagged(write(content), "type", "audio")
    ResourceLink(content) =>
      json_tagged(write(content), "type", "resource_link")
    Resource(content) => json_tagged(write(content), "type", "resource")
  }
}

///|
pub extend ContentBlock with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for ContentBlock with fn from_json(json, path) {
  let fields = expect_object(json, path)
  match required_string(fields, "type", path) {
    "text" => Text(read(json, path))
    "image" => Image(read(json, path))
    "audio" => Audio(read(json, path))
    "resource_link" => ResourceLink(read(json, path))
    "resource" => Resource(read(json, path))
    other =>
      raise @json.JsonDecodeError(
        (path.add_key("type"), "unknown content block \{other}"),
      )
  }
}

///|
/// A standard content block wrapped for a tool call's output.
#derive(Eq)
pub(all) struct Content {
  content : ContentBlock
  meta : Json?
}

///|
pub extend Content with Eq::{equal, not_equal}

///|
pub extend Content with @json.ToJson::{to_json}

///|
pub impl ToJson for Content with fn to_json(self) {
  json_of([("content", Some(write(self.content))), ("_meta", self.meta)])
}

///|
pub extend Content with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for Content with fn from_json(json, path) {
  let fields = expect_object(json, path)
  {
    content: required_object(fields, "content", path),
    meta: meta_of(fields, path),
  }
}

///|
/// A file edit, given as the whole file before and after.
#derive(Eq)
pub(all) struct Diff {
  path : String
  new_text : String
  old_text : String?
  meta : Json?
}

///|
pub extend Diff with Eq::{equal, not_equal}

///|
pub extend Diff with @json.ToJson::{to_json}

///|
pub impl ToJson for Diff with fn to_json(self) {
  json_of([
    ("path", Some(Json::string(self.path))),
    ("newText", Some(Json::string(self.new_text))),
    ("oldText", json_string(self.old_text)),
    ("_meta", self.meta),
  ])
}

///|
pub extend Diff with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for Diff with fn from_json(json, path) {
  let fields = expect_object(json, path)
  {
    path: required_string(fields, "path", path),
    new_text: required_string(fields, "newText", path),
    old_text: string_member(fields, "oldText", path),
    meta: meta_of(fields, path),
  }
}

///|
/// A reference to a terminal the client opened, embedded in a tool call.
#derive(Eq)
pub(all) struct TerminalRef {
  terminal_id : String
  meta : Json?
}

///|
pub extend TerminalRef with Eq::{equal, not_equal}

///|
/// A reference to a terminal, as a tool call embeds it.
pub fn TerminalRef::new(terminal_id : String) -> TerminalRef {
  { terminal_id, meta: None, }
}

///|
pub extend TerminalRef with @json.ToJson::{to_json}

///|
pub impl ToJson for TerminalRef with fn to_json(self) {
  json_of([
    ("terminalId", Some(Json::string(self.terminal_id))),
    ("_meta", self.meta),
  ])
}

///|
pub extend TerminalRef with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for TerminalRef with fn from_json(json, path) {
  let fields = expect_object(json, path)
  {
    terminal_id: required_string(fields, "terminalId", path),
    meta: meta_of(fields, path),
  }
}

///|
/// What a tool call produced, tagged by `type` on the wire.
#derive(Eq)
pub(all) enum ToolCallContent {
  Content(Content)
  Diff(Diff)
  Terminal(TerminalRef)
}

///|
pub extend ToolCallContent with Eq::{equal, not_equal}

///|
pub extend ToolCallContent with @json.ToJson::{to_json}

///|
pub impl ToJson for ToolCallContent with fn to_json(self) {
  match self {
    Content(content) => json_tagged(write(content), "type", "content")
    Diff(diff) => json_tagged(write(diff), "type", "diff")
    Terminal(terminal) => json_tagged(write(terminal), "type", "terminal")
  }
}

///|
pub extend ToolCallContent with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for ToolCallContent with fn from_json(json, path) {
  let fields = expect_object(json, path)
  match required_string(fields, "type", path) {
    "content" => Content(read(json, path))
    "diff" => Diff(read(json, path))
    "terminal" => Terminal(read(json, path))
    other =>
      raise @json.JsonDecodeError(
        (path.add_key("type"), "unknown tool call content \{other}"),
      )
  }
}

///|
/// A place in the workspace a tool touched.
#derive(Eq)
pub(all) struct ToolCallLocation {
  path : String
  line : Int64?
  meta : Json?
}

///|
pub extend ToolCallLocation with Eq::{equal, not_equal}

///|
pub extend ToolCallLocation with @json.ToJson::{to_json}

///|
pub impl ToJson for ToolCallLocation with fn to_json(self) {
  json_of([
    ("path", Some(Json::string(self.path))),
    ("line", json_int(self.line)),
    ("_meta", self.meta),
  ])
}

///|
pub extend ToolCallLocation with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for ToolCallLocation with fn from_json(json, path) {
  let fields = expect_object(json, path)
  {
    path: required_string(fields, "path", path),
    line: int_member(fields, "line", path),
    meta: meta_of(fields, path),
  }
}
