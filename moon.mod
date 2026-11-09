name = "moonbitstack/moonacp"

version = "0.1.1"

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
  "moonbitstack/moonjrpc@0.1.4",
  "moonbitstack/moonasgi@0.10.8",
  "moonbitstack/moonfetch@0.1.8",
  "moonbitstack/moonjson@0.4.4",
  "moonbitstack/moonnet@0.1.12",
  "moonbitstack/moonseed@0.1.3",
  "moonbitstack/moontel@0.1.2",
}
