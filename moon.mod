name = "moonbitstack/moonacp"

version = "0.2.2"

readme = "README.md"

repository = "https://github.com/moonbitstack/moonacp"

license = "Apache-2.0"

keywords = [
  "acp",
  "agent-client-protocol",
  "agent",
  "client",
  "editor",
  "coding-agent",
  "zed",
  "json-rpc",
  "jsonrpc",
  "rpc",
  "asgi",
  "stdio",
  "stdin",
  "websocket",
  "ws",
  "sse",
  "http",
  "streamable-http",
  "http-client",
  "remote",
  "session",
  "prompt",
  "streaming",
  "tool-call",
  "permission",
  "terminal",
  "elicitation",
  "protocol",
  "async",
  "server",
  "opentelemetry",
  "otel",
  "tracing",
  "telemetry",
  "gen-ai",
  "semantic-conventions",
  "moonbit",
]

description = "The Agent Client Protocol for MoonBit: editors talking to agents, over ASGI or stdio."

source = "src"

import {
  "moonbitlang/async@0.22.5",
  "moonbitstack/moonjrpc@0.2.1",
  "moonbitstack/moonasgi@0.11.3",
  "moonbitstack/moonfetch@0.2.1",
  "moonbitstack/moonjson@0.5.1",
  "moonbitstack/moonhttp@0.16.1",
  "moonbitstack/moonnet@0.2.2",
  "moonbitstack/moonseed@0.2.1",
  "moonbitstack/moontel@0.2.3",
}
