// The official TypeScript client driving an agent built with this library, over stdio.
//
//   node ts-client.mjs -- <agent command> [args...]

import { spawn } from "node:child_process";
import { Readable, Writable } from "node:stream";
import { client, ndJsonStream } from "@agentclientprotocol/sdk";

const split = process.argv.indexOf("--");
const command = process.argv.slice(split + 1);
if (split < 0 || command.length === 0) {
  console.error("usage: node ts-client.mjs -- <agent command> [args...]");
  process.exit(2);
}

const child = spawn(command[0], command.slice(1), {
  stdio: ["pipe", "pipe", "inherit"],
});

const updates = [];
const asked = [];

const app = client({ name: "moonacp-interop", version: "0.1.0" })
  .onNotification("session/update", ({ params }) => {
    updates.push(params);
  })
  .onRequest("session/request_permission", ({ params }) => {
    asked.push(params);
    const first = params.options?.[0];
    return first
      ? { outcome: { outcome: "selected", optionId: first.optionId } }
      : { outcome: { outcome: "cancelled" } };
  })
  .onRequest("fs/read_text_file", ({ params }) => ({ content: `read ${params.path}` }))
  .onRequest("fs/write_text_file", () => ({}));

const stream = ndJsonStream(
  Writable.toWeb(child.stdin),
  Readable.toWeb(child.stdout),
);
const connection = app.connect(stream);

const fail = (message) => {
  console.error(`FAIL: ${message}`);
  console.error(`updates seen: ${JSON.stringify(updates)}`);
  child.kill();
  process.exit(1);
};

const init = await connection.agent.request("initialize", {
  protocolVersion: 1,
  clientCapabilities: {},
});
if (init.protocolVersion !== 1) fail(`protocol version ${init.protocolVersion}`);
console.log("initialize: ok", init.agentInfo?.name ?? "");

const started = await connection.agent.request("session/new", {
  cwd: process.cwd(),
  mcpServers: [],
});
const sessionId = started.sessionId;
if (typeof sessionId !== "string" || sessionId === "") fail("no session id");
console.log("session:", sessionId);

const turn = await connection.agent.request("session/prompt", {
  sessionId,
  prompt: [{ type: "text", text: "hello from the TypeScript client" }],
});
if (turn.stopReason !== "end_turn") fail(`stop reason ${turn.stopReason}`);
const chunks = updates.filter(
  (update) => update.update?.sessionUpdate === "agent_message_chunk",
);
if (chunks.length === 0) fail("no agent_message_chunk update arrived");
const text = chunks
  .map((update) => (update.update.content?.type === "text" ? update.update.content.text : ""))
  .join("");
if (!text.includes("hello from the TypeScript client")) fail(`answer was ${JSON.stringify(text)}`);
console.log("turn:", turn.stopReason, JSON.stringify(text));

// A second turn, cancelled while it runs: the agent still answers exactly once.
const cancelled = connection.agent.request("session/prompt", {
  sessionId,
  prompt: [{ type: "text", text: "think for a while" }],
});
await connection.agent.notify("session/cancel", { sessionId });
const second = await cancelled;
if (second.stopReason !== "cancelled") fail(`cancelled turn answered ${second.stopReason}`);
console.log("cancel:", second.stopReason);

child.stdin.end();
child.kill();
console.log("all checks passed");
