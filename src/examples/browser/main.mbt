// The playground's engine: this library, built to JavaScript, so the page renders what the library
// writes rather than a copy of it.
//
// Strings in, strings out. `preview` takes the settings the page offers and returns the messages a
// conversation would put on the wire — encoded by the library's own `ToJson` implementations and
// read back by its `FromJson` ones, so a shape the page shows is a shape the library produces.

///|
/// One JSON-RPC request, wrapped the way the protocol carries parameters.
fn request(id : Int32, name : String, params : Json) -> Json {
  {
    "jsonrpc": Json::string("2.0"),
    "id": Json::number(id.to_double(), repr=id.to_string()),
    "method": Json::string(name),
    "params": params,
  }
}

///|
/// One JSON-RPC notification: no identifier, because nothing answers it.
fn notice(name : String, params : Json) -> Json {
  {
    "jsonrpc": Json::string("2.0"),
    "method": Json::string(name),
    "params": params,
  }
}

///|
/// A text field of the settings object that came from the page.
fn text_of(settings : Json, key : String, fallback : String) -> String {
  guard settings is Object(fields) else { return fallback }
  match fields.get(key) {
    Some(String(text)) => text
    _ => fallback
  }
}

///|
fn flag_of(settings : Json, key : String) -> Bool {
  guard settings is Object(fields) else { return false }
  match fields.get(key) {
    Some(True) => true
    _ => false
  }
}

///|
/// The stop reason the page asked for, read the way a peer reads one off the wire: through the
/// library's own decoder, so an unknown name is the library's answer and not this page's.
fn reason_of(settings : Json) -> @moonacp.StopReason {
  let asked = Json::string(text_of(settings, "stop_reason", "end_turn"))
  @json.from_json(asked) catch {
    _ => @moonacp.StopReason::EndTurn
  }
}

///|
fn text_block(text : String) -> @moonacp.ContentBlock {
  @moonacp.ContentBlock::Text({ text, annotations: None, meta: None, })
}

///|
/// The shape of the page's answer: one request, the notifications a turn streams, the frame each
/// one travels in, and the result.
fn answer_of(asking : Json, updates : Array[Json], result : Json) -> String {
  let frames : Array[Json] = []
  for update in updates {
    // What a stream writes: the message after `data: `, and a blank line after it.
    frames.push(Json("data: " + @moonjson.dumps(update, indent=0) + "\r\n\r\n"))
  }
  let out : Map[String, Json] = Map([])
  out["request"] = Json(@moonjson.dumps(asking, indent=2))
  out["updates"] = Json(
    Json::array(updates.map(json => Json(@moonjson.dumps(json, indent=2)))),
  )
  out["frames"] = Json(Json::array(frames))
  out["result"] = Json(@moonjson.dumps(result, indent=2))
  Json::object(out).stringify()
}

///|
/// The conversation the settings describe: the prompt an editor sends, the updates an agent streams
/// back, and the result the turn ends with.
pub fn preview(settings : String) -> String {
  let asked = @moonjson.loads(settings, @moonjson.strict) catch {
    _ => Json::empty_object()
  }
  let text = text_of(asked, "text", "summarise the notes")
  let session = "notes-1"
  let prompt : @moonacp.Prompt = {
    session_id: session,
    prompt: [text_block(text)],
    meta: None,
  }
  let updates : Array[Json] = []
  updates.push(
    notice("session/update", {
      "sessionId": Json::string(session),
      "update": @moonacp.SessionUpdate::AgentMessageChunk({
        content: text_block("You said: " + text),
        message_id: None,
        meta: None,
      }).to_json(),
    }),
  )
  if flag_of(asked, "tool_call") {
    let call : @moonacp.ToolCall = {
      tool_call_id: "c-1",
      title: "write /work/notes.md",
      name: None,
      kind: Some(@moonacp.ToolKind::Edit),
      status: Some(@moonacp.ToolCallStatus::Pending),
      content: None,
      locations: None,
      raw_input: None,
      raw_output: None,
      meta: None,
    }
    updates.push(
      notice("session/update", {
        "sessionId": Json::string(session),
        "update": @moonacp.SessionUpdate::ToolCall(call).to_json(),
      }),
    )
  }
  let outcome : @moonacp.PromptResult = {
    stop_reason: reason_of(asked),
    meta: None,
  }
  let result : Json = {
    "jsonrpc": Json::string("2.0"),
    "id": Json::number(3.0, repr="3"),
    "result": outcome.to_json(),
  }
  answer_of(request(3, "session/prompt", prompt.to_json()), updates, result)
}
