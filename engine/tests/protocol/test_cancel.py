import json
import os
import signal
import subprocess
import sys
import time
from pathlib import Path

from tests.protocol.conftest import DRIVERS


def test_native_7_sigterm_mid_stage_exits_143_within_1s(cancel_forge):
    (events, code, stderr, _), elapsed = cancel_forge()
    assert code == 143 and elapsed < 1.0
    assert events[-1]["stage"] == "prepare" and "cancelled by SIGTERM" in stderr


def test_engine_9_cancel_removes_temp_and_partial_output(cancel_forge, forge_request, tmp_path):
    (_, code, _, _), _ = cancel_forge()
    assert code == 143 and list((tmp_path / "tmp").iterdir()) == []
    output = Path(forge_request["output_path"])
    assert not output.exists() and not list(output.parent.glob(".fpengine-*"))


def test_sigterm_after_result_exits_0(run_helper, forge_request):
    def on_event(process, event):
        if event["type"] == "result":
            process.send_signal(signal.SIGTERM)

    _, code, _, _ = run_helper("forge", forge_request, driver="pause_after_result", on_event=on_event)
    assert code == 0 and Path(forge_request["output_path"]).exists()


def test_sigint_exits_130(cancel_forge):
    assert cancel_forge(signal.SIGINT)[0][1] == 130


def test_scan_sigterm_between_files(run_helper, font_dir):
    sent = []

    def on_event(process, event):
        if event["type"] == "face" and not sent:
            sent.append(True)
            process.send_signal(signal.SIGTERM)

    events, code, _, _ = run_helper(
        "scan",
        {"files": [str(font_dir / n) for n in ("A.ttf", "B.otf", "C.ttf")]},
        driver="slow_scan",
        on_event=on_event,
    )
    assert code == 143 and any(event["type"] == "face" for event in events)


def test_helper_cancels_when_parent_exits(forge_request, tmp_path):
    pid_path, log_path = tmp_path / "pid", tmp_path / "stderr"
    base = tmp_path / "tmp"
    parent = subprocess.run(
        [
            sys.executable,
            "-I",
            "-B",
            str(DRIVERS / "orphan_parent.py"),
            json.dumps(forge_request),
            str(pid_path),
            str(log_path),
        ],
        env={**os.environ, "TMPDIR": str(base)},
        capture_output=True,
        timeout=10,
    )
    assert parent.returncode == 0, parent.stderr
    pid = int(pid_path.read_text())
    try:
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            try:
                os.kill(pid, 0)
            except ProcessLookupError:
                break
            time.sleep(0.05)
        else:
            raise AssertionError(f"Orphan helper {pid} did not exit: {log_path.read_text()}")
        assert "parent process exited; cancelling" in log_path.read_text()
        assert list(base.iterdir()) == []
    finally:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def test_client_closing_stdout_stops_helper(run_helper, font_dir):
    started = time.monotonic()
    _, code, stderr, _ = run_helper(
        "scan",
        {"files": [str(font_dir / n) for n in ("A.ttf", "B.otf", "C.ttf")]},
        driver="slow_scan",
        close_stdout=True,
    )
    assert code == 141 and time.monotonic() - started < 2
    assert "Exception ignored" not in stderr and "Traceback" not in stderr
