// Session setup: the modes and configuration options a client shows in its picker, and the session
// identifiers the rest of the protocol keys on.

///|
/// One mode the agent can work in.
#derive(Eq)
pub(all) struct SessionMode {
  id : String
  name : String
  description : String?
  meta : Json?
}

///|
pub extend SessionMode with Eq::{equal, not_equal}

///|
pub extend SessionMode with @json.ToJson::{to_json}

///|
pub impl ToJson for SessionMode with fn to_json(self) {
  json_of([
    ("id", Some(Json::string(self.id))),
    ("name", Some(Json::string(self.name))),
    ("description", json_string(self.description)),
    ("_meta", self.meta),
  ])
}

///|
pub extend SessionMode with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for SessionMode with fn from_json(json, path) {
  let fields = expect_object(json, path)
  {
    id: required_string(fields, "id", path),
    name: required_string(fields, "name", path),
    description: string_member(fields, "description", path),
    meta: meta_of(fields, path),
  }
}

///|
/// The modes on offer and the one in force.
#derive(Eq)
pub(all) struct SessionModes {
  current_mode_id : String
  available_modes : Array[SessionMode]
  meta : Json?
}

///|
pub extend SessionModes with Eq::{equal, not_equal}

///|
pub extend SessionModes with @json.ToJson::{to_json}

///|
pub impl ToJson for SessionModes with fn to_json(self) {
  json_of([
    ("currentModeId", Some(Json::string(self.current_mode_id))),
    ("availableModes", Some(Json::array(self.available_modes.map(write)))),
    ("_meta", self.meta),
  ])
}

///|
pub extend SessionModes with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for SessionModes with fn from_json(json, path) {
  let fields = expect_object(json, path)
  {
    current_mode_id: required_string(fields, "currentModeId", path),
    available_modes: required_objects(fields, "availableModes", path),
    meta: meta_of(fields, path),
  }
}

///|
/// What a configuration option is about, so a client can place it. Unknown categories are kept.
#derive(Eq)
pub(all) enum ConfigCategory {
  Mode
  Model
  ModelConfig
  ThoughtLevel
  Other(String)
}

///|
pub extend ConfigCategory with Eq::{equal, not_equal}

///|
pub fn ConfigCategory::to_string(self : ConfigCategory) -> String {
  match self {
    Mode => "mode"
    Model => "model"
    ModelConfig => "model_config"
    ThoughtLevel => "thought_level"
    Other(name) => name
  }
}

///|
pub fn ConfigCategory::of(name : String) -> ConfigCategory {
  match name {
    "mode" => Mode
    "model" => Model
    "model_config" => ModelConfig
    "thought_level" => ThoughtLevel
    other => Other(other)
  }
}

///|
pub extend ConfigCategory with @json.ToJson::{to_json}

///|
pub impl ToJson for ConfigCategory with fn to_json(self) {
  Json::string(self.to_string())
}

///|
pub extend ConfigCategory with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for ConfigCategory with fn from_json(json, path) {
  ConfigCategory::of(text_of(json, path))
}

///|
/// One value of a dropdown.
#derive(Eq)
pub(all) struct ConfigChoice {
  value : String
  name : String
  description : String?
  meta : Json?
}

///|
pub extend ConfigChoice with Eq::{equal, not_equal}

///|
pub extend ConfigChoice with @json.ToJson::{to_json}

///|
pub impl ToJson for ConfigChoice with fn to_json(self) {
  json_of([
    ("value", Some(Json::string(self.value))),
    ("name", Some(Json::string(self.name))),
    ("description", json_string(self.description)),
    ("_meta", self.meta),
  ])
}

///|
pub extend ConfigChoice with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for ConfigChoice with fn from_json(json, path) {
  let fields = expect_object(json, path)
  {
    value: required_string(fields, "value", path),
    name: required_string(fields, "name", path),
    description: string_member(fields, "description", path),
    meta: meta_of(fields, path),
  }
}

///|
/// Choices under a heading.
#derive(Eq)
pub(all) struct ConfigGroup {
  group : String
  name : String
  options : Array[ConfigChoice]
  meta : Json?
}

///|
pub extend ConfigGroup with Eq::{equal, not_equal}

///|
pub extend ConfigGroup with @json.ToJson::{to_json}

///|
pub impl ToJson for ConfigGroup with fn to_json(self) {
  json_of([
    ("group", Some(Json::string(self.group))),
    ("name", Some(Json::string(self.name))),
    ("options", Some(Json::array(self.options.map(write)))),
    ("_meta", self.meta),
  ])
}

///|
pub extend ConfigGroup with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for ConfigGroup with fn from_json(json, path) {
  let fields = expect_object(json, path)
  {
    group: required_string(fields, "group", path),
    name: required_string(fields, "name", path),
    options: required_objects(fields, "options", path),
    meta: meta_of(fields, path),
  }
}

///|
/// The choices of a dropdown, flat or grouped. The two are told apart by whether the first entry
/// carries `group`.
#derive(Eq)
pub(all) enum ConfigChoices {
  Flat(Array[ConfigChoice])
  Grouped(Array[ConfigGroup])
}

///|
pub extend ConfigChoices with Eq::{equal, not_equal}

///|
pub extend ConfigChoices with @json.ToJson::{to_json}

///|
pub impl ToJson for ConfigChoices with fn to_json(self) {
  match self {
    Flat(choices) => Json::array(choices.map(write))
    Grouped(groups) => Json::array(groups.map(write))
  }
}

///|
pub extend ConfigChoices with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for ConfigChoices with fn from_json(json, path) {
  let items = array_of(json, path)
  if items.length() > 0 &&
    (match items[0] {
      Object(fields) => fields.contains("group")
      _ => false
    }) {
    Grouped(decode_list(json, path, (item, at) => read(item, at)))
  } else {
    Flat(decode_list(json, path, (item, at) => read(item, at)))
  }
}

///|
/// What a configuration option holds: a picked value or a switch.
#derive(Eq)
pub(all) enum ConfigValue {
  Select(String, ConfigChoices)
  Boolean(Bool)
}

///|
pub extend ConfigValue with Eq::{equal, not_equal}

///|
pub extend ConfigValue with @json.ToJson::{to_json}

///|
pub impl ToJson for ConfigValue with fn to_json(self) {
  match self {
    Select(current_value, options) =>
      json_of([
        ("currentValue", Some(Json::string(current_value))),
        ("options", Some(write(options))),
      ])
    Boolean(value) => json_of([("currentValue", Some(Json::boolean(value)))])
  }
}

///|
/// One entry of the session configuration picker.
#derive(Eq)
pub(all) struct ConfigOption {
  id : String
  name : String
  description : String?
  category : ConfigCategory?
  value : ConfigValue
  meta : Json?
}

///|
pub extend ConfigOption with Eq::{equal, not_equal}

///|
pub extend ConfigOption with @json.ToJson::{to_json}

///|
pub impl ToJson for ConfigOption with fn to_json(self) {
  let (tag, body) = match self.value {
    Select(_, _) => ("select", write(self.value))
    Boolean(_) => ("boolean", write(self.value))
  }
  let base = json_of([
    ("id", Some(Json::string(self.id))),
    ("name", Some(Json::string(self.name))),
    ("description", json_string(self.description)),
    ("category", self.category.map(write)),
    ("_meta", self.meta),
  ])
  json_tagged(merge_json(base, body), "type", tag)
}

///|
pub extend ConfigOption with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for ConfigOption with fn from_json(json, path) {
  let fields = expect_object(json, path)
  let id = required_string(fields, "id", path)
  let name = required_string(fields, "name", path)
  let description = string_member(fields, "description", path)
  let category = enum_member(fields, "category", path, name => {
    Some(ConfigCategory::of(name))
  })
  let meta = meta_of(fields, path)
  let value = match required_string(fields, "type", path) {
    "select" =>
      Select(
        required_string(fields, "currentValue", path),
        required_object(fields, "options", path),
      )
    "boolean" =>
      Boolean(
        bool_of(
          required(fields, "currentValue", path),
          path.add_key("currentValue"),
        ),
      )
    other =>
      raise @json.JsonDecodeError(
        (path.add_key("type"), "unknown config option \{other}"),
      )
  }
  { id, name, description, category, value, meta, }
}

///|
/// What `session/new` and its siblings answer with.
#derive(Eq)
pub(all) struct SessionStarted {
  session_id : String
  modes : SessionModes?
  config_options : Array[ConfigOption]?
  meta : Json?
}

///|
pub extend SessionStarted with Eq::{equal, not_equal}

///|
pub extend SessionStarted with @json.ToJson::{to_json}

///|
pub impl ToJson for SessionStarted with fn to_json(self) {
  json_of([
    ("sessionId", Some(Json::string(self.session_id))),
    ("modes", self.modes.map(write)),
    ("configOptions", json_list_of(self.config_options)),
    ("_meta", self.meta),
  ])
}

///|
pub extend SessionStarted with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for SessionStarted with fn from_json(json, path) {
  let fields = expect_object(json, path)
  {
    session_id: required_string(fields, "sessionId", path),
    modes: object_member(fields, "modes", path),
    config_options: list_member(fields, "configOptions", path, (value, at) => {
      read(value, at)
    }),
    meta: meta_of(fields, path),
  }
}

///|
/// The whole option list after one of them changed.
#derive(Eq)
pub(all) struct SetConfigOptions {
  config_options : Array[ConfigOption]
  meta : Json?
}

///|
pub extend SetConfigOptions with Eq::{equal, not_equal}

///|
pub extend SetConfigOptions with @json.ToJson::{to_json}

///|
pub impl ToJson for SetConfigOptions with fn to_json(self) {
  json_of([
    ("configOptions", Some(Json::array(self.config_options.map(write)))),
    ("_meta", self.meta),
  ])
}

///|
pub extend SetConfigOptions with @json.FromJson::{from_json}

///|
pub impl @json.FromJson for SetConfigOptions with fn from_json(json, path) {
  let fields = expect_object(json, path)
  {
    config_options: required_objects(fields, "configOptions", path),
    meta: meta_of(fields, path),
  }
}
