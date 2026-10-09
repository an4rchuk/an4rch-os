"""A small client for greetd's IPC protocol (man 7 greetd-ipc).

Each message is a 32-bit length in native byte order followed by JSON. A
login is: create_session(username) → answer each auth_message until greetd
says success → start_session(cmd). Errors and wrong passwords come back as
{"type": "error", ...}; cancel_session starts over.
"""
from __future__ import annotations

import json
import os
import socket
import struct
from dataclasses import dataclass, field


class GreetdError(Exception):
    pass


@dataclass
class Prompt:
    """Something greetd wants: kind is "secret", "visible", "info" or "error"."""
    kind: str
    text: str


@dataclass
class Result:
    ok: bool = False
    prompt: Prompt | None = None        # greetd needs another answer
    error: str = ""                     # a failed login, in plain words
    messages: list[str] = field(default_factory=list)


class Greetd:
    def __init__(self, path: str | None = None):
        path = path or os.environ.get("GREETD_SOCK")
        if not path:
            raise GreetdError("GREETD_SOCK isn't set: not started by greetd")
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.connect(path)

    def close(self) -> None:
        try:
            self.sock.close()
        except OSError:
            pass

    def _recv(self, n: int) -> bytes:
        buf = b""
        while len(buf) < n:
            chunk = self.sock.recv(n - len(buf))
            if not chunk:
                raise GreetdError("greetd closed the connection")
            buf += chunk
        return buf

    def request(self, msg: dict) -> dict:
        data = json.dumps(msg).encode()
        self.sock.sendall(struct.pack("=I", len(data)) + data)
        (n,) = struct.unpack("=I", self._recv(4))
        return json.loads(self._recv(n))

    def _follow(self, reply: dict, answers: list[str]) -> Result:
        """Answer prompts with `answers` in turn; stop at success, an error,
        or a prompt we have no answer for."""
        result = Result()
        while True:
            kind = reply.get("type")
            if kind == "success":
                result.ok = True
                return result
            if kind == "error":
                self.request({"type": "cancel_session"})
                desc = reply.get("description", "")
                if reply.get("error_type") == "auth_error":
                    result.error = "Wrong password. Try again."
                else:
                    result.error = desc or "Couldn't log in."
                return result
            if kind != "auth_message":
                raise GreetdError(f"unexpected reply from greetd: {reply}")
            mtype = reply.get("auth_message_type", "")
            text = reply.get("auth_message", "").strip()
            if mtype in ("info", "error"):
                # Nothing to answer (e.g. "Place your finger on the reader").
                if text:
                    result.messages.append(text)
                reply = self.request({"type": "post_auth_message_response"})
                continue
            if not answers:
                result.prompt = Prompt(mtype, text)
                return result
            reply = self.request({"type": "post_auth_message_response", "response": answers.pop(0)})

    def login(self, username: str, password: str) -> Result:
        reply = self.request({"type": "create_session", "username": username})
        return self._follow(reply, [password])

    def answer(self, response: str) -> Result:
        """Answer a further prompt (a second factor, a new password…)."""
        reply = self.request({"type": "post_auth_message_response", "response": response})
        return self._follow(reply, [])

    def start(self, cmd: list[str], env: list[str] | None = None) -> None:
        reply = self.request({"type": "start_session", "cmd": cmd, "env": env or []})
        if reply.get("type") != "success":
            raise GreetdError(reply.get("description", "couldn't start the session"))

    def cancel(self) -> None:
        try:
            self.request({"type": "cancel_session"})
        except (OSError, GreetdError, ValueError):
            pass
