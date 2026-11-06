// A minimal MCP client for the stdio transport.
//
// The protocol only carries the servers' configuration; connecting to them is the agent's own
// business. This is what that business looks like: spawn the server, complete the handshake, ask
// what it can do, and close its input when the session ends.

///|
/// One connected MCP server, spoken to over its pipes.
struct McpClient {
  name : String
  frames : &@peer.Frames
  to_server : @process.WriteToProcess
  mut next_id : Int32
  mut tools : Array[String]
}

///|
/// A JSON object from its entries, in order.
fn object_of(entries : Array[(String, Json)]) -> Json {
  let fields : Map[String, Json] = Map([])
  for entry in entries {
    let (key, value) = entry
    fields[key] = value
  }
  Json::object(fields)
}

///|
/// The client's name and version, as every MCP server wants to know them.
fn client_info() -> Json {
  object_of([
    ("name", Json::string("moonacp-notes")),
    ("version", Json::string("0.1.0")),
  ])
}

///|
/// Starts a server and completes the MCP handshake. `None` means the server could not be reached or
/// did not answer: an agent carries on without it rather than failing the session.
async fn McpClient::connect(server : @moonacp.McpStdio) -> McpClient? noraise {
  open_server(server) catch {
    _ => None
  }
}

///|
/// The part that can fail: spawning, and the handshake that may never come back.
async fn open_server(server : @moonacp.McpStdio) -> McpClient? {
  let (child_stdin, to_server) = @process.write_to_process()
  let (from_server, child_stdout) = @process.read_from_process()
  let env : Map[String, String] = Map([])
  for variable in server.env {
    env[variable.name] = variable.value
  }
  ignore(
    @process.spawn_orphan(
      server.command,
      server.args,
      stdin=child_stdin,
      stdout=child_stdout,
      extra_env=env,
    ),
  )
  let client = {
    name: server.name,
    frames: @peer.lines(from_server, to_server),
    to_server,
    next_id: 0,
    tools: [],
  }
  // The handshake is bounded: a server that never answers must not hold `session/new` open.
  let greeted = @async.with_timeout_opt(5000, () => client.greet()) catch {
    _ => None
  }
  match greeted {
    Some(true) => Some(client)
    _ => {
      client.close()
      None
    }
  }
}

///|
/// The handshake: `initialize`, then the notice that says the client is ready.
async fn McpClient::greet(self : McpClient) -> Bool {
  let answer = self.request(
    "initialize",
    object_of([
      ("protocolVersion", Json::string("2025-06-18")),
      ("capabilities", object_of([])),
      ("clientInfo", client_info()),
    ]),
  )
  match answer {
    None => false
    Some(answer) => {
      ignore(answer)
      self.notify("notifications/initialized", object_of([]))
      // What the server offers is worth knowing before a turn uses it.
      self.tools = self.list_tools()
      true
    }
  }
}

///|
/// Asks what the server can do. A server that does not answer leaves the list empty.
async fn McpClient::list_tools(self : McpClient) -> Array[String] {
  let names : Array[String] = []
  let answer = match self.request("tools/list", object_of([])) {
    Some(answer) => answer
    None => return names
  }
  guard answer is Object(fields) else { return names }
  guard fields.get("tools") is Some(Array(tools)) else { return names }
  for tool in tools {
    if tool is Object(entry) {
      if entry.get("name") is Some(String(name)) {
        names.push(name)
      }
    }
  }
  names
}

///|
/// One request, and the answer that carries its id. Anything else the server sends while waiting —
/// notifications, or a request this client does not serve — is dropped.
async fn McpClient::request(
  self : McpClient,
  name : String,
  params : Json,
) -> Json? {
  let id = self.next_id
  self.next_id = self.next_id + 1
  self.frames.write(
    object_of([
      ("jsonrpc", Json::string("2.0")),
      ("id", Json::number(id.to_double())),
      ("method", Json::string(name)),
      ("params", params),
    ]).stringify(),
  ) catch {
    _ => return None
  }
  let mut answer = None
  let mut waiting = true
  while waiting {
    let line = match self.frames.read() {
      Some(line) => line
      None => {
        // The server went away, or the pipe broke: nothing more is coming.
        waiting = false
        continue
      }
    }
    let json = @json.parse(line) catch { _ => continue }
    guard json is Object(fields) else { continue }
    guard fields.get("id") is Some(Number(seen, ..)) else { continue }
    if seen != id.to_double() {
      continue
    }
    answer = fields.get("result")
    waiting = false
  }
  answer
}

///|
/// One notice: no id, and nothing comes back.
async fn McpClient::notify(
  self : McpClient,
  name : String,
  params : Json,
) -> Unit {
  ignore(
    self.frames.write(
      object_of([
        ("jsonrpc", Json::string("2.0")),
        ("method", Json::string(name)),
        ("params", params),
      ]).stringify(),
    ) catch {
      _ => ()
    },
  )
}

///|
/// Ends the server: closing its input is how an MCP server learns the client is gone, and how it
/// exits on its own.
fn McpClient::close(self : McpClient) -> Unit {
  self.to_server.close()
}

///|
/// A line for the answer that names the tools the session's servers offer, if any.
fn tools_line(servers : Array[McpClient]) -> String {
  let parts : Array[String] = []
  for server in servers {
    if server.tools.is_empty() {
      continue
    }
    parts.push(
      "\{server.tools.length()} tool(s) from \{server.name}: \{server.tools.join(", ")}",
    )
  }
  if parts.is_empty() {
    ""
  } else {
    "\nMCP: " + parts.join("; ") + "."
  }
}
