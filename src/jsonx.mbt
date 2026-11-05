// Reading and writing the wire shapes every message shares: a JSON object whose keys are the
// schema's camelCase names, absent members left out rather than written as null.

///|
/// Builds an object, dropping the members that are absent.
fn json_of(pairs : Array[(String, Json?)]) -> Json {
  let out : Map[String, Json] = Map([])
  for pair in pairs {
    let (key, value) = pair
    if value is Some(value) {
      out[key] = value
    }
  }
  Json::object(out)
}

///|
/// Adds the discriminator a tagged union carries to the object its payload wrote.
fn json_tagged(payload : Json, key : String, tag : String) -> Json {
  let out = match payload {
    Object(fields) => fields
    _ => Map([])
  }
  out[key] = Json::string(tag)
  Json::object(out)
}

///|
/// Lays a union's payload flat into the object that describes it.
fn merge_json(base : Json, payload : Json) -> Json {
  let fields = match base {
    Object(fields) => fields
    _ => Map([])
  }
  if payload is Object(payload) {
    payload.each(fn(key, value) { fields[key] = value })
  }
  Json::object(fields)
}

///|
fn[A : @json.ToJson] json_list_of(values : Array[A]?) -> Json? {
  json_list(values, value => write(value))
}

///|
fn json_string(value : String?) -> Json? {
  value.map(Json::string)
}

///|
fn json_bool(value : Bool?) -> Json? {
  value.map(Json::boolean)
}

///|
fn json_int(value : Int64?) -> Json? {
  value.map(value => Json::number(value.to_double(), repr=value.to_string()))
}

///|
fn json_float(value : Double?) -> Json? {
  value.map(value => Json::number(value))
}

///|
fn[A] json_list(values : Array[A]?, write : (A) -> Json) -> Json? {
  guard values is Some(values) else { return None }
  Some(Json::array(values.map(write)))
}

///|
/// Encodes through `ToJson`, so the codecs below read as one expression per member.
fn[A : @json.ToJson] write(value : A) -> Json {
  @json.ToJson::to_json(value)
}

///|
/// Decodes through `FromJson`, for the same reason.
fn[A : @json.FromJson] read(
  json : Json,
  path : @json.JsonPath,
) -> A raise @json.JsonDecodeError {
  @json.from_json(json, path~)
}

///|
/// Decodes a whole message body, where no path is being tracked yet. A body that does not decode is
/// the other side's fault, so it raises `Malformed`.
fn[A : @json.FromJson] read_root(json : Json) -> A raise Refused {
  @json.from_json(json) catch {
    @json.JsonDecodeError((path, reason)) =>
      raise Refused::Malformed(reason="\{path}: \{reason}")
  }
}

///|
fn kind_name(json : Json) -> String {
  match json {
    Null => "null"
    True | False => "a boolean"
    Number(_, ..) => "a number"
    String(_) => "a string"
    Array(_) => "an array"
    Object(_) => "an object"
  }
}

///|
fn expect_object(
  json : Json,
  path : @json.JsonPath,
) -> Map[String, Json] raise @json.JsonDecodeError {
  guard json is Object(fields) else {
    raise @json.JsonDecodeError(
      (path, "want an object, got \{kind_name(json)}"),
    )
  }
  fields
}

///|
fn want(
  path : @json.JsonPath,
  expected : String,
  got : Json,
) -> @json.JsonDecodeError {
  @json.JsonDecodeError((path, "want \{expected}, got \{kind_name(got)}"))
}

///|
fn field_of(
  fields : Map[String, Json],
  key : String,
  _path : @json.JsonPath,
) -> Json? {
  match fields.get(key) {
    None | Some(Null) => None
    Some(value) => Some(value)
  }
}

///|
fn required(
  fields : Map[String, Json],
  key : String,
  path : @json.JsonPath,
) -> Json raise @json.JsonDecodeError {
  match fields.get(key) {
    None | Some(Null) =>
      raise @json.JsonDecodeError((path.add_key(key), "missing"))
    Some(value) => value
  }
}

///|
fn text_of(
  value : Json,
  path : @json.JsonPath,
) -> String raise @json.JsonDecodeError {
  guard value is String(text) else { raise want(path, "a string", value) }
  text
}

///|
fn bool_of(
  value : Json,
  path : @json.JsonPath,
) -> Bool raise @json.JsonDecodeError {
  match value {
    True => true
    False => false
    _ => raise want(path, "a boolean", value)
  }
}

///|
/// Numbers arrive as doubles; an integer member rejects a fraction rather than rounding it.
fn int_of(
  value : Json,
  path : @json.JsonPath,
) -> Int64 raise @json.JsonDecodeError {
  guard value is Number(number, ..) && number == number.to_int64().to_double() else {
    raise want(path, "an integer", value)
  }
  number.to_int64()
}

///|
fn float_of(
  value : Json,
  path : @json.JsonPath,
) -> Double raise @json.JsonDecodeError {
  guard value is Number(number, ..) else { raise want(path, "a number", value) }
  number
}

///|
fn array_of(
  value : Json,
  path : @json.JsonPath,
) -> Array[Json] raise @json.JsonDecodeError {
  guard value is Array(items) else { raise want(path, "an array", value) }
  items
}

///|
fn string_member(
  fields : Map[String, Json],
  key : String,
  path : @json.JsonPath,
) -> String? raise @json.JsonDecodeError {
  match field_of(fields, key, path) {
    None => None
    Some(value) => Some(text_of(value, path.add_key(key)))
  }
}

///|
fn required_string(
  fields : Map[String, Json],
  key : String,
  path : @json.JsonPath,
) -> String raise @json.JsonDecodeError {
  text_of(required(fields, key, path), path.add_key(key))
}

///|
fn bool_member(
  fields : Map[String, Json],
  key : String,
  path : @json.JsonPath,
) -> Bool? raise @json.JsonDecodeError {
  match field_of(fields, key, path) {
    None => None
    Some(value) => Some(bool_of(value, path.add_key(key)))
  }
}

///|
fn int_member(
  fields : Map[String, Json],
  key : String,
  path : @json.JsonPath,
) -> Int64? raise @json.JsonDecodeError {
  match field_of(fields, key, path) {
    None => None
    Some(value) => Some(int_of(value, path.add_key(key)))
  }
}

///|
fn float_member(
  fields : Map[String, Json],
  key : String,
  path : @json.JsonPath,
) -> Double? raise @json.JsonDecodeError {
  match field_of(fields, key, path) {
    None => None
    Some(value) => Some(float_of(value, path.add_key(key)))
  }
}

///|
/// A nested object decoded by its own `FromJson`.
fn[A : @json.FromJson] object_member(
  fields : Map[String, Json],
  key : String,
  path : @json.JsonPath,
) -> A? raise @json.JsonDecodeError {
  guard field_of(fields, key, path) is Some(value) else { return None }
  Some(read(value, path.add_key(key)))
}

///|
/// A required nested object.
fn[A : @json.FromJson] required_object(
  fields : Map[String, Json],
  key : String,
  path : @json.JsonPath,
) -> A raise @json.JsonDecodeError {
  read(required(fields, key, path), path.add_key(key))
}

///|
/// A list member, each item with its own path for error messages.
fn[A] list_member(
  fields : Map[String, Json],
  key : String,
  path : @json.JsonPath,
  decode : (Json, @json.JsonPath) -> A raise @json.JsonDecodeError,
) -> Array[A]? raise @json.JsonDecodeError {
  guard field_of(fields, key, path) is Some(value) else { return None }
  let at = path.add_key(key)
  Some(decode_list(value, at, decode))
}

///|
fn[A] decode_list(
  value : Json,
  path : @json.JsonPath,
  decode : (Json, @json.JsonPath) -> A raise @json.JsonDecodeError,
) -> Array[A] raise @json.JsonDecodeError {
  let out = []
  for index, item in array_of(value, path) {
    out.push(decode(item, path.add_index(index)))
  }
  out
}

///|
/// A required list member.
fn[A] required_list(
  fields : Map[String, Json],
  key : String,
  path : @json.JsonPath,
  decode : (Json, @json.JsonPath) -> A raise @json.JsonDecodeError,
) -> Array[A] raise @json.JsonDecodeError {
  decode_list(required(fields, key, path), path.add_key(key), decode)
}

///|
/// A required list of objects, each decoded by its own `FromJson`.
fn[A : @json.FromJson] required_objects(
  fields : Map[String, Json],
  key : String,
  path : @json.JsonPath,
) -> Array[A] raise @json.JsonDecodeError {
  required_list(fields, key, path, (item, at) => read(item, at))
}

///|
fn meta_of(fields : Map[String, Json], path : @json.JsonPath) -> Json? {
  ignore(path)
  field_of(fields, "_meta", path)
}

///|
/// An enum member, read through its own name table.
fn[A] enum_member(
  fields : Map[String, Json],
  key : String,
  path : @json.JsonPath,
  of : (String) -> A?,
) -> A? raise @json.JsonDecodeError {
  guard field_of(fields, key, path) is Some(value) else { return None }
  let at = path.add_key(key)
  match of(text_of(value, at)) {
    Some(variant) => Some(variant)
    None => raise @json.JsonDecodeError((at, "unknown \{key}"))
  }
}

///|
/// A required enum member.
fn[A] required_enum(
  fields : Map[String, Json],
  key : String,
  path : @json.JsonPath,
  of : (String) -> A?,
) -> A raise @json.JsonDecodeError {
  let at = path.add_key(key)
  match of(required_string(fields, key, path)) {
    Some(variant) => variant
    None => raise @json.JsonDecodeError((at, "unknown \{key}"))
  }
}
