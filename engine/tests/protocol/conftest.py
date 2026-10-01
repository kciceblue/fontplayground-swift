"""Validate the actual wire bytes from every helper invocation."""

import io
import json
import os
import signal
import subprocess
import sys
import time
from pathlib import Path

import pytest
from fontTools.colorLib.builder import buildCOLR, buildCPAL
from fontTools.ttLib import TTFont
from jsonschema import Draft202012Validator
from referencing import Registry, Resource

from tests.fixtures import build_font, cps

ROOT = Path(__file__).resolve().parents[3]
SCHEMAS = ROOT / "spec/protocol"
DRIVERS = Path(__file__).parent / "drivers"


@pytest.fixture(scope="session")
def schemas():
    return {path.name: json.loads(path.read_text()) for path in SCHEMAS.glob("*.schema.json")}


@pytest.fixture(scope="session")
def registry(schemas):
    return Registry().with_resources((schema["$id"], Resource.from_contents(schema)) for schema in schemas.values())


@pytest.fixture(scope="session")
def validator(schemas, registry):
    return Draft202012Validator(schemas["event.schema.json"], registry=registry)


@pytest.fixture
def validate_wire(validator):
    def validate(raw, code):
        assert not raw or raw.endswith(b"\n")
        events = []
        for line in raw.splitlines():
            assert line and not line.startswith(b"\xef\xbb\xbf")
            event = json.loads(line.decode("utf-8"))
            validator.validate(event)
            events.append(event)
        terminals = [i for i, event in enumerate(events) if event["type"] in ("result", "error")]
        if code in (0, 2, 3):
            assert terminals == [len(events) - 1]
        else:
            assert code in (130, 141, 143)
            assert not terminals
        return events

    return validate


@pytest.fixture
def run_helper(validate_wire):
    def run(command, request=b"", *, env=None, driver=None, on_event=None, close_stdout=False):
        args = [] if command is None else [command]
        entry = [str(DRIVERS / f"{driver}.py")] if driver else ["-m", "fpengine"]
        data = request if isinstance(request, bytes) else json.dumps(request, ensure_ascii=False).encode()
        process = subprocess.Popen(
            [sys.executable, "-I", "-B", *entry, *args],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env={**os.environ, **(env or {})},
        )
        try:
            if on_event or close_stdout:
                process.stdin.write(data)
                process.stdin.close()
                process.stdin = None
                raw = b""
                while line := process.stdout.readline():
                    raw += line
                    if close_stdout:
                        process.stdout.close()
                        process.stdout = None
                        break
                    on_event(process, json.loads(line))
                tail, stderr = process.communicate(timeout=10)
                raw += tail or b""
            else:
                raw, stderr = process.communicate(data, timeout=20)
            events = validate_wire(raw, process.returncode)
            return events, process.returncode, stderr.decode(), raw
        finally:
            if process.poll() is None:
                process.kill()
                process.communicate()

    return run


@pytest.fixture
def inprocess(validate_wire):
    from fpengine.cli import main

    def run(command, request):
        output = io.BytesIO()
        data = request if isinstance(request, bytes) else json.dumps(request, ensure_ascii=False).encode()
        code = main([command], stdin=io.BytesIO(data), stdout=output)
        return validate_wire(output.getvalue(), code), code, output.getvalue()

    return run


@pytest.fixture
def forge_request(font_dir, tmp_path):
    return {
        "spec": {
            "materials": [{"path": str(font_dir / name), "index": 0} for name in ("A.ttf", "B.otf")],
            "script_rules": {"han": 1},
            "family_name": "Fixture Forged",
        },
        "output_path": str(tmp_path / "builds/output.ttf"),
    }


@pytest.fixture
def color_font(tmp_path):
    path = build_font(tmp_path / "Color.ttf", "Fixture Color", "Regular", cps("ABC"))
    with TTFont(path) as font:
        font["COLR"] = buildCOLR({"uni0041": [("uni0042", 0)]})
        font["CPAL"] = buildCPAL([[(1.0, 0.0, 0.0, 1.0)]])
        font.save(path)
    return path


@pytest.fixture
def cancel_forge(run_helper, forge_request, tmp_path):
    def run(signum=signal.SIGTERM):
        sent = []

        def on_event(process, event):
            if event.get("stage") == "prepare" and not sent:
                time.sleep(0.3)
                sent.append(time.monotonic())
                process.send_signal(signum)

        result = run_helper(
            "forge", forge_request, driver="slow_forge", env={"TMPDIR": str(tmp_path / "tmp")}, on_event=on_event
        )
        assert sent
        return result, time.monotonic() - sent[0]

    return run
