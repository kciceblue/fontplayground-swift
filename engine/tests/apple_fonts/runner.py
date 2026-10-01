"""Run a single helper with file-backed streams and its own process resource accounting."""

from __future__ import annotations

import json
import os
import signal
import subprocess
import sys
import tempfile
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Literal


@dataclass
class HelperRun:
    returncode: int
    events: list[dict]
    wall_s: float
    peak_rss_mb: float
    timed_out: bool
    stderr_tail: str

    @property
    def result(self) -> dict | None:
        matches = [event for event in self.events if event.get("type") == "result"]
        if len(matches) != 1:
            return None
        return matches[0].get("report", matches[0].get("summary", matches[0]))

    @property
    def error(self) -> dict | None:
        matches = [event for event in self.events if event.get("type") == "error"]
        return matches[0] if len(matches) == 1 else None


def run_helper(
    command: Literal["forge", "scan"],
    request: dict,
    *,
    tmpdir: Path,
    timeout_s: float,
    cancel_after_s: float | None = None,
) -> HelperRun:
    tmpdir.mkdir(parents=True, exist_ok=True)
    helper_tmp = tmpdir / "helper-tmp"
    helper_tmp.mkdir(exist_ok=True)
    request_path = tmpdir / "request.json"
    with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=tmpdir, delete=False) as stream:
        temporary = Path(stream.name)
        json.dump(request, stream, ensure_ascii=False)
        stream.write("\n")
        stream.flush()
        os.fsync(stream.fileno())
    try:
        os.replace(temporary, request_path)
    finally:
        temporary.unlink(missing_ok=True)
    output, errors = tmpdir / "stdout.jsonl", tmpdir / "stderr.log"
    python = os.environ.get("FP_ENGINE_PYTHON") or sys.executable
    env = {**os.environ, "TMPDIR": str(helper_tmp), "PYTHONDONTWRITEBYTECODE": "1"}
    started = time.monotonic()
    terminated_at = None
    timed_out = False
    with request_path.open("rb") as stdin, output.open("wb") as stdout, errors.open("wb") as stderr:
        process = subprocess.Popen(
            [python, "-I", "-B", "-m", "fpengine", command], stdin=stdin, stdout=stdout, stderr=stderr, env=env
        )
        try:
            while True:
                pid, wait_status, usage = os.wait4(process.pid, os.WNOHANG)
                if pid:
                    process.returncode = os.waitstatus_to_exitcode(wait_status)
                    break
                elapsed = time.monotonic() - started
                if terminated_at is None and (
                    elapsed >= timeout_s or cancel_after_s is not None and elapsed >= cancel_after_s
                ):
                    timed_out = elapsed >= timeout_s
                    try:
                        os.kill(process.pid, signal.SIGTERM)
                    except ProcessLookupError:
                        pass
                    terminated_at = time.monotonic()
                elif terminated_at is not None and time.monotonic() - terminated_at >= 2:
                    try:
                        os.kill(process.pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                time.sleep(0.05)
        finally:
            if process.returncode is None:
                try:
                    os.kill(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                _, wait_status, usage = os.wait4(process.pid, 0)
                process.returncode = os.waitstatus_to_exitcode(wait_status)
    wall_s = time.monotonic() - started
    events = [json.loads(line) for line in output.read_text(encoding="utf-8").splitlines() if line.strip()]
    rss_bytes = usage.ru_maxrss if sys.platform == "darwin" else usage.ru_maxrss * 1024
    return HelperRun(
        process.returncode,
        events,
        wall_s,
        rss_bytes / 2**20,
        timed_out,
        errors.read_bytes()[-4096:].decode("utf-8", "replace"),
    )
