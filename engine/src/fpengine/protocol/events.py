"""One flushed UTF-8 line per event, including during cancellation."""

import json
import logging
from typing import BinaryIO

from fpengine.protocol import PROTOCOL_VERSION, cancel

_FALLBACK = (
    b'{"protocol":1,"type":"error","code":"internal","stage":null,"material_index":null,'
    b'"message":"Unexpected error while reporting an error.","detail":null}\n'
)


class EventSerializationError(Exception):
    """An internal terminal event has already been written; unwind the command."""


class EventWriter:
    def __init__(self, stream: BinaryIO):
        self.stream = stream
        self.last_stage: str | None = None
        self.terminal_sent = False

    def emit(self, type_: str, **payload: object) -> None:
        if self.terminal_sent:
            raise RuntimeError("An event was emitted after the terminal event.")
        event = {"protocol": PROTOCOL_VERSION, "type": type_, **payload}
        try:
            line = (json.dumps(event, ensure_ascii=False, separators=(",", ":"), allow_nan=False) + "\n").encode()
        except (TypeError, ValueError, UnicodeError):
            logging.getLogger(__name__).exception("Cannot serialize %s event", type_)
            if type_ == "error":
                with cancel.critical():
                    self._write(_FALLBACK)
                    self.terminal_sent = True
                    cancel.mark_terminal_sent()
            else:
                self.terminal(
                    "error",
                    code="internal",
                    stage="verify" if self.last_stage == "done" else self.last_stage,
                    material_index=None,
                    message="Unexpected error.",
                    detail=None,
                )
            raise EventSerializationError("Event serialization failed") from None
        with cancel.critical():
            self._write(line)
            if type_ == "progress":
                self.last_stage = str(payload["stage"])

    def _write(self, line: bytes) -> None:
        try:
            self.stream.write(line)
            self.stream.flush()
        except (BrokenPipeError, ValueError) as exc:
            raise cancel.ClientGone() from exc

    def terminal(self, type_: str, **payload: object) -> None:
        if self.terminal_sent:
            raise RuntimeError("A terminal event was already emitted.")
        if type_ not in ("result", "error"):
            raise ValueError("Not a terminal event.")
        with cancel.critical():
            self.emit(type_, **payload)
            self.terminal_sent = True
            cancel.mark_terminal_sent()
