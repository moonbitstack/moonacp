// Talks to an agent across the network: `moon run src/examples/05-remote --target native --
// <url>`, where the URL is the endpoint itself, such as `http://127.0.0.1:8080/acp`. It prints what
// came back, so a mismatch with what the agent said it would answer is visible in the log.

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
async fn main {
  let argv = @env.args()
  guard argv.length() > 1 else {
    println("usage: 05-remote <url>")
    return
  }
  let printer = Printer::{ text: "", }
  let remote = @remote.open(printer, argv[1]) catch {
    _ => {
      println("cannot open the connection")
      return
    }
  }
  let conn = remote.conn()
  @async.with_task_group(async fn(group) {
    group.spawn_bg(async fn() { remote.run() })
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
    // Ends the exchange: the server drops the connection and the reading task returns.
    remote.close()
  })
}
