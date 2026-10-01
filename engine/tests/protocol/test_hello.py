import importlib.metadata
import json
import platform
import subprocess
import sys

import fontTools

from fpengine.face import READER_VERSION


def test_hello_events_and_exit_code(run_helper):
    events, code, stderr, raw = run_helper("hello")
    assert code == 0 and len(events) == 2
    assert events[0]["type"] == "hello"
    assert events[1] == {"protocol": 1, "type": "result", "command": "hello"}
    assert events[0]["fpengine_version"] == importlib.metadata.version("fpengine")
    assert events[0]["fonttools"] == fontTools.version
    assert events[0]["python"] == platform.python_version()
    assert events[0]["face_reader_version"] == READER_VERSION
    assert "start hello" in stderr and "finished hello" in stderr
    assert raw.count(b"\n") == 2


def test_helper_imports_only_engine_modules(forge_request):
    script = """
import io, json, sys
from fpengine.cli import main
assert 'fontTools' not in sys.modules
request = json.loads(sys.argv[1])
commands = [('hello', {}), ('scan', {'files': [request['spec']['materials'][0]['path']]}), ('forge', request)]
for command, data in commands:
    assert main([command], stdin=io.BytesIO(json.dumps(data).encode()), stdout=io.BytesIO()) == 0
print(json.dumps(sorted({name.split('.')[0] for name in sys.modules})))
"""
    process = subprocess.run([sys.executable, "-I", "-B", "-c", script, json.dumps(forge_request)], capture_output=True)
    assert process.returncode == 0, process.stderr
    assert not ({"PySide6", "objc", "AppKit", "jsonschema", "referencing"} & set(json.loads(process.stdout)))


def test_help_and_version():
    for argument, expected in (("--help", "Usage:"), ("-h", "Usage:"), ("--version", "fpengine 1.0.0")):
        result = subprocess.run([sys.executable, "-I", "-B", "-m", "fpengine", argument], capture_output=True)
        assert result.returncode == 0
        assert result.stdout.decode().startswith(expected)
