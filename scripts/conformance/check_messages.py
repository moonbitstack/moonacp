#!/usr/bin/env python3
"""Drive an agent over stdio and check every message in both directions against the protocol schema.

The schema is the published one for the version this library implements, vendored beside this
script and pinned there. The script plays the editor: it opens a session, runs a turn, asks for the
session list, sets a mode, cancels a turn, and loads the session again. Whatever the agent writes
and whatever this script writes goes through `jsonschema` before anything else is believed.

    python scripts/conformance/check_messages.py -- <agent command> [args...]

Exits non-zero if any message fails to validate or if a request goes unanswered.
"""

from __future__ import annotations

import json
import os
import queue
import subprocess
import sys
import threading
from pathlib import Path

import jsonschema

SCHEMA = Path(__file__).with_name("schema-v1.29.1.json")
PROTOCOL_VERSION = 1


class Checker:
    """Every message either side writes goes through the schema as it is written."""

    def __init__(self) -> None:
        schema = json.loads(SCHEMA.read_text(encoding="utf-8"))
        self.validator = jsonschema.Draft202012Validator(schema)
        self.checked = 0
        self.failures: list[str] = []
        self.lock = threading.Lock()

    def check(self, text: str, direction: str) -> None:
        with self.lock:
            self.checked += 1
            message = json.loads(text)
            errors = sorted(self.validator.iter_errors(message), key=lambda e: list(e.path))
            if errors:
                first = errors[0]
                where = "/".join(str(part) for part in first.path) or "(root)"
                self.failures.append(f"{direction}: {where}: {first.message}\n    {text}")


class Agent:
    """A subprocess that speaks one JSON-RPC message per line."""

    def __init__(self, command: list[str], cwd: str | None, checker: Checker) -> None:
        self.checker = checker
        self.process = subprocess.Popen(
            command,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            cwd=cwd,
            text=True,
            encoding="utf-8",
            bufsize=1,
        )
        self.lines: queue.Queue[str | None] = queue.Queue()
        self.seen: list[str] = []
        self.stderr: list[str] = []
        threading.Thread(target=self._read, daemon=True).start()
        threading.Thread(target=self._read_stderr, daemon=True).start()
        self.next_id = 0

    def _read(self) -> None:
        assert self.process.stdout is not None
        for line in self.process.stdout:
            if line.strip():
                self.checker.check(line, "agent")
            self.lines.put(line)
        self.lines.put(None)

    def _read_stderr(self) -> None:
        assert self.process.stderr is not None
        for line in self.process.stderr:
            self.stderr.append(line)

    def send(self, message: dict) -> None:
        assert self.process.stdin is not None
        text = json.dumps(message, ensure_ascii=False)
        self.checker.check(text, "client")
        self.seen.append(text)
        self.process.stdin.write(text + "\n")
        self.process.stdin.flush()

    def request(self, method: str, params: dict | None = None, timeout: float = 30.0) -> dict:
        self.next_id += 1
        message = {"jsonrpc": "2.0", "id": self.next_id, "method": method}
        if params is not None:
            message["params"] = params
        self.send(message)
        return self.answer(self.next_id, timeout)

    def notify(self, method: str, params: dict | None = None) -> None:
        message = {"jsonrpc": "2.0", "method": method}
        if params is not None:
            message["params"] = params
        self.send(message)

    def answer(self, request_id: int, timeout: float = 30.0) -> dict:
        while True:
            try:
                line = self.lines.get(timeout=timeout)
            except queue.Empty:
                raise SystemExit(f"the agent did not answer request {request_id} in {timeout}s")
            if line is None:
                raise SystemExit(f"the agent exited before answering request {request_id}")
            message = json.loads(line)
            if message.get("id") == request_id and "method" not in message:
                return message

    def close(self) -> None:
        assert self.process.stdin is not None
        self.process.stdin.close()
        try:
            self.process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            self.process.kill()


def main(argv: list[str]) -> int:
    if "--" not in argv:
        raise SystemExit(__doc__)
    split = argv.index("--")
    command = argv[split + 1 :]
    if not command:
        raise SystemExit(__doc__)

    checker = Checker()
    agent = Agent(command, os.environ.get("AGENT_CWD"), checker)
    try:
        print(
            "initialize:",
            agent.request(
                "initialize",
                {"protocolVersion": PROTOCOL_VERSION, "clientCapabilities": {}},
            )["result"].get("protocolVersion"),
        )

        session = agent.request("session/new", {"cwd": os.getcwd(), "mcpServers": []})["result"][
            "sessionId"
        ]
        print("session:", session)

        turn = agent.request(
            "session/prompt",
            {"sessionId": session, "prompt": [{"type": "text", "text": "hello"}]},
            timeout=60.0,
        )
        print("turn:", turn["result"]["stopReason"])

        listing = agent.request("session/list", {})
        print("sessions listed:", len(listing["result"].get("sessions", [])))

        agent.request("session/set_mode", {"sessionId": session, "modeId": "edit"})
        loaded = agent.request(
            "session/load",
            {"sessionId": session, "cwd": os.getcwd(), "mcpServers": []},
        )
        print("load: ok" if "result" in loaded else f"load: {loaded.get('error')}")

        # A turn that is cancelled while it runs still answers exactly once.
        agent.next_id += 1
        prompt_id = agent.next_id
        agent.send(
            {
                "jsonrpc": "2.0",
                "id": prompt_id,
                "method": "session/prompt",
                "params": {"sessionId": session, "prompt": [{"type": "text", "text": "think"}]},
            }
        )
        agent.notify("session/cancel", {"sessionId": session})
        cancelled = agent.answer(prompt_id, timeout=60.0)
        print("cancel:", cancelled.get("result", {}).get("stopReason"))
    finally:
        agent.close()

    if checker.failures:
        print(f"\n{len(checker.failures)} of {checker.checked} messages do not match the schema:\n")
        for failure in checker.failures:
            print(failure)
        return 1
    print(f"\nall {checker.checked} messages match the schema")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
