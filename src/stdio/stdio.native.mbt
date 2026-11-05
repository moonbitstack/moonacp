// Serving an agent on stdin and stdout, and launching one as a child process.

///|
/// Runs an agent on the process's own stdin and stdout until the client closes stdin. This is the
/// transport an editor uses when it launches an agent: one JSON-RPC message per line, nothing else
/// on stdout, diagnostics on stderr.
pub async fn serve_stdio(agent : &@moonacp.Agent) -> Unit {
  // The process's own two streams: an editor launches an agent and talks to it here.
  let frames = @peer.lines(@stdio.stdin, @stdio.stdout)
  let peer = @moonacp.serve(agent, frames)
  peer.run()
}

///|
/// A child process speaking the protocol on its pipes.
pub struct Child {
  ///
  /// The connection to the child.
  conn : @moonacp.Conn
  /// The child's process id, for a caller that wants to wait on it.
  pid : Int32
  to_child : @process.WriteToProcess
}

///|
/// Starts `command` with `args` and connects to it as a client. The command is an absolute path or
/// something the system can find on `PATH`; the first array element is the program.
pub async fn spawn(
  client : &@moonacp.Client,
  command : Array[String],
  args? : Array[String],
  env? : Map[String, String],
  cwd? : StringView,
) -> Child {
  guard command.length() > 0 else { abort("spawn: no program given") }
  // The first element is the program, the rest are its arguments unless the caller named them.
  let rest = match args {
    Some(args) => args
    None => {
      let out = []
      for index in 1..<command.length() {
        out.push(command[index])
      }
      out
    }
  }
  let (child_stdin, to_child) = @process.write_to_process()
  let (from_child, child_stdout) = @process.read_from_process()
  // `cwd` is only passed when the caller named one: an empty path is not a directory.
  let pid = match cwd {
    Some(cwd) =>
      @process.spawn_orphan(
        command[0],
        rest,
        stdin=child_stdin,
        stdout=child_stdout,
        extra_env=env.unwrap_or(Map([])),
        cwd~,
      )
    None =>
      @process.spawn_orphan(
        command[0],
        rest,
        stdin=child_stdin,
        stdout=child_stdout,
        extra_env=env.unwrap_or(Map([])),
      )
  }
  let frames = @peer.lines(from_child, to_child)
  { conn: @moonacp.connect(client, frames), pid, to_child, }
}

///|
/// The connection to the child, runnable and callable.
pub fn Child::conn(self : Child) -> @moonacp.Conn {
  self.conn
}

///|
/// Closes the child's input, which is how an agent learns the client is done: it finishes what it
/// is doing and exits. The read side ends with it, so a task blocked on `run` comes back.
pub fn Child::close(self : Child) -> Unit {
  self.to_child.close()
}
