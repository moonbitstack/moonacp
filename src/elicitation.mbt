// Elicitation: the agent asks the user for a few fields, and the client renders them. The schema is
// the protocol's own small subset of JSON Schema, so it is typed here rather than passed through.

///|
/// A string field's format hint.
#derive(Eq)
pub(all) enum StringFormat {
  Email
  Uri
  Date
  DateTime
}

///|
pub extend StringFormat with Eq::{equal, not_equal}

///|
pub fn StringFormat::to_string(self : StringFormat) -> String {
  match self {
    Email => "email"
    Uri => "uri"
    Date => "date"
    DateTime => "date-time"
  }
}

///|
pub fn StringFormat::of(name : String) -> StringFormat? {
  match name {
    "email" => Some(Email)
    "uri" => Some(Uri)
    "date" => Some(Date)
    "date-time" => Some(DateTime)
    _ => None
  }
}

///|
pub extend StringFormat with @json.ToJson::{to_json}

///|
pub impl ToJson for StringFormat with fn to_json(self) {
  Json::string(self.to_string())
}

///|
pub extend StringFormat with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for StringFormat with fn from_json(json, path) {
  match StringFormat::of(text_of(json, path)) {
    Some(format) => format
    None => raise want(path, "a string format", json)
  }
}

///|
/// One titled choice of a string field.
#derive(Eq)
pub(all) struct EnumOption {
  value : String
  title : String
  description : String?
  meta : Json?
}

///|
pub extend EnumOption with Eq::{equal, not_equal}

///|
pub extend EnumOption with @json.ToJson::{to_json}

///|
pub impl ToJson for EnumOption with fn to_json(self) {
  json_of([
    ("const", Some(Json::string(self.value))),
    ("title", Some(Json::string(self.title))),
    ("description", json_string(self.description)),
    ("_meta", self.meta),
  ])
}

///|
pub extend EnumOption with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for EnumOption with fn from_json(json, path) {
  let fields = expect_object(json, path)
  {
    value: required_string(fields, "const", path),
    title: required_string(fields, "title", path),
    description: string_member(fields, "description", path),
    meta: meta_of(fields, path),
  }
}

///|
/// A field the user types into.
#derive(Eq)
pub(all) struct TextField {
  title : String?
  description : String?
  min_length : Int64?
  max_length : Int64?
  pattern : String?
  format : StringFormat?
  default : String?
  choices : Array[String]?
  titled_choices : Array[EnumOption]?
  meta : Json?
}

///|
pub extend TextField with Eq::{equal, not_equal}

///|
pub extend TextField with @json.ToJson::{to_json}

///|
pub impl ToJson for TextField with fn to_json(self) {
  json_of([
    ("title", json_string(self.title)),
    ("description", json_string(self.description)),
    ("minLength", json_int(self.min_length)),
    ("maxLength", json_int(self.max_length)),
    ("pattern", json_string(self.pattern)),
    ("format", self.format.map(write)),
    ("default", json_string(self.default)),
    ("enum", json_list(self.choices, Json::string)),
    ("oneOf", json_list_of(self.titled_choices)),
    ("_meta", self.meta),
  ])
}

///|
pub extend TextField with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for TextField with fn from_json(json, path) {
  let fields = expect_object(json, path)
  {
    title: string_member(fields, "title", path),
    description: string_member(fields, "description", path),
    min_length: int_member(fields, "minLength", path),
    max_length: int_member(fields, "maxLength", path),
    pattern: string_member(fields, "pattern", path),
    format: enum_member(fields, "format", path, StringFormat::of),
    default: string_member(fields, "default", path),
    choices: list_member(fields, "enum", path, (value, at) => text_of(value, at)),
    titled_choices: list_member(fields, "oneOf", path, (value, at) => {
      read(value, at)
    }),
    meta: meta_of(fields, path),
  }
}

///|
/// A field for a fractional number.
#derive(Eq)
pub(all) struct NumberField {
  title : String?
  description : String?
  minimum : Double?
  maximum : Double?
  default : Double?
  meta : Json?
}

///|
pub extend NumberField with Eq::{equal, not_equal}

///|
pub extend NumberField with @json.ToJson::{to_json}

///|
pub impl ToJson for NumberField with fn to_json(self) {
  json_of([
    ("title", json_string(self.title)),
    ("description", json_string(self.description)),
    ("minimum", json_float(self.minimum)),
    ("maximum", json_float(self.maximum)),
    ("default", json_float(self.default)),
    ("_meta", self.meta),
  ])
}

///|
pub extend NumberField with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for NumberField with fn from_json(json, path) {
  let fields = expect_object(json, path)
  {
    title: string_member(fields, "title", path),
    description: string_member(fields, "description", path),
    minimum: float_member(fields, "minimum", path),
    maximum: float_member(fields, "maximum", path),
    default: float_member(fields, "default", path),
    meta: meta_of(fields, path),
  }
}

///|
/// A field for a whole number.
#derive(Eq)
pub(all) struct IntegerField {
  title : String?
  description : String?
  minimum : Int64?
  maximum : Int64?
  default : Int64?
  meta : Json?
}

///|
pub extend IntegerField with Eq::{equal, not_equal}

///|
pub extend IntegerField with @json.ToJson::{to_json}

///|
pub impl ToJson for IntegerField with fn to_json(self) {
  json_of([
    ("title", json_string(self.title)),
    ("description", json_string(self.description)),
    ("minimum", json_int(self.minimum)),
    ("maximum", json_int(self.maximum)),
    ("default", json_int(self.default)),
    ("_meta", self.meta),
  ])
}

///|
pub extend IntegerField with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for IntegerField with fn from_json(json, path) {
  let fields = expect_object(json, path)
  {
    title: string_member(fields, "title", path),
    description: string_member(fields, "description", path),
    minimum: int_member(fields, "minimum", path),
    maximum: int_member(fields, "maximum", path),
    default: int_member(fields, "default", path),
    meta: meta_of(fields, path),
  }
}

///|
/// A field for yes or no.
#derive(Eq)
pub(all) struct BooleanField {
  title : String?
  description : String?
  default : Bool?
  meta : Json?
}

///|
pub extend BooleanField with Eq::{equal, not_equal}

///|
pub extend BooleanField with @json.ToJson::{to_json}

///|
pub impl ToJson for BooleanField with fn to_json(self) {
  json_of([
    ("title", json_string(self.title)),
    ("description", json_string(self.description)),
    ("default", json_bool(self.default)),
    ("_meta", self.meta),
  ])
}

///|
pub extend BooleanField with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for BooleanField with fn from_json(json, path) {
  let fields = expect_object(json, path)
  {
    title: string_member(fields, "title", path),
    description: string_member(fields, "description", path),
    default: bool_member(fields, "default", path),
    meta: meta_of(fields, path),
  }
}

///|
/// What a multi-select offers: bare values or titled ones.
#derive(Eq)
pub(all) enum ChoiceItems {
  Values(Array[String])
  Titled(Array[EnumOption])
}

///|
pub extend ChoiceItems with Eq::{equal, not_equal}

///|
pub extend ChoiceItems with @json.ToJson::{to_json}

///|
pub impl ToJson for ChoiceItems with fn to_json(self) {
  match self {
    Values(values) => Json::array(values.map(Json::string))
    Titled(options) => Json::array(options.map(write))
  }
}

///|
/// A field for picking several of a set.
#derive(Eq)
pub(all) struct MultiSelectField {
  title : String?
  description : String?
  min_items : Int64?
  max_items : Int64?
  items : ChoiceItems
  default : Array[String]?
  meta : Json?
}

///|
pub extend MultiSelectField with Eq::{equal, not_equal}

///|
pub extend MultiSelectField with @json.ToJson::{to_json}

///|
pub impl ToJson for MultiSelectField with fn to_json(self) {
  json_of([
    ("title", json_string(self.title)),
    ("description", json_string(self.description)),
    ("minItems", json_int(self.min_items)),
    ("maxItems", json_int(self.max_items)),
    ("items", Some(write(self.items))),
    ("default", json_list(self.default, Json::string)),
    ("_meta", self.meta),
  ])
}

///|
pub extend MultiSelectField with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for MultiSelectField with fn from_json(json, path) {
  let fields = expect_object(json, path)
  let items = match field_of(fields, "items", path) {
    None => Values([])
    Some(value) => {
      let at = path.add_key("items")
      if value is Array(entries) &&
        entries.length() > 0 &&
        (match entries[0] {
          Object(entry) => entry.contains("const") || entry.contains("title")
          _ => false
        }) {
        Titled(decode_list(value, at, (item, at) => read(item, at)))
      } else if value is Object(entry) && entry.contains("anyOf") {
        Titled(
          match object_member(entry, "anyOf", at) {
            Some(options) => {
              let options : Array[EnumOption] = options
              options
            }
            None => []
          },
        )
      } else {
        Values(decode_list(value, at, (item, at) => text_of(item, at)))
      }
    }
  }
  {
    title: string_member(fields, "title", path),
    description: string_member(fields, "description", path),
    min_items: int_member(fields, "minItems", path),
    max_items: int_member(fields, "maxItems", path),
    items,
    default: list_member(fields, "default", path, (value, at) => {
      text_of(value, at)
    }),
    meta: meta_of(fields, path),
  }
}

///|
/// One field of a form, tagged by `type` on the wire. A kind the protocol does not define yet is
/// kept as it came so a client can still show it.
#derive(Eq)
pub(all) enum Field {
  Text(TextField)
  Number(NumberField)
  Integer(IntegerField)
  Boolean(BooleanField)
  MultiSelect(MultiSelectField)
  Other(Json)
}

///|
pub extend Field with Eq::{equal, not_equal}

///|
pub extend Field with @json.ToJson::{to_json}

///|
pub impl ToJson for Field with fn to_json(self) {
  match self {
    Text(field) => json_tagged(write(field), "type", "string")
    Number(field) => json_tagged(write(field), "type", "number")
    Integer(field) => json_tagged(write(field), "type", "integer")
    Boolean(field) => json_tagged(write(field), "type", "boolean")
    MultiSelect(field) => json_tagged(write(field), "type", "array")
    Other(json) => json
  }
}

///|
pub extend Field with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for Field with fn from_json(json, path) {
  let fields = expect_object(json, path)
  match string_member(fields, "type", path) {
    Some("string") => Text(read(json, path))
    Some("number") => Number(read(json, path))
    Some("integer") => Integer(read(json, path))
    Some("boolean") => Boolean(read(json, path))
    Some("array") => MultiSelect(read(json, path))
    _ => Other(json)
  }
}

///|
/// The form to render.
#derive(Eq)
pub(all) struct ElicitationSchema {
  properties : Map[String, Field]
  required : Array[String]?
  title : String?
  description : String?
  meta : Json?
}

///|
pub extend ElicitationSchema with Eq::{equal, not_equal}

///|
pub extend ElicitationSchema with @json.ToJson::{to_json}

///|
pub impl ToJson for ElicitationSchema with fn to_json(self) {
  let properties : Map[String, Json] = Map([])
  for entry in self.properties.iter() {
    let (name, field) = entry
    properties[name] = write(field)
  }
  json_of([
    ("type", Some(Json::string("object"))),
    ("title", json_string(self.title)),
    ("description", json_string(self.description)),
    ("properties", Some(Json::object(properties))),
    ("required", json_list(self.required, Json::string)),
    ("_meta", self.meta),
  ])
}

///|
pub extend ElicitationSchema with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for ElicitationSchema with fn from_json(json, path) {
  let fields = expect_object(json, path)
  let properties : Map[String, Field] = Map([])
  match field_of(fields, "properties", path) {
    None => ()
    Some(value) => {
      let at = path.add_key("properties")
      let entries = expect_object(value, at)
      for entry in entries.iter() {
        let (name, field) = entry
        properties[name] = @json.from_json(field, path=at.add_key(name))
      }
    }
  }
  {
    properties,
    required: list_member(fields, "required", path, (value, at) => {
      text_of(value, at)
    }),
    title: string_member(fields, "title", path),
    description: string_member(fields, "description", path),
    meta: meta_of(fields, path),
  }
}

///|
/// Which request an elicitation belongs to: a session's turn, or a bare JSON-RPC request.
#derive(Eq)
pub(all) enum ElicitScope {
  OfSession(String, String?)
  OfRequest(Json)
}

///|
pub extend ElicitScope with Eq::{equal, not_equal}

///|
pub extend ElicitScope with @json.ToJson::{to_json}

///|
pub impl ToJson for ElicitScope with fn to_json(self) {
  match self {
    OfSession(session_id, tool_call_id) =>
      json_of([
        ("sessionId", Some(Json::string(session_id))),
        ("toolCallId", json_string(tool_call_id)),
      ])
    OfRequest(request_id) => json_of([("requestId", Some(request_id))])
  }
}

///|
pub extend ElicitScope with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for ElicitScope with fn from_json(json, path) {
  let fields = expect_object(json, path)
  match string_member(fields, "sessionId", path) {
    Some(session_id) =>
      OfSession(session_id, string_member(fields, "toolCallId", path))
    None => OfRequest(required(fields, "requestId", path))
  }
}

///|
/// A form for the user to fill in.
#derive(Eq)
pub(all) struct FormRequest {
  message : String
  schema : ElicitationSchema
  scope : ElicitScope
  meta : Json?
}

///|
pub extend FormRequest with Eq::{equal, not_equal}

///|
pub extend FormRequest with @json.ToJson::{to_json}

///|
pub impl ToJson for FormRequest with fn to_json(self) {
  json_tagged(
    merge_json(
      write(self.scope),
      json_of([
        ("message", Some(Json::string(self.message))),
        ("requestedSchema", Some(write(self.schema))),
        ("_meta", self.meta),
      ]),
    ),
    "mode",
    "form",
  )
}

///|
pub extend FormRequest with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for FormRequest with fn from_json(json, path) {
  let fields = expect_object(json, path)
  {
    message: required_string(fields, "message", path),
    schema: required_object(fields, "requestedSchema", path),
    scope: read(json, path),
    meta: meta_of(fields, path),
  }
}

///|
/// A link the user follows.
#derive(Eq)
pub(all) struct UrlRequest {
  message : String
  elicitation_id : String
  url : String
  scope : ElicitScope
  meta : Json?
}

///|
pub extend UrlRequest with Eq::{equal, not_equal}

///|
pub extend UrlRequest with @json.ToJson::{to_json}

///|
pub impl ToJson for UrlRequest with fn to_json(self) {
  json_tagged(
    merge_json(
      write(self.scope),
      json_of([
        ("message", Some(Json::string(self.message))),
        ("elicitationId", Some(Json::string(self.elicitation_id))),
        ("url", Some(Json::string(self.url))),
        ("_meta", self.meta),
      ]),
    ),
    "mode",
    "url",
  )
}

///|
pub extend UrlRequest with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for UrlRequest with fn from_json(json, path) {
  let fields = expect_object(json, path)
  {
    message: required_string(fields, "message", path),
    elicitation_id: required_string(fields, "elicitationId", path),
    url: required_string(fields, "url", path),
    scope: read(json, path),
    meta: meta_of(fields, path),
  }
}

///|
/// An ask, tagged by `mode` on the wire.
#derive(Eq)
pub(all) enum Elicitation {
  Form(FormRequest)
  Url(UrlRequest)
}

///|
pub extend Elicitation with Eq::{equal, not_equal}

///|
pub extend Elicitation with @json.ToJson::{to_json}

///|
pub impl ToJson for Elicitation with fn to_json(self) {
  match self {
    Form(request) => write(request)
    Url(request) => write(request)
  }
}

///|
pub extend Elicitation with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for Elicitation with fn from_json(json, path) {
  let fields = expect_object(json, path)
  match string_member(fields, "mode", path) {
    Some("form") => Form(read(json, path))
    Some("url") => Url(read(json, path))
    Some(other) =>
      raise @json.JsonDecodeError(
        (path.add_key("mode"), "unknown elicitation \{other}"),
      )
    None => raise @json.JsonDecodeError((path.add_key("mode"), "missing"))
  }
}

///|
/// What the user did with the ask. `content` holds one value per field, of whatever type the field
/// asked for, so it stays raw.
#derive(Eq)
pub(all) enum Answer {
  Accept(Map[String, Json]?)
  Decline
  Cancel
  Other(String)
}

///|
pub extend Answer with Eq::{equal, not_equal}

///|
pub extend Answer with @json.ToJson::{to_json}

///|
pub impl ToJson for Answer with fn to_json(self) {
  match self {
    Accept(content) =>
      json_tagged(
        json_of([("content", content.map(Json::object))]),
        "action",
        "accept",
      )
    Decline => json_tagged(Json::empty_object(), "action", "decline")
    Cancel => json_tagged(Json::empty_object(), "action", "cancel")
    Other(action) => json_tagged(Json::empty_object(), "action", action)
  }
}

///|
pub extend Answer with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for Answer with fn from_json(json, path) {
  let fields = expect_object(json, path)
  match required_string(fields, "action", path) {
    "accept" =>
      Accept(
        match field_of(fields, "content", path) {
          None => None
          Some(value) => Some(expect_object(value, path.add_key("content")))
        },
      )
    "decline" => Decline
    "cancel" => Cancel
    other => Other(other)
  }
}
