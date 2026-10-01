"""A detached helper must stop when its client disappears."""

import logging
import os
import signal
import threading


def start_parent_watchdog(interval_s: float = 1.0) -> None:
    parent = os.getppid()

    def watch() -> None:
        wait = threading.Event()
        while not wait.wait(interval_s):
            if os.getppid() != parent:
                logging.getLogger(__name__).warning("parent process exited; cancelling")
                os.kill(os.getpid(), signal.SIGTERM)
                return

    threading.Thread(target=watch, name="fpengine-parent-watchdog", daemon=True).start()
