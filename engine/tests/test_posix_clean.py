import importlib.util
import re
import tempfile
from pathlib import Path

import pytest

from fpengine.face import read_faces
from fpengine.forge import forge
from fpengine.spec import ForgeSpec, MaterialSpec

ENGINE = Path(__file__).resolve().parents[1]
SOURCES = ENGINE / "src" / "fpengine"
WINDOWS_ONLY = [
    r"[A-Za-z]:\\\\",
    r"\bWINDIR\b",
    r"\bLOCALAPPDATA\b",
    r"\bwinreg\b",
    r"\bwindll\b",
    r"os\.startfile",
    r"PureWindowsPath",
    r"sys\.platform\s*==\s*[\"']win32",
    r"platform\.startswith\([\"']win",
]


def test_tooling_3_engine_sources_are_posix_clean() -> None:
    for path in SOURCES.rglob("*.py"):
        source = path.read_text(encoding="utf-8")
        for pattern in WINDOWS_ONLY:
            assert re.search(pattern, source) is None, f"{path}: {pattern}"
    assert importlib.util.find_spec("fpengine.paths") is None


def test_tooling_18_engine_has_no_discovery_or_cache_io() -> None:
    for module in ("scanner", "paths", "cache", "catalog"):
        assert importlib.util.find_spec(f"fpengine.{module}") is None
    source = (SOURCES / "records.py").read_text(encoding="utf-8")
    for operation in ("open(", ".write_text(", ".read_text(", "json.dump(", ".lower()"):
        assert operation not in source


def test_tooling_18_read_faces_keeps_the_given_path(font_dir: Path, tmp_path: Path) -> None:
    link = tmp_path / "Mixed Case Link.TTF"
    link.symlink_to(font_dir / "A.ttf")
    face = read_faces(link)[0]
    assert face.path == str(link)
    assert face.key == (str(link), 0)


def test_tooling_23_forge_temp_files_live_in_tmpdir(
    font_dir: Path, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    helper_tmp = tmp_path / "helper-tmp"
    helper_tmp.mkdir()
    monkeypatch.setenv("TMPDIR", str(helper_tmp))
    # TOOLING-23: each helper starts with an uncached temporary-directory choice.
    monkeypatch.setattr(tempfile, "tempdir", None)
    observed: list[Path] = []

    def progress(stage: str, fraction: float) -> None:
        if stage == "merge":
            entries = list(helper_tmp.iterdir())
            assert len(entries) == 1
            assert entries[0].is_dir() and entries[0].name.startswith("fontplayground-")
            observed.extend(entries)

    face = read_faces(font_dir / "A.ttf")[0]
    forge(ForgeSpec(materials=[MaterialSpec(face)]), tmp_path / "forged.ttf", progress=progress)
    assert len(observed) == 1
    assert list(helper_tmp.iterdir()) == []


def test_engine_is_qt_free_and_renamed() -> None:
    imported_reference_or_qt = re.compile(
        r"^\s*(from|import)\s+(fontplayground|PySide6|shiboken6|pytestqt)\b", re.MULTILINE
    )
    for directory in (ENGINE / "src", ENGINE / "tests"):
        for path in directory.rglob("*.py"):
            assert imported_reference_or_qt.search(path.read_text(encoding="utf-8")) is None, str(path)
