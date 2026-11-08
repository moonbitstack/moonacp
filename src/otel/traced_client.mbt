// The editor's side: the agent's requests to read a file or run a command are tool executions.
//
// The protocol has the agent ask the editor for the things it may not do itself — read a file,
// write one, open a terminal, wait for it to exit. From the agent's side each of those is a tool
// call, so each one is the span the conventions name for tool execution, and the tool's name is
// the method that was called.
//
// `session/update` is a notification and `session/request_permission` waits on a person, so
// neither is a span: one has no work of its own, the other measures a human.

///|
/// A client that records one span per tool it runs for the agent and answers everything else
/// itself.
priv struct TracedClient {
  inner : &@moonacp.Client
  tracer : @trace.Tracer
  settings : Options
}

///|
/// Wraps a client so that every file and terminal request the agent makes is one span, written to
/// `tracer`. The editor holds no answer to `initialize`, so the agent's name comes from `options`;
/// leaving it out keeps `gen_ai.agent.name` off the span.
pub fn traced_client(
  client : &@moonacp.Client,
  tracer : @trace.Tracer,
  options~ : Options = options,
) -> &@moonacp.Client {
  TracedClient::{ inner: client, tracer, settings: options, }
}

///|
/// Opens the span one tool call runs in.
fn TracedClient::begin(
  self : TracedClient,
  tool : String,
  session : String,
) -> @trace.Span? {
  let name = span_name(@semconv.gen_ai_execute_tool_internal, tool)
  let attributes = opening(
    @semconv.gen_ai_execute_tool_internal,
    self.settings.agent_name,
    self.settings.agent_version,
    session,
  )
  attributes.push((@semconv.gen_ai_tool_name, @trace.Str(tool)))
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
impl @moonacp.Client for TracedClient with fn update(self, id, update) {
  self.inner.update(id, update)
}

///|
impl @moonacp.Client for TracedClient with fn request_permission(self, ask) {
  self.inner.request_permission(ask)
}

///|
impl @moonacp.Client for TracedClient with fn read_text_file(self, request) {
  let span = self.begin("fs/read_text_file", request.session_id)
  let outcome = Ok(self.inner.read_text_file(request)) catch {
    error => Err(error)
  }
  match outcome {
    Ok(text) => {
      closed(span)
      text
    }
    Err(error) => {
      broken(span, error)
      raise error
    }
  }
}

///|
impl @moonacp.Client for TracedClient with fn write_text_file(self, request) {
  let span = self.begin("fs/write_text_file", request.session_id)
  let outcome = Ok(self.inner.write_text_file(request)) catch {
    error => Err(error)
  }
  match outcome {
    Ok(_) => closed(span)
    Err(error) => {
      broken(span, error)
      raise error
    }
  }
}

///|
impl @moonacp.Client for TracedClient with fn create_terminal(self, request) {
  let span = self.begin("terminal/create", request.session_id)
  let outcome = Ok(self.inner.create_terminal(request)) catch {
    error => Err(error)
  }
  match outcome {
    Ok(id) => {
      closed(span)
      id
    }
    Err(error) => {
      broken(span, error)
      raise error
    }
  }
}

///|
impl @moonacp.Client for TracedClient with fn terminal_output(self, request) {
  let span = self.begin("terminal/output", request.session_id)
  let outcome = Ok(self.inner.terminal_output(request)) catch {
    error => Err(error)
  }
  match outcome {
    Ok(output) => {
      closed(span)
      output
    }
    Err(error) => {
      broken(span, error)
      raise error
    }
  }
}

///|
impl @moonacp.Client for TracedClient with fn wait_for_terminal_exit(
  self,
  request,
) {
  let span = self.begin("terminal/wait_for_exit", request.session_id)
  let outcome = Ok(self.inner.wait_for_terminal_exit(request)) catch {
    error => Err(error)
  }
  match outcome {
    Ok(status) => {
      closed(span)
      status
    }
    Err(error) => {
      broken(span, error)
      raise error
    }
  }
}

///|
impl @moonacp.Client for TracedClient with fn kill_terminal(self, request) {
  let span = self.begin("terminal/kill", request.session_id)
  let outcome = Ok(self.inner.kill_terminal(request)) catch {
    error => Err(error)
  }
  match outcome {
    Ok(_) => closed(span)
    Err(error) => {
      broken(span, error)
      raise error
    }
  }
}

///|
impl @moonacp.Client for TracedClient with fn release_terminal(self, request) {
  let span = self.begin("terminal/release", request.session_id)
  let outcome = Ok(self.inner.release_terminal(request)) catch {
    error => Err(error)
  }
  match outcome {
    Ok(_) => closed(span)
    Err(error) => {
      broken(span, error)
      raise error
    }
  }
}

///|
impl @moonacp.Client for TracedClient with fn elicit(self, ask) {
  self.inner.elicit(ask)
}
