name = "moonbitstack/moonacp"

version = "0.2.0"

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
  "moonbitstack/moonjrpc@0.1.5",
  "moonbitstack/moonasgi@0.11.2",
  "moonbitstack/moonfetch@0.1.8",
  "moonbitstack/moonjson@0.5.0",
  "moonbitstack/moonhttp@0.16.0",
  "moonbitstack/moonnet@0.1.12",
  "moonbitstack/moonseed@0.1.3",
  "moonbitstack/moontel@0.2.0",
}
