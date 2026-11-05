#!/usr/bin/env python3
"""The official Python client driving an agent built with this library, over stdio.

    python scripts/interop/py-client.py -- <agent command> [args...]

Installs as `agent-client-protocol`; the version is pinned in requirements.txt beside this script.
"""

from __future__ import annotations

import asyncio
import os
import sys

import acp


class Recorder(acp.Client):
    """What the client is expected to answer: it watches the updates and allows anything asked."""

    def __init__(self) -> None:
        self.updates: list[str] = []
        self.text: list[str] = []
        self.asked = 0

    async def session_update(self, session_id: str, update, **kwargs) -> None:
        kind = getattr(update, "session_update", "")
        self.updates.append(kind)
        if kind == "agent_message_chunk":
            content = getattr(update, "content", None)
            if getattr(content, "type", None) == "text":
                self.text.append(content.text)

    async def request_permission(self, session_id, tool_call, options, **kwargs):
        self.asked += 1
        if options:
            return {"outcome": {"outcome": "selected", "optionId": options[0].option_id}}
        return {"outcome": {"outcome": "cancelled"}}

    async def read_text_file(self, session_id, path, line=None, limit=None, **kwargs):
        return {"content": f"read {path}"}

    async def write_text_file(self, session_id, path, content, **kwargs):
        return {}


class Agent:
    """A subprocess speaking the protocol on its own stdio."""

    def __init__(self, command: list[str]) -> None:
        self.command = command
        self.process: asyncio.subprocess.Process | None = None

    async def start(self) -> tuple[asyncio.StreamReader, asyncio.StreamWriter]:
        self.process = await asyncio.create_subprocess_exec(
            *self.command,
            stdin=asyncio.subprocess.PIPE,
            stdout=asyncio.subprocess.PIPE,
            stderr=sys.stderr,
            cwd=os.environ.get("AGENT_CWD") or None,
        )
        assert self.process.stdin is not None and self.process.stdout is not None
        return self.process.stdout, self.process.stdin

    async def stop(self) -> None:
        if self.process is None:
            return
        assert self.process.stdin is not None
        self.process.stdin.close()
        try:
            await asyncio.wait_for(self.process.wait(), timeout=10)
        except asyncio.TimeoutError:
            self.process.kill()


def fail(message: str) -> None:
    print(f"FAIL: {message}")
    raise SystemExit(1)


async def main(argv: list[str]) -> int:
    if "--" not in argv:
        raise SystemExit(__doc__)
    command = argv[argv.index("--") + 1 :]
    if not command:
        raise SystemExit(__doc__)

    agent = Agent(command)
    reader, writer = await agent.start()
    recorder = Recorder()
    connection = acp.connect_to_agent(recorder, writer, reader)

    try:
        init = await connection.initialize(protocol_version=acp.PROTOCOL_VERSION)
        if init.protocol_version != acp.PROTOCOL_VERSION:
            fail(f"protocol version {init.protocol_version}")
        print("initialize: ok", init.agent_info.name if init.agent_info else "")

        session = await connection.new_session(cwd=os.getcwd(), mcp_servers=[])
        session_id = session.session_id
        if not session_id:
            fail("no session id")
        print("session:", session_id)

        turn = await connection.prompt(
            session_id, [{"type": "text", "text": "hello from the Python client"}]
        )
        if turn.stop_reason != "end_turn":
            fail(f"stop reason {turn.stop_reason}")
        answer = "".join(recorder.text)
        if "hello from the Python client" not in answer:
            fail(f"answer was {answer!r}")
        print("turn:", turn.stop_reason, repr(answer[:60]))

        # A turn cancelled while it runs still answers exactly once.
        task = asyncio.create_task(
            connection.prompt(
                session_id, [{"type": "text", "text": "think for a while"}]
            )
        )
        await asyncio.sleep(0.05)
        await connection.cancel(session_id)
        cancelled = await asyncio.wait_for(task, timeout=60)
        if cancelled.stop_reason != "cancelled":
            fail(f"cancelled turn answered {cancelled.stop_reason}")
        print("cancel:", cancelled.stop_reason)
    finally:
        await agent.stop()

    print("all checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main(sys.argv[1:])))
