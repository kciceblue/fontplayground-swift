"""Keep the v1.0.0 cutover (WP-701): no code depends on the removed original app."""

import hashlib
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SCANNED_SUFFIXES = {".py", ".swift", ".sh", ".yml", ".yaml", ".toml", ".json"}
SKIPPED_DIRECTORIES = {".git", "build", ".build", ".venv", "dist"}
# spec/ holds frozen goldens; docs/ holds prose and pre-port research prototypes that nothing runs.
UNSCANNED_TOP_LEVEL = {"spec", "docs"}
ORIGINAL_APP_PATH = "reference/fontplayground-py"
ORIGINAL_APP_IMPORT = re.compile(r"^\s*(from|import)\s+fontplayground\b")


def _tracked_files() -> list[Path]:
    try:
        listed = subprocess.run(
            ["git", "-C", str(ROOT), "ls-files", "-z"], capture_output=True, check=True
        ).stdout.split(b"\0")
        return [ROOT / name.decode() for name in listed if name]
    except (OSError, subprocess.CalledProcessError):
        return [
            path
            for path in ROOT.rglob("*")
            if path.is_file() and not SKIPPED_DIRECTORIES & set(path.relative_to(ROOT).parts)
        ]


def _scanned_files() -> list[Path]:
    this_file = Path(__file__).resolve()
    return [
        path
        for path in _tracked_files()
        if (path.suffix in SCANNED_SUFFIXES or path.name == "Makefile")
        and path.relative_to(ROOT).parts[0] not in UNSCANNED_TOP_LEVEL
        and path.resolve() != this_file
        and path.is_file()
    ]


def _is_comment(line: str, path: Path) -> bool:
    stripped = line.strip()
    return stripped.startswith("#") or (path.suffix == ".swift" and stripped.startswith("//"))


def test_reference_directory_is_gone() -> None:
    assert not (ROOT / "reference").exists()


def test_no_code_references_the_reference_directory() -> None:
    files = _scanned_files()
    assert any(path.name == "Makefile" for path in files) and any(path.suffix == ".swift" for path in files)
    offending = []
    for path in files:
        for number, line in enumerate(path.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
            if _is_comment(line, path):
                continue
            if ORIGINAL_APP_PATH in line or (path.suffix == ".py" and ORIGINAL_APP_IMPORT.match(line)):
                offending.append(f"{path.relative_to(ROOT)}:{number}: {line.strip()}")
    assert offending == []


def test_frozen_fixtures_match_manifest() -> None:
    fixtures = ROOT / "spec/fixtures"
    lines = (fixtures / "FROZEN.sha256").read_text(encoding="utf-8").splitlines()
    assert lines
    for line in lines:
        digest, relative = line.split("  ", 1)
        path = fixtures / relative
        assert path.is_file(), relative
        assert hashlib.sha256(path.read_bytes()).hexdigest() == digest, relative
