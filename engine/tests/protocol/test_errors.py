import copy
import io
import json
import signal
import sys
from types import SimpleNamespace

import pytest
from jsonschema import Draft202012Validator

from fpengine.protocol import cancel, requests
from fpengine.protocol.errors import ErrorCode, map_forge_error
from fpengine.protocol.events import EventSerializationError, EventWriter
from fpengine.protocol.requests import RequestError, parse_forge, parse_scan
from fpengine.spec import ForgeError
from tests.fixtures import fake_face


def changed(request, case):
    request = copy.deepcopy(request)
    material = request["spec"]["materials"][0]
    if case == "missing_spec":
        del request["spec"]
    elif case == "missing_output":
        del request["output_path"]
    elif case in ("relative", "parent", "dots"):
        material["path"] = {"relative": "a.ttf", "parent": "/a/../a.ttf", "dots": "/a/b..c.ttf"}[case]
    elif case in ("bool", "fraction", "integral"):
        material["weight"] = {"bool": True, "fraction": 700.5, "integral": 700.0}[case]
    elif case == "group":
        request["spec"]["script_rules"] = {"klingon": 1}
    elif case == "negative":
        material["index"] = -1
    elif case == "same":
        request["output_path"] = material["path"]
    elif case == "rules":
        request["spec"]["script_rules"] = {"han": None, "kana": 7}
    elif case == "unknown":
        request["new"] = {"ignored": True}
        material["future"] = 17
    elif case == "expect":
        material["expect"] = {"postscript_name": None, "size": 0, "mtime": 0.0}
    return request


@pytest.mark.parametrize(
    "case",
    [
        "not_json",
        "array",
        "nan",
        "utf8",
        "missing_spec",
        "missing_output",
        "relative",
        "parent",
        "bool",
        "fraction",
        "group",
        "negative",
        "same",
        "command",
        "no_command",
    ],
)
def test_bad_requests(case, run_helper, forge_request):
    raw = {"not_json": b"no", "array": b"[]", "nan": b'{"n":NaN}', "utf8": b"\xff"}
    command = "forgee" if case == "command" else None if case == "no_command" else "forge"
    request = raw.get(case, changed(forge_request, case))
    events, code, _, _ = run_helper(command, request)
    assert code == 2 and len(events) == (2 if case == "same" else 1)
    assert events[-1]["code"] == "bad_request" and events[-1]["stage"] is None
    exact = {
        "bool": "Invalid request: spec.materials[0].weight: must be an integer.",
        "relative": "Invalid request: spec.materials[0].path: must be an absolute path.",
        "command": "Unknown command 'forgee'. Use hello, scan or forge.",
    }
    if case in exact:
        assert events[-1]["message"] == exact[case]


def test_integral_weight_is_accepted(run_helper, forge_request):
    assert run_helper("forge", changed(forge_request, "integral"))[1] == 0


@pytest.mark.parametrize(
    "case",
    [
        "missing_spec",
        "missing_output",
        "relative",
        "parent",
        "bool",
        "fraction",
        "group",
        "negative",
        "integral",
        "dots",
        "rules",
        "unknown",
        "expect",
        "scan_empty",
        "scan_string",
        "scan_root",
        "scan_too_many",
    ],
)
def test_parser_agrees_with_schema(case, schemas, registry, forge_request):
    scan_cases = {"scan_empty": [], "scan_string": "x", "scan_root": ["/"], "scan_too_many": ["/a"] * 100001}
    scan = case.startswith("scan_")
    obj = {"files": scan_cases[case]} if scan else changed(forge_request, case)
    schema = schemas[("scan" if scan else "forge") + "-request.schema.json"]
    accepted = Draft202012Validator(schema, registry=registry).is_valid(obj)
    try:
        (parse_scan if scan else parse_forge)(obj)
    except RequestError:
        parsed = False
    else:
        parsed = True
    assert parsed == accepted


@pytest.mark.parametrize(
    "stage,code",
    [
        ("validate", "validate"),
        ("prepare", "prepare_failed"),
        ("merge", "merge_failed"),
        ("finish", "finish_failed"),
        ("verify", "verify_failed"),
        ("unknown", "internal"),
    ],
)
def test_map_forge_error(stage, code):
    progress = SimpleNamespace(stage="merge", material_index=1)
    error = map_forge_error(ForgeError(stage, None, "x"), progress, [])
    assert error.code == code and error.stage == ("merge" if stage == "unknown" else stage)
    assert error.material_index == (1 if stage == "prepare" else None)
    assert error.message == "x" and "ForgeError" in error.detail


def test_map_forge_error_precedence_cause_and_unique_material():
    progress = SimpleNamespace(stage="verify", material_index=1)
    faces = [fake_face({65}, family="First"), fake_face({66}, family="Second")]
    error = ForgeError("prepare", "First Regular", "x", code="aat_unsupported_script", material_index=0)
    mapped = map_forge_error(error, progress, faces)
    assert mapped.code == ErrorCode.AAT_UNSUPPORTED_SCRIPT and mapped.material_index == 0
    error = ForgeError("finish", None, "disk")
    error.__cause__ = OSError("disk")
    assert map_forge_error(error, progress, faces).code == ErrorCode.IO_ERROR
    error = ForgeError("verify", "First Regular", "x")
    assert map_forge_error(error, progress, faces).material_index == 0
    assert map_forge_error(error, progress, [faces[0], faces[0]]).material_index is None
    error = ForgeError("done", None, "x", code="internal")
    assert map_forge_error(error, progress, faces).stage == "verify"


def test_request_bound_unicode_and_exact_errors(monkeypatch):
    monkeypatch.setattr(requests, "MAX_REQUEST_BYTES", 4)
    with pytest.raises(RequestError, match="Request is too large"):
        requests.read_request(io.BytesIO(b"12345"), allow_empty=False)
    with pytest.raises(RequestError, match="invalid Unicode escape"):
        parse_scan({"files": ["/a\ud800"]})
    with pytest.raises(RequestError, match="must be a number"):
        parse_forge({"spec": {"materials": [], "default_scale": True}, "output_path": "/a"})


def test_event_writer_serialization_failure_and_second_terminal(validate_wire):
    restore = cancel.install()
    try:
        output = io.BytesIO()
        writer = EventWriter(output)
        with pytest.raises(EventSerializationError):
            writer.emit("face", face={"bug": object()})
        assert validate_wire(output.getvalue(), 3)[-1]["code"] == "internal"
        with pytest.raises(RuntimeError):
            writer.terminal("result", command="hello")
        output = io.BytesIO()
        writer = EventWriter(output)
        with pytest.raises(EventSerializationError):
            writer.terminal("error", code=object())
        assert json.loads(output.getvalue())["message"] == "Unexpected error while reporting an error."
    finally:
        restore()


def test_serialization_failure_unwinds_cli_with_exit_3(monkeypatch, inprocess):
    from fpengine.commands import hello

    reached = []

    def broken(req, out):
        out.terminal("result", command="hello", unexpected=object())
        reached.append(True)
        return 0

    monkeypatch.setattr(hello, "run", broken)
    events, code, _ = inprocess("hello", {})
    assert code == 3 and events[-1]["code"] == "internal" and not reached


def test_signal_is_deferred_through_event_flush():
    class Interrupted(io.BytesIO):
        def flush(self):
            signal.raise_signal(signal.SIGTERM)

    restore = cancel.install()
    try:
        output = Interrupted()
        with pytest.raises(cancel.Cancelled):
            EventWriter(output).emit("progress", stage="validate", fraction=0.0)
        assert json.loads(output.getvalue())["stage"] == "validate"
    finally:
        restore()


def test_signal_after_terminal_flush_is_ignored():
    class Interrupted(io.BytesIO):
        def flush(self):
            signal.raise_signal(signal.SIGTERM)

    restore = cancel.install()
    try:
        writer = EventWriter(Interrupted())
        writer.terminal("result", command="hello")
        assert writer.terminal_sent
        signal.raise_signal(signal.SIGTERM)
    finally:
        restore()


def test_sigterm_during_startup_exits_143_and_restores(monkeypatch):
    from fpengine import cli

    original = cli.configure_logging

    def interrupted():
        signal.raise_signal(signal.SIGTERM)
        return original()

    monkeypatch.setattr(cli, "configure_logging", interrupted)
    previous, saved_stdout = signal.getsignal(signal.SIGTERM), sys.stdout
    output = io.BytesIO()
    assert cli.main(["hello"], stdin=io.BytesIO(b"{}"), stdout=output) == 143
    assert sys.stdout is saved_stdout and signal.getsignal(signal.SIGTERM) is previous
    assert output.getvalue() == b""
