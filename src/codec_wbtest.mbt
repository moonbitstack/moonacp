// Every type survives a trip through the wire: encode, read back, and the value is the one that went
// in. The literal shapes are checked where a wrong key would still round-trip — the names are the
// protocol, so they are worth asserting once each.

///|
fn[A : @json.ToJson + @json.FromJson + Eq] round_trip(
  value : A,
  json : String,
) -> Unit raise {
  let encoded = @json.ToJson::to_json(value)
  let expected = @json.parse(json)
  assert_eq(canonical(encoded).stringify(), canonical(expected).stringify())
  let back : A = @json.from_json(expected)
  assert_true(back == value)
}

///|
/// Objects compared by content, not by the order the members happen to be written in.
fn canonical(json : Json) -> Json {
  match json {
    Object(fields) => {
      let keys = []
      for entry in fields.iter() {
        keys.push(entry.0)
      }
      keys.sort()
      let out : Map[String, Json] = Map([])
      for key in keys {
        out[key] = match fields.get(key) {
          Some(value) => canonical(value)
          None => Json::null()
        }
      }
      Json::object(out)
    }
    Array(items) => Json::array(items.map(canonical))
    other => other
  }
}

///|
test "the content blocks" {
  round_trip(
    ContentBlock::Text({ text: "hi", annotations: None, meta: None, }),
    "{\"text\":\"hi\",\"type\":\"text\"}",
  )
  round_trip(
    ContentBlock::Image({
      data: "AA==",
      mime_type: "image/png",
      uri: None,
      annotations: None,
      meta: None,
    }),
    "{\"data\":\"AA==\",\"mimeType\":\"image/png\",\"type\":\"image\"}",
  )
  round_trip(
    ContentBlock::Audio({
      data: "AA==",
      mime_type: "audio/wav",
      annotations: None,
      meta: None,
    }),
    "{\"data\":\"AA==\",\"mimeType\":\"audio/wav\",\"type\":\"audio\"}",
  )
  round_trip(
    ContentBlock::ResourceLink({
      uri: "file:///a",
      name: "a",
      title: None,
      description: None,
      mime_type: None,
      size: Some(12L),
      annotations: None,
      meta: None,
    }),
    "{\"name\":\"a\",\"size\":12,\"type\":\"resource_link\",\"uri\":\"file:///a\"}",
  )
  round_trip(
    ContentBlock::Resource({
      resource: Resource::Text({
        uri: "file:///a",
        text: "x",
        mime_type: None,
        meta: None,
      }),
      annotations: None,
      meta: None,
    }),
    "{\"resource\":{\"text\":\"x\",\"uri\":\"file:///a\"},\"type\":\"resource\"}",
  )
  round_trip(
    ContentBlock::Resource({
      resource: Resource::Blob({
        uri: "file:///a",
        blob: "AA==",
        mime_type: Some("application/pdf"),
        meta: None,
      }),
      annotations: Some({
        audience: Some([Role::User]),
        last_modified: None,
        priority: Some(0.5),
        meta: None,
      }),
      meta: None,
    }),
    "{\"resource\":{\"blob\":\"AA==\",\"mimeType\":\"application/pdf\",\"uri\":\"file:///a\"},\"annotations\":{\"audience\":[\"user\"],\"priority\":0.5},\"type\":\"resource\"}",
  )
}

///|
test "the tool call shapes" {
  round_trip(
    ToolCallContent::Diff({
      path: "/a",
      new_text: "b",
      old_text: Some("a"),
      meta: None,
    }),
    "{\"newText\":\"b\",\"oldText\":\"a\",\"path\":\"/a\",\"type\":\"diff\"}",
  )
  round_trip(
    ToolCallContent::Terminal(TerminalRef::new("t-1")),
    "{\"terminalId\":\"t-1\",\"type\":\"terminal\"}",
  )
  round_trip(
    ToolCallContent::Content({
      content: ContentBlock::Text({
        text: "done",
        annotations: None,
        meta: None,
      }),
      meta: None,
    }),
    "{\"content\":{\"text\":\"done\",\"type\":\"text\"},\"type\":\"content\"}",
  )
  round_trip(
    ToolCall::{
      tool_call_id: "c-1",
      title: "read",
      name: Some("read_file"),
      kind: Some(ToolKind::Read),
      status: Some(ToolCallStatus::InProgress),
      content: None,
      locations: Some([{ path: "/a", line: Some(3L), meta: None, }]),
      raw_input: Some(@json.parse("{\"p\":1}")),
      raw_output: None,
      meta: None,
    },
    "{\"toolCallId\":\"c-1\",\"title\":\"read\",\"name\":\"read_file\",\"kind\":\"read\",\"status\":\"in_progress\",\"locations\":[{\"path\":\"/a\",\"line\":3}],\"rawInput\":{\"p\":1}}",
  )
  round_trip(
    ToolCallUpdate::{
      tool_call_id: "c-1",
      kind: None,
      status: Some(ToolCallStatus::Completed),
      title: None,
      name: None,
      content: None,
      locations: None,
      raw_input: None,
      raw_output: None,
      meta: None,
    },
    "{\"toolCallId\":\"c-1\",\"status\":\"completed\"}",
  )
}

///|
test "permission asks and answers" {
  round_trip(
    Permission::{
      tool_call: {
        tool_call_id: "c-1",
        kind: None,
        status: None,
        title: Some("write"),
        name: None,
        content: None,
        locations: None,
        raw_input: None,
        raw_output: None,
        meta: None,
      },
      options: [
        {
          option_id: "allow",
          name: "Allow",
          kind: PermissionOptionKind::AllowOnce,
          meta: None,
        },
        {
          option_id: "no",
          name: "No",
          kind: PermissionOptionKind::RejectAlways,
          meta: None,
        },
      ],
      meta: None,
    },
    "{\"toolCall\":{\"toolCallId\":\"c-1\",\"title\":\"write\"},\"options\":[{\"optionId\":\"allow\",\"name\":\"Allow\",\"kind\":\"allow_once\"},{\"optionId\":\"no\",\"name\":\"No\",\"kind\":\"reject_always\"}]}",
  )
  round_trip(
    Outcome::Selected("allow"),
    "{\"optionId\":\"allow\",\"outcome\":\"selected\"}",
  )
  round_trip(Outcome::Cancelled, "{\"outcome\":\"cancelled\"}")
}

///|
test "the session updates" {
  round_trip(
    SessionUpdate::AgentMessageChunk({
      content: ContentBlock::Text({ text: "hi", annotations: None, meta: None, }),
      message_id: Some("m-1"),
      meta: None,
    }),
    "{\"content\":{\"text\":\"hi\",\"type\":\"text\"},\"messageId\":\"m-1\",\"sessionUpdate\":\"agent_message_chunk\"}",
  )
  round_trip(
    SessionUpdate::Plan({
      entries: [
        {
          content: "read",
          priority: PlanEntryPriority::High,
          status: PlanEntryStatus::Pending,
          meta: None,
        },
      ],
      meta: None,
    }),
    "{\"entries\":[{\"content\":\"read\",\"priority\":\"high\",\"status\":\"pending\"}],\"sessionUpdate\":\"plan\"}",
  )
  round_trip(
    SessionUpdate::AvailableCommands({
      available_commands: [
        {
          name: "help",
          description: "Show help",
          input: Some({ hint: "topic", meta: None, }),
          meta: None,
        },
      ],
      meta: None,
    }),
    "{\"availableCommands\":[{\"name\":\"help\",\"description\":\"Show help\",\"input\":{\"hint\":\"topic\"}}],\"sessionUpdate\":\"available_commands_update\"}",
  )
  round_trip(
    SessionUpdate::ModeChanged({ current_mode_id: "edit", meta: None, }),
    "{\"currentModeId\":\"edit\",\"sessionUpdate\":\"current_mode_update\"}",
  )
  round_trip(
    SessionUpdate::SessionInfoChanged({
      title: Some("T"),
      updated_at: None,
      meta: None,
    }),
    "{\"title\":\"T\",\"sessionUpdate\":\"session_info_update\"}",
  )
  round_trip(
    SessionUpdate::Usage({
      used: 10L,
      size: 100L,
      cost: Some({ amount: 0.25, currency: "USD", meta: None, }),
      meta: None,
    }),
    "{\"used\":10,\"size\":100,\"cost\":{\"amount\":0.25,\"currency\":\"USD\"},\"sessionUpdate\":\"usage_update\"}",
  )
  round_trip(
    SessionUpdate::Notice({
      severity: Severity::Warning,
      title: "Careful",
      description: None,
      meta: None,
    }),
    "{\"severity\":\"warning\",\"title\":\"Careful\",\"sessionUpdate\":\"notice\"}",
  )
  round_trip(
    SessionUpdate::Compaction({
      compaction_id: "k-1",
      status: CompactionStatus::InProgress,
      summary: None,
      error: None,
      meta: None,
    }),
    "{\"compactionId\":\"k-1\",\"status\":\"in_progress\",\"sessionUpdate\":\"compaction_update\"}",
  )
  round_trip(
    SessionUpdate::CompactionSummary({
      compaction_id: "k-1",
      content: ContentBlock::Text({
        text: "so far",
        annotations: None,
        meta: None,
      }),
      meta: None,
    }),
    "{\"compactionId\":\"k-1\",\"content\":{\"text\":\"so far\",\"type\":\"text\"},\"sessionUpdate\":\"compaction_summary_chunk\"}",
  )
}

///|
test "modes and configuration options" {
  round_trip(
    SessionModes::{
      current_mode_id: "ask",
      available_modes: [
        { id: "ask", name: "Ask", description: None, meta: None, },
      ],
      meta: None,
    },
    "{\"currentModeId\":\"ask\",\"availableModes\":[{\"id\":\"ask\",\"name\":\"Ask\"}]}",
  )
  round_trip(
    ConfigOption::{
      id: "model",
      name: "Model",
      description: None,
      category: Some(ConfigCategory::Model),
      value: ConfigValue::Select(
        "fast",
        ConfigChoices::Flat([
          { value: "fast", name: "Fast", description: None, meta: None, },
        ]),
      ),
      meta: None,
    },
    "{\"id\":\"model\",\"name\":\"Model\",\"category\":\"model\",\"type\":\"select\",\"currentValue\":\"fast\",\"options\":[{\"value\":\"fast\",\"name\":\"Fast\"}]}",
  )
  round_trip(
    ConfigOption::{
      id: "stream",
      name: "Stream",
      description: None,
      category: None,
      value: ConfigValue::Boolean(true),
      meta: None,
    },
    "{\"id\":\"stream\",\"name\":\"Stream\",\"type\":\"boolean\",\"currentValue\":true}",
  )
  round_trip(
    ConfigOption::{
      id: "model",
      name: "Model",
      description: None,
      category: None,
      value: ConfigValue::Select(
        "b",
        ConfigChoices::Grouped([
          {
            group: "g",
            name: "G",
            options: [{ value: "b", name: "B", description: None, meta: None, }],
            meta: None,
          },
        ]),
      ),
      meta: None,
    },
    "{\"id\":\"model\",\"name\":\"Model\",\"type\":\"select\",\"currentValue\":\"b\",\"options\":[{\"group\":\"g\",\"name\":\"G\",\"options\":[{\"value\":\"b\",\"name\":\"B\"}]}]}",
  )
}

///|
test "session setup and the answers to it" {
  round_trip(
    SessionStarted::{
      session_id: "s-1",
      modes: None,
      config_options: None,
      meta: None,
    },
    "{\"sessionId\":\"s-1\"}",
  )
  round_trip(
    NewSession::{
      cwd: "/work",
      additional_directories: Some(["/tmp"]),
      mcp_servers: [
        McpServer::Stdio({
          name: "n",
          command: "/bin/cat",
          args: [],
          env: [],
          meta: None,
        }),
        McpServer::Http({
          name: "h",
          url: "https://example.test/mcp",
          headers: [{ name: "x", value: "y", meta: None, }],
          meta: None,
        }),
        McpServer::Sse({
          name: "s",
          url: "https://example.test/sse",
          headers: [],
          meta: None,
        }),
      ],
      meta: None,
    },
    "{\"cwd\":\"/work\",\"additionalDirectories\":[\"/tmp\"],\"mcpServers\":[{\"name\":\"n\",\"command\":\"/bin/cat\",\"args\":[],\"env\":[]},{\"name\":\"h\",\"url\":\"https://example.test/mcp\",\"headers\":[{\"name\":\"x\",\"value\":\"y\"}],\"type\":\"http\"},{\"name\":\"s\",\"url\":\"https://example.test/sse\",\"headers\":[],\"type\":\"sse\"}]}",
  )
  round_trip(
    SessionInfo::{
      session_id: "s-1",
      cwd: "/work",
      additional_directories: None,
      title: Some("T"),
      updated_at: None,
      meta: None,
    },
    "{\"sessionId\":\"s-1\",\"cwd\":\"/work\",\"title\":\"T\"}",
  )
  round_trip(
    SessionList::{ sessions: [], next_cursor: Some("c-2"), meta: None, },
    "{\"sessions\":[],\"nextCursor\":\"c-2\"}",
  )
  round_trip(
    Prompt::{
      session_id: "s-1",
      prompt: [
        ContentBlock::Text({ text: "hi", annotations: None, meta: None, }),
      ],
      meta: None,
    },
    "{\"sessionId\":\"s-1\",\"prompt\":[{\"text\":\"hi\",\"type\":\"text\"}]}",
  )
  round_trip(
    PromptResult::{ stop_reason: StopReason::EndTurn, meta: None, },
    "{\"stopReason\":\"end_turn\"}",
  )
  round_trip(
    Cancel::{ session_id: "s-1", meta: None, },
    "{\"sessionId\":\"s-1\"}",
  )
}

///|
test "capabilities" {
  round_trip(
    AgentCapabilities::{
      load_session: true,
      prompt: { image: true, audio: false, embedded_context: true, meta: None, },
      mcp: { http: true, sse: false, meta: None, },
      session: {
        list: true,
        delete: false,
        additional_directories: true,
        resume_session: true,
        close: true,
        meta: None,
      },
      auth: Some({ logout: true, meta: None, }),
      meta: None,
    },
    "{\"loadSession\":true,\"promptCapabilities\":{\"image\":true,\"embeddedContext\":true},\"mcpCapabilities\":{\"http\":true},\"sessionCapabilities\":{\"list\":{},\"additionalDirectories\":{},\"resume\":{},\"close\":{}},\"auth\":{\"logout\":{}}}",
  )
  round_trip(
    ClientCapabilities::{
      fs: { read_text_file: true, write_text_file: false, meta: None, },
      terminal: true,
      session: Some({
        compaction: true,
        config_options: true,
        booleans: true,
        notices: true,
        meta: None,
      }),
      auth: Some({ terminal: true, meta: None, }),
      elicitation: Some({ form: true, url: false, meta: None, }),
      meta: None,
    },
    "{\"fs\":{\"readTextFile\":true},\"terminal\":true,\"session\":{\"compaction\":{},\"configOptions\":{\"boolean\":{}},\"notices\":{}},\"auth\":{\"terminal\":true},\"elicitation\":{\"form\":{}}}",
  )
  round_trip(
    Initialized::{
      protocol_version: 1,
      capabilities: AgentCapabilities::none(),
      auth_methods: [
        AuthMethod::Agent({ id: "a", name: "A", description: None, meta: None, }),
        AuthMethod::Terminal({
          id: "t",
          name: "T",
          description: None,
          args: Some(["--login"]),
          env: Some({ "A": "b" }),
          meta: None,
        }),
      ],
      agent_info: Some(Implementation::new("x", "1")),
      meta: None,
    },
    "{\"protocolVersion\":1,\"agentCapabilities\":{\"promptCapabilities\":{},\"mcpCapabilities\":{},\"sessionCapabilities\":{}},\"authMethods\":[{\"id\":\"a\",\"name\":\"A\"},{\"id\":\"t\",\"name\":\"T\",\"args\":[\"--login\"],\"env\":{\"A\":\"b\"},\"type\":\"terminal\"}],\"agentInfo\":{\"name\":\"x\",\"version\":\"1\"}}",
  )
}

///|
test "the client's own requests" {
  round_trip(
    ReadTextFile::{
      session_id: "s",
      path: "/a",
      line: Some(2L),
      limit: None,
      meta: None,
    },
    "{\"sessionId\":\"s\",\"path\":\"/a\",\"line\":2}",
  )
  round_trip(FileText::{ content: "x", meta: None, }, "{\"content\":\"x\"}")
  round_trip(
    WriteTextFile::{ session_id: "s", path: "/a", content: "x", meta: None, },
    "{\"sessionId\":\"s\",\"path\":\"/a\",\"content\":\"x\"}",
  )
  round_trip(
    TerminalCommand::{
      session_id: "s",
      command: "/bin/ls",
      args: Some(["-l"]),
      env: Some([{ name: "A", value: "b", meta: None, }]),
      cwd: None,
      output_byte_limit: Some(1024L),
      meta: None,
    },
    "{\"sessionId\":\"s\",\"command\":\"/bin/ls\",\"args\":[\"-l\"],\"env\":[{\"name\":\"A\",\"value\":\"b\"}],\"outputByteLimit\":1024}",
  )
  round_trip(
    TerminalOpened::{ terminal_id: "t", meta: None, },
    "{\"terminalId\":\"t\"}",
  )
  round_trip(
    TerminalRequest::{ session_id: "s", terminal_id: "t", meta: None, },
    "{\"sessionId\":\"s\",\"terminalId\":\"t\"}",
  )
  round_trip(
    TerminalOutput::{
      output: "x",
      truncated: false,
      exit_status: Some({ exit_code: Some(0L), signal: None, meta: None, }),
      meta: None,
    },
    "{\"output\":\"x\",\"truncated\":false,\"exitStatus\":{\"exitCode\":0}}",
  )
  round_trip(
    ExitStatus::{ exit_code: None, signal: Some("KILL"), meta: None, },
    "{\"signal\":\"KILL\"}",
  )
}

///|
test "elicitation" {
  round_trip(
    Elicitation::Form({
      message: "Pick",
      schema: {
        properties: Map([
          (
            "name",
            Field::Text({
              title: None,
              description: None,
              min_length: Some(1L),
              max_length: None,
              pattern: None,
              format: None,
              default: None,
              choices: None,
              titled_choices: None,
              meta: None,
            }),
          ),
          (
            "count",
            Field::Integer({
              title: None,
              description: None,
              minimum: None,
              maximum: Some(10L),
              default: None,
              meta: None,
            }),
          ),
          (
            "tags",
            Field::MultiSelect({
              title: None,
              description: None,
              min_items: None,
              max_items: None,
              items: ChoiceItems::Values(["a", "b"]),
              default: None,
              meta: None,
            }),
          ),
        ]),
        required: Some(["name"]),
        title: None,
        description: None,
        meta: None,
      },
      scope: ElicitScope::OfSession("s", None),
      meta: None,
    }),
    "{\"mode\":\"form\",\"sessionId\":\"s\",\"message\":\"Pick\",\"requestedSchema\":{\"type\":\"object\",\"properties\":{\"name\":{\"minLength\":1,\"type\":\"string\"},\"count\":{\"maximum\":10,\"type\":\"integer\"},\"tags\":{\"items\":[\"a\",\"b\"],\"type\":\"array\"}},\"required\":[\"name\"]}}",
  )
  round_trip(
    Elicitation::Url({
      message: "Go",
      elicitation_id: "e-1",
      url: "https://example.test",
      scope: ElicitScope::OfRequest(@json.parse("7")),
      meta: None,
    }),
    "{\"mode\":\"url\",\"requestId\":7,\"message\":\"Go\",\"elicitationId\":\"e-1\",\"url\":\"https://example.test\"}",
  )
  round_trip(
    Answer::Accept(Some(Map([("name", Json::string("x"))]))),
    "{\"content\":{\"name\":\"x\"},\"action\":\"accept\"}",
  )
  round_trip(Answer::Decline, "{\"action\":\"decline\"}")
  round_trip(Answer::Cancel, "{\"action\":\"cancel\"}")
}

///|
test "the other session methods" {
  round_trip(
    LoadSession::{
      session_id: "s",
      cwd: "/w",
      additional_directories: None,
      mcp_servers: [],
      meta: None,
    },
    "{\"sessionId\":\"s\",\"cwd\":\"/w\",\"mcpServers\":[]}",
  )
  round_trip(
    ResumeSession::{
      session_id: "s",
      cwd: "/w",
      additional_directories: None,
      mcp_servers: None,
      meta: None,
    },
    "{\"sessionId\":\"s\",\"cwd\":\"/w\"}",
  )
  round_trip(
    ListSessions::{ cwd: Some("/w"), cursor: None, meta: None, },
    "{\"cwd\":\"/w\"}",
  )
  round_trip(
    DeleteSession::{ session_id: "s", meta: None, },
    "{\"sessionId\":\"s\"}",
  )
  round_trip(
    CloseSession::{ session_id: "s", meta: None, },
    "{\"sessionId\":\"s\"}",
  )
  round_trip(
    SetMode::{ session_id: "s", mode_id: "edit", meta: None, },
    "{\"sessionId\":\"s\",\"modeId\":\"edit\"}",
  )
  round_trip(
    SetConfigOption::{
      session_id: "s",
      config_id: "model",
      value: ConfigValueId::Value("fast"),
      meta: None,
    },
    "{\"sessionId\":\"s\",\"configId\":\"model\",\"value\":\"fast\"}",
  )
  round_trip(
    SetConfigOption::{
      session_id: "s",
      config_id: "stream",
      value: ConfigValueId::Boolean(true),
      meta: None,
    },
    "{\"sessionId\":\"s\",\"configId\":\"stream\",\"value\":true,\"type\":\"boolean\"}",
  )
  round_trip(
    SetConfigOptions::{ config_options: [], meta: None, },
    "{\"configOptions\":[]}",
  )
  round_trip(
    Authenticate::{ method_id: "a", meta: None, },
    "{\"methodId\":\"a\"}",
  )
}

///|
test "a request is answered with an error object that keeps its code" {
  let refused = Refused::new(
    invalid_params,
    "Invalid params",
    data=Json::string("cwd: missing"),
  )
  let failure = refused.failure()
  assert_eq(failure.code, invalid_params)
  assert_eq(failure.message, "Invalid params")
  let back = refused_of(failure)
  assert_eq(back.code(), invalid_params)
  assert_eq(back.data(), Some(Json::string("cwd: missing")))
  assert_eq(Refused::Unsupported(name="session/load").code(), method_not_found)
  assert_eq(Refused::Malformed(reason="x").code(), invalid_params)
}
