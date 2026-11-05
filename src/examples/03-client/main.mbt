// Drives whatever agent the command line names: initialize, one session, one turn, and a second
// turn that is cancelled. Prints what came back, so a mismatch is visible in the log.

///|
struct Printer {
  mut text : String
}

///|
impl @moonacp.Client for Printer with fn update(self, id, update) {
  ignore(id)
  match update {
    @moonacp.SessionUpdate::AgentMessageChunk(chunk) =>
      if chunk.content is @moonacp.ContentBlock::Text(content) {
        self.text = self.text + content.text
      }
    @moonacp.SessionUpdate::ToolCall(call) => println("[tool] " + call.title)
    _ => ()
  }
}

///|
impl @moonacp.Client for Printer with fn request_permission(self, ask) {
  ignore(self)
  match ask.options {
    [] => @moonacp.Outcome::Cancelled
    [first, ..] => @moonacp.Outcome::Selected(first.option_id)
  }
}

///|
impl @moonacp.Client for Printer with fn read_text_file(self, request) {
  ignore(self)
  "read of \{request.path}"
}

///|
impl @moonacp.Client for Printer with fn write_text_file(self, request) {
  ignore(self)
  ignore(request)
}

///|
async fn main {
  let argv = @env.args()
  guard argv.length() > 1 else {
    println("usage: 03-client <agent command> [args...]")
    return
  }
  let command = []
  for index in 1..<argv.length() {
    command.push(argv[index])
  }
  let printer = Printer::{ text: "", }
  let child = @stdio.spawn(printer, command) catch {
    _ => {
      println("cannot start the agent")
      return
    }
  }
  let conn = child.conn()
  @async.with_task_group(async fn(group) {
    group.spawn_bg(async fn() { conn.run() })
    let started = conn.initialize({
      protocol_version: @moonacp.protocol_version,
      client_capabilities: @moonacp.ClientCapabilities::none(),
      client_info: Some(@moonacp.Implementation::new("moonacp-client", "0.1.0")),
      meta: None,
    }) catch {
      error => {
        println("cannot initialize: " + @moonacp.failure_of(error).message)
        return
      }
    }
    println(
      "agent: \{started.agent_info.map(info => info.name).unwrap_or("unnamed")}",
    )
    let session = conn.new_session({
      cwd: ".",
      additional_directories: None,
      mcp_servers: [],
      meta: None,
    }) catch {
      error => {
        println("cannot open a session: " + @moonacp.failure_of(error).message)
        return
      }
    }
    println("session: \{session.session_id}")
    let answer = conn.prompt({
      session_id: session.session_id,
      prompt: [
        @moonacp.ContentBlock::Text({
          text: "hello from a MoonBit client",
          annotations: None,
          meta: None,
        }),
      ],
      meta: None,
    }) catch {
      error => {
        println("the turn failed: " + @moonacp.failure_of(error).message)
        return
      }
    }
    println("stop: \{answer.stop_reason.to_string()}")
    println("answer: \{printer.text}")
    // A second turn, cancelled while it runs.
    let pending = group.spawn(async fn() {
      conn.prompt({
        session_id: session.session_id,
        prompt: [
          @moonacp.ContentBlock::Text({
            text: "think",
            annotations: None,
            meta: None,
          }),
        ],
        meta: None,
      })
    })
    conn.cancel(session.session_id) catch {
      _ => ()
    }
    let cancelled = pending.wait() catch {
      _ => { stop_reason: @moonacp.StopReason::Cancelled, meta: None, }
    }
    println("cancel: \{cancelled.stop_reason.to_string()}")
  })
}
