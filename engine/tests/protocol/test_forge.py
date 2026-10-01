import os
import tempfile
from dataclasses import dataclass
from pathlib import Path
from types import SimpleNamespace

import pytest
from fontTools.ttLib import TTFont

from fpengine.face import read_faces
from fpengine.protocol.report import INTERIM_REPORT_FIELDS, OutputNames, forge_report
from fpengine.protocol.requests import parse_forge
from fpengine.spec import ForgeError


def test_native_3_forge_round_trip(run_helper, forge_request):
    events, code, _, _ = run_helper("forge", forge_request)
    assert code == 0
    progress = events[:-1]
    assert [e["stage"] for e in progress] == [
        "validate",
        "plan",
        "prepare",
        "prepare",
        "merge",
        "finish",
        "verify",
        "done",
    ]
    assert [e["material_index"] for e in progress if e["stage"] == "prepare"] == [0, 1]
    assert [e["fraction"] for e in progress] == sorted(e["fraction"] for e in progress)
    report = events[-1]["report"]
    assert report["total_codepoints"] == 7
    assert [(m["path"], m["index"]) for m in report["materials"]] == [
        (m["path"], m["index"]) for m in forge_request["spec"]["materials"]
    ]
    with TTFont(forge_request["output_path"]) as font:
        for key, name_id in (("family_name", 16), ("style_name", 17), ("postscript_name", 6), ("full_name", 4)):
            fallback = {16: 1, 17: 2}.get(name_id, name_id)
            assert report[key] == (font["name"].getDebugName(name_id) or font["name"].getDebugName(fallback))
        assert report["fs_type"] == font["OS/2"].fsType
    assert not list(Path(forge_request["output_path"]).parent.glob(".fpengine-*"))


@pytest.mark.parametrize("change", ["size", "mtime", "postscript", "deleted", "index"])
def test_forge_stale_material(change, run_helper, forge_request, font_dir, tmp_path):
    path = tmp_path / "Copy.ttc"
    path.write_bytes((font_dir / "T.ttc").read_bytes())
    face = read_faces(path)[0]
    material = {
        "path": str(path),
        "index": 0,
        "expect": {"postscript_name": face.postscript_name, "size": face.size, "mtime": face.mtime},
    }
    forge_request["spec"]["materials"][1] = material
    if change == "size":
        material["expect"]["size"] += 1
        expected = f"{path} changed since it was scanned (size {face.size + 1} → {face.size})."
    elif change == "mtime":
        material["expect"]["mtime"] -= 2
        expected = f"{path} changed since it was scanned (modified {face.mtime - 2:.3f} → {face.mtime:.3f})."
    elif change == "postscript":
        material["expect"]["postscript_name"] = "Old"
        expected = f"{path} face 0 is now '{face.postscript_name}', not 'Old'."
    elif change == "deleted":
        path.unlink()
        expected = f"{path}: the font file is no longer there."
    else:
        material["index"] = 5
        expected = f"{path} has no face 5 any more."
    events, code, _, _ = run_helper("forge", forge_request)
    error = events[-1]
    assert code == 3 and error["code"] == "stale_material"
    assert error["stage"] == "validate" and error["material_index"] == 1 and error["message"] == expected
    assert not Path(forge_request["output_path"]).exists()


@pytest.mark.parametrize("missing", [True, False])
def test_forge_missing_material_without_expect(missing, run_helper, forge_request, font_dir, tmp_path):
    path = tmp_path / "missing.ttf" if missing else font_dir / "T.ttc"
    forge_request["spec"]["materials"][1] = {"path": str(path), "index": 5}
    events, code, _, _ = run_helper("forge", forge_request)
    assert code == (3 if missing else 2)
    assert events[-1]["code"] == ("io_error" if missing else "bad_request")
    assert events[-1]["material_index"] == 1
    if not missing:
        assert events[-1]["stage"] is None
        assert events[-1]["message"] == f"Invalid request: spec.materials[1].index: {path} has 2 faces."


@pytest.mark.parametrize("kind", ["color", "text", "empty", "scale"])
def test_forge_unsupported_and_validate_errors(kind, run_helper, forge_request, color_font, tmp_path):
    if kind == "color":
        forge_request["spec"]["materials"][0]["path"] = str(color_font)
    elif kind == "text":
        text = tmp_path / "junk.ttf"
        text.write_bytes(b"x" * 75)
        forge_request["spec"]["materials"][0]["path"] = str(text)
    elif kind == "empty":
        forge_request["spec"]["materials"] = []
    else:
        forge_request["spec"]["materials"][0]["scale"] = 20
    events, code, _, _ = run_helper("forge", forge_request)
    assert code == 3
    assert events[-1]["code"] == ("unsupported_font" if kind in ("color", "text") else "validate")
    if kind == "color":
        assert events[-1]["message"] == "Fixture Color Regular: colour fonts are not supported"


def test_forge_glyph_limit_code(monkeypatch, inprocess, forge_request):
    from fpengine import merge

    monkeypatch.setattr(merge, "MAX_GLYPHS", 3)
    events, code, _ = inprocess("forge", forge_request)
    assert code == 3 and events[-1]["code"] == "glyph_limit"


def test_forge_internal_error(monkeypatch, inprocess, forge_request):
    from fpengine import forge

    def boom(spec):
        raise RuntimeError("boom")

    monkeypatch.setattr(forge, "plan", boom)
    events, code, _ = inprocess("forge", forge_request)
    assert code == 3 and events[-1]["code"] == "internal" and events[-1]["stage"] == "plan"
    assert events[-1]["message"] == "Unexpected error: RuntimeError: boom"
    assert "Traceback" in events[-1]["detail"]


@pytest.mark.parametrize("existing", [True, False])
def test_forge_output_is_atomic(existing, monkeypatch, inprocess, forge_request):
    from fpengine import merge

    output = Path(forge_request["output_path"])
    output.parent.mkdir()
    if existing:
        output.write_bytes(b"old verified font")

    def fail(*args):
        raise ForgeError("verify", None, "x")

    monkeypatch.setattr(merge, "verify", fail)
    events, code, _ = inprocess("forge", forge_request)
    assert code == 3 and events[-1]["code"] == "verify_failed"
    assert output.read_bytes() == b"old verified font" if existing else not output.exists()
    assert not list(output.parent.glob(".fpengine-*"))


def test_directory_sync_failure_after_rename_is_a_saved_result(monkeypatch, inprocess, forge_request):
    """The rename is the commit point: a later directory fsync failure must not report a replaced file as failed."""
    from fpengine.commands import forge as forge_command

    output = Path(forge_request["output_path"])
    output.parent.mkdir()
    output.write_bytes(b"old verified font")
    real_fsync = forge_command._fsync

    def fsync(path, *, directory=False):
        if directory:
            raise OSError(5, "Input/output error")
        real_fsync(path)

    monkeypatch.setattr(forge_command, "_fsync", fsync)
    events, code, _ = inprocess("forge", forge_request)
    assert code == 0 and events[-1]["type"] == "result"
    with TTFont(output) as font:
        assert "name" in font
    report = events[-1]["report"]
    note = (
        "The font was saved, but its folder couldn't be flushed to disk (Input/output error); "
        "if the Mac loses power soon, build it again."
    )
    assert report["issues"][-1] == {
        "code": "output_sync_failed",
        "severity": "warning",
        "material_index": None,
        "group": None,
        "message": note,
    }
    assert report["warnings"][-1] == note
    assert not list(output.parent.glob(".fpengine-*"))


def test_stray_prints_do_not_corrupt_stdout(monkeypatch, inprocess, forge_request, capsys):
    from fpengine import forge

    real = forge.plan

    def noisy(spec):
        print("noise")
        return real(spec)

    monkeypatch.setattr(forge, "plan", noisy)
    _, code, raw = inprocess("forge", forge_request)
    assert code == 0 and b"noise" not in raw and "noise" in capsys.readouterr().err


def test_forge_uses_tmpdir_and_cleans_it(monkeypatch, inprocess, forge_request, tmp_path):
    from fpengine import forge

    base = tmp_path / "a/b"
    monkeypatch.setenv("TMPDIR", str(base))
    real, seen, previous = forge.plan, [], tempfile.tempdir

    def record(spec):
        seen.append((os.listdir(base), tempfile.gettempdir()))
        return real(spec)

    monkeypatch.setattr(forge, "plan", record)
    _, code, _ = inprocess("forge", forge_request)
    assert code == 0 and len(seen) == 1
    names, directory = seen[0]
    assert len(names) == 1 and names[0].startswith(f"fpengine-{os.getpid()}-")
    assert directory == str(base / names[0])
    assert list(base.iterdir()) == [] and tempfile.tempdir == previous


def test_report_fields_and_interim_values(forge_request):
    @dataclass
    class LicenceNote:
        licence_class: str
        material_indexes: tuple[int, ...]
        text: str

    assert set(INTERIM_REPORT_FIELDS) <= {"issues", "licence_notes"}
    report = SimpleNamespace(
        total_codepoints=1,
        total_glyphs=2,
        materials=[],
        warnings=[],
        issues=[{"code": "some_issue", "severity": "warning", "material_index": 1, "group": None, "message": "t"}],
        licence_notes=[LicenceNote("apple-sla", (1,), "t")],
    )
    result = forge_report(parse_forge(forge_request), report, OutputNames("a", "b", "a-b", "a b", 0), 1.234)
    assert result["licence_notes"] == [{"class": "apple-sla", "material_indexes": [1], "text": "t"}]
    assert result["issues"] == report.issues
