// The agent's side of the wire: one handler per method, and the turn that `session/cancel` stops.

///|
/// Holds the task a turn runs in, so `session/cancel` can stop it. A `mut` field makes this a
/// reference, so every copy of a `Session` sees the same slot.
priv struct Slot {
  mut task : @async.Task[StopReason?]?
}

///|
/// What running turns can be stopped by, keyed by session. A cancel that arrives before the turn has
/// a task of its own is remembered, so the turn stops as soon as it starts.
priv struct Turns {
  running : Map[String, Slot]
  pending : Map[String, Bool]
}

///|
fn Turns::new() -> Turns {
  { running: Map([]), pending: Map([]), }
}

///|
fn Turns::open(self : Turns, session_id : String) -> Slot {
  let slot = Slot::{ task: None, }
  self.running[session_id] = slot
  slot
}

///|
fn Turns::close(self : Turns, session_id : String) -> Unit {
  self.running.remove(session_id)
  self.pending.remove(session_id)
}

///|
/// Stops the turn running in a session, if there is one. Called from the read loop, so it must not
/// wait for the turn to finish.
fn Turns::stop(self : Turns, session_id : String) -> Unit {
  match self.running.get(session_id) {
    Some(slot) =>
      match slot.task {
        Some(task) => task.cancel()
        None => self.pending[session_id] = true
      }
    None => self.pending[session_id] = true
  }
}

///|
/// Whether a cancel arrived before the turn got going.
fn Turns::take_pending(self : Turns, session_id : String) -> Bool {
  match self.pending.get(session_id) {
    Some(_) => {
      self.pending.remove(session_id)
      true
    }
    None => false
  }
}

///|
/// Reads a call's parameters, reporting the decoder's reason as -32602.
fn[P : @json.FromJson] params_of(params : Json?) -> P raise @moonjrpc.Failed {
  @json.from_json(params.unwrap_or(Json::null())) catch {
    @json.JsonDecodeError((path, reason)) =>
      raise @moonjrpc.Failed({
        code: invalid_params,
        message: "Invalid params",
        data: Some(Json::string("\{path}: \{reason}")),
      })
  }
}

///|
/// Registers a call: parameters decoded, failures turned into error objects, the answer written.
fn[P : @json.FromJson, R : ToJson] on_call(
  methods : @moonjrpc.Methods,
  name : String,
  run : async (P) -> R,
) -> Unit {
  methods.call(name, async fn(params) {
    let input : P = params_of(params)
    let output = run(input) catch {
      error => raise @moonjrpc.Failed(failure_of(error))
    }
    write(output)
  })
}

///|
/// Registers a notice. A notice is never answered, and its failures have nobody to go to, so they
/// are dropped rather than allowed to end the connection.
fn[P : @json.FromJson] on_notice(
  methods : @moonjrpc.Methods,
  name : String,
  run : async (P) -> Unit,
) -> Unit {
  methods.notice(name, async fn(params) {
    let input : P = params_of(params) catch { _ => return }
    run(input) catch {
      _ => ()
    }
  })
}

///|
/// Runs one turn so that `session/cancel` can stop it: the turn gets its own task, and the slot is
/// where the cancel handler finds it.
async fn run_turn(
  agent : &Agent,
  request : Prompt,
  session : Session,
  turns : Turns,
) -> StopReason {
  let slot = turns.open(request.session_id)
  let outcome = @async.with_task_group(async fn(group) {
    let task = group.spawn(async fn() {
      @async.handle_cancellation(async fn() { agent.prompt(request, session) })
    })
    slot.task = Some(task)
    if turns.take_pending(request.session_id) {
      task.cancel()
    }
    task.wait()
  })
  match outcome {
    Some(reason) => reason
    None => StopReason::Cancelled
  }
}

///|
/// Serves an agent over any transport: the caller runs the returned peer. Messages are answered in
/// the order they arrive, and batches are refused, because the protocol has none.
pub fn serve(agent : &Agent, frames : &@peer.Frames) -> @peer.Peer {
  let methods = @moonjrpc.Methods::new()
  let peer = @peer.Peer::new(frames, methods~, timeout_ms=None, batch=false)
  register(agent, peer, methods)
  peer
}

///|
fn register(
  agent : &Agent,
  peer : @peer.Peer,
  methods : @moonjrpc.Methods,
) -> Unit {
  let turns = Turns::new()
  on_call(methods, "initialize", async fn(request : Initialize) {
    agent.initialize(request)
  })
  on_call(methods, "authenticate", async fn(request : Authenticate) {
    agent.authenticate(request)
    Json::empty_object()
  })
  on_call(methods, "logout", async fn(_ : Json) {
    agent.logout()
    Json::empty_object()
  })
  on_call(methods, "session/new", async fn(request : NewSession) {
    agent.new_session(request)
  })
  on_call(methods, "session/load", async fn(request : LoadSession) {
    let session = Session::{ peer, id: request.session_id, }
    agent.load_session(request, session)
  })
  on_call(methods, "session/resume", async fn(request : ResumeSession) {
    let session = Session::{ peer, id: request.session_id, }
    agent.resume_session(request, session)
  })
  on_call(methods, "session/list", async fn(request : ListSessions) {
    agent.list_sessions(request)
  })
  on_call(methods, "session/delete", async fn(request : DeleteSession) {
    agent.delete_session(request)
    Json::empty_object()
  })
  on_call(methods, "session/close", async fn(request : CloseSession) {
    agent.close_session(request)
    Json::empty_object()
  })
  on_call(methods, "session/set_mode", async fn(request : SetMode) {
    agent.set_mode(request)
    Json::empty_object()
  })
  on_call(methods, "session/set_config_option", async fn(
    request : SetConfigOption,
  ) {
    let options = agent.set_config_option(request)
    json_of([("configOptions", Some(Json::array(options.map(write))))])
  })
  methods.call("session/prompt", async fn(params) {
    let request : Prompt = params_of(params)
    let session = Session::{ peer, id: request.session_id, }
    defer turns.close(request.session_id)
    let reason = run_turn(agent, request, session, turns) catch {
      error => raise @moonjrpc.Failed(failure_of(error))
    }
    write(PromptResult::{ stop_reason: reason, meta: None, })
  })
  on_notice(methods, "session/cancel", async fn(request : Cancel) {
    turns.stop(request.session_id)
    agent.cancel(request.session_id)
  })
}
