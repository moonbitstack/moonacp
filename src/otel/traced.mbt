// The agent's side: a turn is one span.

///|
/// An agent that records a span for every turn and answers everything else itself.
///
/// The span is the one the conventions name for an agent running in the same process as its
/// caller: `invoke_agent` and the agent's name, of kind internal, stamped with the agent's
/// version and the conversation — ACP's session. A turn that ends is `Ok` and says how it ended;
/// a turn that fails carries the failure as its status and still ends.
///
/// Prompt text and answer text are never recorded: a trace is read by more people than the
/// conversation is, and turning that on is a decision for the application, not for a wrapper.
priv struct Traced {
  inner : &@moonacp.Agent
  tracer : @trace.Tracer
  mut agent_name : String
  mut agent_version : String
}

///|
/// Wraps an agent so that each turn it runs is one span, written to `tracer`.
///
/// The agent's name and version come from its answer to `initialize`; `options` fills them in for
/// an agent that answers without `agentInfo`, as a quieter one may.
pub fn traced(
  agent : &@moonacp.Agent,
  tracer : @trace.Tracer,
  options~ : Options = options,
) -> &@moonacp.Agent {
  Traced::{
    inner: agent,
    tracer,
    agent_name: options.agent_name,
    agent_version: options.agent_version,
  }
}

///|
/// Opens the span a turn runs in. A tracer that cannot mint an identifier leaves the turn
/// untraced rather than failing it: an agent works whether or not anyone is watching.
fn Traced::begin(self : Traced, session : String) -> @trace.Span? {
  let name = span_name(@semconv.gen_ai_invoke_agent_internal, self.agent_name)
  let attributes = opening(
    @semconv.gen_ai_invoke_agent_internal,
    self.agent_name,
    self.agent_version,
    session,
  )
  let started = self.tracer.start(
    name,
    kind=@trace.Internal,
    at=now(),
    attributes~,
  ) catch {
    _ => return None
  }
  Some(started)
}

///|
impl @moonacp.Agent for Traced with fn initialize(self, request) {
  let answer = self.inner.initialize(request)
  match answer.agent_info {
    Some(info) => {
      self.agent_name = info.name
      self.agent_version = info.version
    }
    None => ()
  }
  answer
}

///|
impl @moonacp.Agent for Traced with fn authenticate(self, request) {
  self.inner.authenticate(request)
}

///|
impl @moonacp.Agent for Traced with fn logout(self) {
  self.inner.logout()
}

///|
impl @moonacp.Agent for Traced with fn new_session(self, request) {
  self.inner.new_session(request)
}

///|
impl @moonacp.Agent for Traced with fn load_session(self, request, session) {
  self.inner.load_session(request, session)
}

///|
impl @moonacp.Agent for Traced with fn resume_session(self, request, session) {
  self.inner.resume_session(request, session)
}

///|
impl @moonacp.Agent for Traced with fn list_sessions(self, request) {
  self.inner.list_sessions(request)
}

///|
impl @moonacp.Agent for Traced with fn delete_session(self, request) {
  self.inner.delete_session(request)
}

///|
impl @moonacp.Agent for Traced with fn close_session(self, request) {
  self.inner.close_session(request)
}

///|
impl @moonacp.Agent for Traced with fn set_mode(self, request) {
  self.inner.set_mode(request)
}

///|
impl @moonacp.Agent for Traced with fn set_config_option(self, request) {
  self.inner.set_config_option(request)
}

///|
impl @moonacp.Agent for Traced with fn prompt(self, request, session) {
  let span = self.begin(request.session_id)
  let outcome = Ok(self.inner.prompt(request, session)) catch {
    error => Err(error)
  }
  match outcome {
    Ok(reason) => {
      settled(span, reason.to_string())
      reason
    }
    Err(error) => {
      broken(span, error)
      raise error
    }
  }
}

///|
impl @moonacp.Agent for Traced with fn cancel(self, id) {
  self.inner.cancel(id)
}
