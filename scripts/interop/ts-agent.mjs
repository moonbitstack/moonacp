// An echo agent built with the official TypeScript SDK, so a client written against this library
// can be driven against a foreign implementation.

import { agent, ndJsonStream } from "@agentclientprotocol/sdk";
import { Readable, Writable } from "node:stream";

const app = agent({ name: "ts-echo", version: "0.1.0" })
  .onRequest("initialize", () => ({
    protocolVersion: 1,
    agentCapabilities: {},
    agentInfo: { name: "ts-echo", version: "0.1.0" },
  }))
  .onRequest("session/new", () => ({ sessionId: "ts-1" }))
  .onRequest("session/prompt", async (ctx) => {
    const params = ctx.params;
    const said = (params.prompt ?? [])
      .filter((block) => block.type === "text")
      .map((block) => block.text)
      .join(" ");
    await ctx.client.notify("session/update", {
      sessionId: params.sessionId,
      update: {
        sessionUpdate: "agent_message_chunk",
        content: { type: "text", text: `ts echo: ${said}` },
      },
    });
    return { stopReason: "end_turn" };
  })
  .onNotification("session/cancel", () => {});

app.connect(
  ndJsonStream(Writable.toWeb(process.stdout), Readable.toWeb(process.stdin)),
);
