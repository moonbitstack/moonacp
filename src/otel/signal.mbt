// The names the conventions fix, and the clock the spans are stamped with.

///|
/// The current time in nanoseconds since the epoch, which is what an OTLP timestamp is.
/// `@async.now` counts milliseconds.
fn now() -> Int64 {
  @async.now() * 1_000_000L
}

///|
/// The operation a signal names: `gen_ai.invoke_agent.internal` names the operation
/// `invoke_agent`, which is what `gen_ai.operation.name` carries and what the span's name begins
/// with. Read off the signal rather than written a second time, so the two cannot drift apart.
fn operation_of(signal : String) -> String {
  match signal.find(".") {
    None => signal
    Some(start) => {
      let rest = signal[start + 1:]
      match rest.find(".") {
        Some(end) => rest[0:end].to_owned()
        None => rest.to_owned()
      }
    }
  }
}

///|
/// The span name the conventions ask for: the operation and what it ran on — the agent's name, or
/// the tool's — or the operation alone when there is nothing to put after it.
fn span_name(signal : String, subject : String) -> String {
  let operation = operation_of(signal)
  if subject == "" {
    operation
  } else {
    operation + " " + subject
  }
}

///|
/// The attributes one span opens with: the operation it covers and the conversation it belongs
/// to, which ACP calls the session, plus the agent when its name is known.
fn opening(
  signal : String,
  agent : String,
  version : String,
  session : String,
) -> Array[(String, @trace.Value)] {
  let attributes : Array[(String, @trace.Value)] = [
    (@semconv.gen_ai_operation_name, @trace.Str(operation_of(signal))),
    (@semconv.gen_ai_conversation_id, @trace.Str(session)),
  ]
  if agent != "" {
    attributes.push((@semconv.gen_ai_agent_name, @trace.Str(agent)))
  }
  if version != "" {
    attributes.push((@semconv.gen_ai_agent_version, @trace.Str(version)))
  }
  attributes
}

///|
/// Ends a span that did its work, saying how it ended.
fn settled(span : @trace.Span?, reason : String) -> Unit {
  match span {
    None => ()
    Some(span) => {
      span.set_attribute(
        @semconv.gen_ai_response_finish_reasons,
        @trace.Strs([reason]),
      )
      span.set_status(@trace.Ok)
      span.finish(at=now())
    }
  }
}

///|
/// Ends a span whose work finished, without claiming anything the signal does not declare.
fn closed(span : @trace.Span?) -> Unit {
  match span {
    None => ()
    Some(span) => {
      span.set_status(@trace.Ok)
      span.finish(at=now())
    }
  }
}

///|
/// Ends a span whose work failed. The conventions give an error a status and, for a body of
/// text, an exception event; the status is what a backend groups on, so that is what is written.
fn broken(span : @trace.Span?, error : @moonacp.Refused) -> Unit {
  match span {
    None => ()
    Some(span) => {
      span.set_status(@trace.Error(error.message()))
      span.finish(at=now())
    }
  }
}
