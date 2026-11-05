#!/usr/bin/env python3
"""An echo agent built with the official Python SDK, so a client written against this library can be
driven against a foreign implementation.

    python scripts/interop/py-agent.py

Speaks the protocol on stdin and stdout, and answers one turn with one chunk of text.
"""

from __future__ import annotations

import asyncio
import sys

import acp
from acp.schema import AgentCapabilities, AgentMessageChunk, Implementation, TextContent


class EchoAgent(acp.Agent):
    def __init__(self) -> None:
        self.sessions = 0
        self.client = None

    def bind(self, client):
        """The SDK hands the agent its client through the factory, so keep it."""
        self.client = client
        return self

    async def initialize(self, protocol_version, client_capabilities=None, client_info=None, **kwargs):
        return acp.InitializeResponse(
            protocol_version=acp.PROTOCOL_VERSION,
            agent_capabilities=AgentCapabilities(),
            agent_info=Implementation(name="python-echo", version="0.1.0"),
        )

    async def new_session(self, cwd, additional_directories=None, mcp_servers=None, **kwargs):
        self.sessions += 1
        return acp.NewSessionResponse(session_id=f"py-{self.sessions}")

    async def prompt(self, session_id, prompt, **kwargs):
        said = " ".join(
            block.text for block in prompt if getattr(block, "type", None) == "text"
        )
        # The connection is the second argument the SDK passes to the factory, so the session
        # updates go through `self.client`, set up in `main`.
        await self.client.session_update(
            session_id=session_id,
            update={
                "sessionUpdate": "agent_message_chunk",
                "content": {"type": "text", "text": f"python echo: {said}"},
            },
        )
        return acp.PromptResponse(stop_reason="end_turn")

    async def cancel(self, session_id, **kwargs):
        return None


async def main() -> int:
    reader, writer = await acp.stdio_streams()
    connection = acp.AgentSideConnection(
        lambda client: EchoAgent().bind(client), writer, reader
    )
    try:
        await connection.listen()
    finally:
        await connection.close()
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
