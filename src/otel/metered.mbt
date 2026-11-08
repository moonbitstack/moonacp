// The other signal: how long an operation took, as the convention's histogram rather than a span.
//
// The exporter is the one `moontel` builds, so a program that already has a metric path — OTLP over
// HTTP or gRPC, or a Prometheus registry bridged by `moontel/otlp/p8s` — hands the same one here.

///|
/// The unit a duration is measured in, which the conventions spell `s`.
let seconds_unit : String = "s"

///|
let turn_description : String = "How long one turn took, from the prompt to its last chunk or its failure."

///|
let tool_description : String = "How long the editor took to answer one request from the agent."

///|
/// One metric: an explicit-bucket histogram of seconds, cumulative, under the name the conventions
/// give it.
fn histogram(
  name : String,
  description : String,
  point : @otlp.DataPoint,
) -> @otlp.Metric {
  {
    name,
    description,
    unit: seconds_unit,
    kind: @otlp.MetricKind::Histogram(temporality=@otlp.Temporality::Cumulative),
    points: [point],
  }
}

// The agent's side: one observation of `gen_ai.invoke_agent.duration` per turn.
//
// The conventions say the value SHOULD be the same as the duration of the turn's span, which is
// what this reads: the clock starts where the span starts and stops where it stops, whether the
// turn ended or failed.

///|
/// An agent that records how long each turn took and answers everything else itself.
///
/// The histogram is cumulative and lives as long as the wrapper, so every turn exports the state of
/// the world after that turn. A reader keeps the newest one; the counts never reset.
priv struct Metered {
  inner : &@moonacp.Agent
  exporter : @otlp.MetricsExporter
  mut agent_name : String
  turns : Seconds
}

///|
/// Wraps an agent so that each turn it runs is one observation of
/// `gen_ai.invoke_agent.duration`, handed to `exporter`.
///
/// The agent's name comes from its answer to `initialize`; `options` fills it in for an agent that
/// answers without `agentInfo`. The conversation is not an attribute of this metric — only the
/// agent is — which is what keeps one process's series from growing with every session it serves.
pub fn metered(
  agent : &@moonacp.Agent,
  exporter : @otlp.MetricsExporter,
  options~ : Options = options,
) -> &@moonacp.Agent {
  Metered::{
    inner: agent,
    exporter,
    agent_name: options.agent_name,
    turns: Seconds::new(),
  }
}

///|
/// Records a turn that ended, either way.
fn Metered::timed(self : Metered, started : Int64) -> Unit {
  let ended = now()
  self.turns.observe(seconds_between(started, ended), ended)
  let attributes : Array[(String, @trace.Value)] = [
    (
      @semconv.gen_ai_operation_name,
      @trace.Str(operation_of(@semconv.gen_ai_invoke_agent_internal)),
    ),
  ]
  if self.agent_name != "" {
    attributes.push((@semconv.gen_ai_agent_name, @trace.Str(self.agent_name)))
  }
  self.exporter.record(
    histogram(
      @semconv.gen_ai_invoke_agent_duration,
      turn_description,
      self.turns.point(attributes),
    ),
  )
}

///|
impl @moonacp.Agent for Metered with fn initialize(self, request) {
  let answer = self.inner.initialize(request)
  // The version is not an attribute of this metric, and the conversation is not either: only the
  // agent's name is, which is what keeps one process's series from growing with every session.
  match answer.agent_info {
    Some(info) => self.agent_name = info.name
    None => ()
  }
  answer
}

///|
impl @moonacp.Agent for Metered with fn authenticate(self, request) {
  self.inner.authenticate(request)
}

///|
impl @moonacp.Agent for Metered with fn logout(self) {
  self.inner.logout()
}

///|
impl @moonacp.Agent for Metered with fn new_session(self, request) {
  self.inner.new_session(request)
}

///|
impl @moonacp.Agent for Metered with fn load_session(self, request, session) {
  self.inner.load_session(request, session)
}

///|
impl @moonacp.Agent for Metered with fn resume_session(self, request, session) {
  self.inner.resume_session(request, session)
}

///|
impl @moonacp.Agent for Metered with fn list_sessions(self, request) {
  self.inner.list_sessions(request)
}

///|
impl @moonacp.Agent for Metered with fn delete_session(self, request) {
  self.inner.delete_session(request)
}

///|
impl @moonacp.Agent for Metered with fn close_session(self, request) {
  self.inner.close_session(request)
}

///|
impl @moonacp.Agent for Metered with fn set_mode(self, request) {
  self.inner.set_mode(request)
}

///|
impl @moonacp.Agent for Metered with fn set_config_option(self, request) {
  self.inner.set_config_option(request)
}

///|
impl @moonacp.Agent for Metered with fn prompt(self, request, session) {
  let started = now()
  let outcome = Ok(self.inner.prompt(request, session)) catch {
    error => Err(error)
  }
  self.timed(started)
  match outcome {
    Ok(reason) => reason
    Err(error) => raise error
  }
}

///|
impl @moonacp.Agent for Metered with fn cancel(self, id) {
  self.inner.cancel(id)
}

// The editor's side: one observation of `gen_ai.execute_tool.duration` per request answered.
//
// The conventions give this metric the tool's name and the agent's, and no operation name: the
// operation is the metric itself.

///|
/// A client that records how long each request took to answer and answers everything else itself.
priv struct MeteredClient {
  inner : &@moonacp.Client
  exporter : @otlp.MetricsExporter
  settings : Options
  tools : Seconds
}

///|
/// Wraps a client so that every file and terminal request the agent makes is one observation of
/// `gen_ai.execute_tool.duration`, handed to `exporter`. The editor holds no answer to `initialize`,
/// so the agent's name comes from `options`.
pub fn metered_client(
  client : &@moonacp.Client,
  exporter : @otlp.MetricsExporter,
  options~ : Options = options,
) -> &@moonacp.Client {
  MeteredClient::{
    inner: client,
    exporter,
    settings: options,
    tools: Seconds::new(),
  }
}

///|
/// Records one answered request, whatever the answer was.
fn MeteredClient::timed(
  self : MeteredClient,
  tool : String,
  started : Int64,
) -> Unit {
  let ended = now()
  self.tools.observe(seconds_between(started, ended), ended)
  let attributes : Array[(String, @trace.Value)] = [
    (@semconv.gen_ai_tool_name, @trace.Str(tool)),
  ]
  if self.settings.agent_name != "" {
    attributes.push(
      (@semconv.gen_ai_agent_name, @trace.Str(self.settings.agent_name)),
    )
  }
  self.exporter.record(
    histogram(
      @semconv.gen_ai_execute_tool_duration,
      tool_description,
      self.tools.point(attributes),
    ),
  )
}

///|
impl @moonacp.Client for MeteredClient with fn update(self, id, update) {
  self.inner.update(id, update)
}

///|
impl @moonacp.Client for MeteredClient with fn request_permission(self, ask) {
  self.inner.request_permission(ask)
}

///|
impl @moonacp.Client for MeteredClient with fn read_text_file(self, request) {
  let started = now()
  let outcome = Ok(self.inner.read_text_file(request)) catch {
    error => Err(error)
  }
  self.timed("fs/read_text_file", started)
  match outcome {
    Ok(text) => text
    Err(error) => raise error
  }
}

///|
impl @moonacp.Client for MeteredClient with fn write_text_file(self, request) {
  let started = now()
  let outcome = Ok(self.inner.write_text_file(request)) catch {
    error => Err(error)
  }
  self.timed("fs/write_text_file", started)
  match outcome {
    Ok(_) => ()
    Err(error) => raise error
  }
}

///|
impl @moonacp.Client for MeteredClient with fn create_terminal(self, request) {
  let started = now()
  let outcome = Ok(self.inner.create_terminal(request)) catch {
    error => Err(error)
  }
  self.timed("terminal/create", started)
  match outcome {
    Ok(id) => id
    Err(error) => raise error
  }
}

///|
impl @moonacp.Client for MeteredClient with fn terminal_output(self, request) {
  let started = now()
  let outcome = Ok(self.inner.terminal_output(request)) catch {
    error => Err(error)
  }
  self.timed("terminal/output", started)
  match outcome {
    Ok(output) => output
    Err(error) => raise error
  }
}

///|
impl @moonacp.Client for MeteredClient with fn wait_for_terminal_exit(
  self,
  request,
) {
  let started = now()
  let outcome = Ok(self.inner.wait_for_terminal_exit(request)) catch {
    error => Err(error)
  }
  self.timed("terminal/wait_for_exit", started)
  match outcome {
    Ok(status) => status
    Err(error) => raise error
  }
}

///|
impl @moonacp.Client for MeteredClient with fn kill_terminal(self, request) {
  let started = now()
  let outcome = Ok(self.inner.kill_terminal(request)) catch {
    error => Err(error)
  }
  self.timed("terminal/kill", started)
  match outcome {
    Ok(_) => ()
    Err(error) => raise error
  }
}

///|
impl @moonacp.Client for MeteredClient with fn release_terminal(self, request) {
  let started = now()
  let outcome = Ok(self.inner.release_terminal(request)) catch {
    error => Err(error)
  }
  self.timed("terminal/release", started)
  match outcome {
    Ok(_) => ()
    Err(error) => raise error
  }
}

///|
impl @moonacp.Client for MeteredClient with fn elicit(self, ask) {
  self.inner.elicit(ask)
}
