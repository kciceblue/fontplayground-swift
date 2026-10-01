"""Keep cancellation outside engine Exception handlers and event writes."""

import signal
from collections.abc import Callable, Iterator
from contextlib import contextmanager
from types import SimpleNamespace

_state = SimpleNamespace(critical=0, pending=None, terminal_sent=False, cancelling=False)


class Cancelled(BaseException):
    def __init__(self, signum: int = signal.SIGTERM):
        self.signum = signum
        super().__init__(signum)


class ClientGone(Cancelled):
    pass


def _handle(signum: int, frame: object) -> None:
    if _state.terminal_sent or _state.cancelling:
        return
    if _state.critical:
        _state.pending = signum
        return
    _state.cancelling = True
    raise Cancelled(signum)


def install() -> Callable[[], None]:
    """A signal arriving while the handlers are installed stays pending until the caller's next checkpoint."""
    _state.critical, _state.pending = 1, None
    _state.terminal_sent, _state.cancelling = False, False
    try:
        previous = {sig: signal.signal(sig, _handle) for sig in (signal.SIGTERM, signal.SIGINT)}
    finally:
        _state.critical = 0

    def restore() -> None:
        for sig, handler in previous.items():
            signal.signal(sig, handler)

    return restore


def checkpoint() -> None:
    if _state.pending is not None and not (_state.critical or _state.terminal_sent or _state.cancelling):
        _state.cancelling = True
        raise Cancelled(_state.pending)


@contextmanager
def critical() -> Iterator[None]:
    _state.critical += 1
    try:
        yield
    finally:
        _state.critical -= 1
        checkpoint()


def mark_terminal_sent() -> None:
    _state.terminal_sent = True
