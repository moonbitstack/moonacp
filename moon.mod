name = "moonbitstack/moonacp"

version = "0.1.0"

readme = "README.md"

repository = "https://github.com/moonbitstack/moonacp"

license = "Apache-2.0"

keywords = [
  "acp",
  "agent-client-protocol",
  "agent",
  "editor",
  "coding-agent",
  "zed",
  "json-rpc",
  "asgi",
  "stdio",
  "websocket",
  "sse",
  "moonbit",
]

description = "The Agent Client Protocol for MoonBit: editors talking to agents, over ASGI or stdio."

source = "src"

import {
  "moonbitlang/async@0.22.5",
  "moonbitstack/moonjrpc@0.1.3",
  "moonbitstack/moonasgi@0.10.6",
  "moonbitstack/moonfetch@0.1.5",
  "moonbitstack/moonjson@0.4.3",
  "moonbitstack/moonnet@0.1.10",
}
