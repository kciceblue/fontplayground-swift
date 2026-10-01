"""WP-203: the helper runtime and its manifest switch into place together, or not at all."""

import subprocess
from pathlib import Path

import pytest

SCRIPT = Path(__file__).resolve().parents[3] / "scripts" / "publish-helper-runtime.sh"


def _runtime(path: Path, marker: str) -> Path:
    (path / "bin").mkdir(parents=True)
    (path / "bin" / "python3").write_text(marker)
    return path


def _pair(out: Path) -> tuple[str | None, str | None]:
    runtime, manifest = out / "fpengine" / "bin" / "python3", out / "fpengine-runtime.json"
    return (
        runtime.read_text() if runtime.exists() else None,
        manifest.read_text() if manifest.exists() else None,
    )


def _leftovers(out: Path) -> list[str]:
    return sorted(p.name for p in out.iterdir() if p.name not in ("fpengine", "fpengine-runtime.json", "stage"))


def _run(*args: object) -> subprocess.CompletedProcess:
    return subprocess.run(["bash", str(SCRIPT), *map(str, args)], capture_output=True, text=True, check=False)


@pytest.mark.parametrize("previous", [False, True])
def test_publish_switches_runtime_and_manifest_together(tmp_path: Path, previous: bool) -> None:
    out = tmp_path / "helper"
    out.mkdir()
    if previous:
        _runtime(out / "fpengine", "old")
        (out / "fpengine-runtime.json").write_text("old")
    runtime = _runtime(out / "stage" / "fpengine", "new")
    manifest = out / "stage" / "manifest.json"
    manifest.write_text("new")
    result = _run(out, runtime, manifest)
    assert result.returncode == 0, result.stderr
    assert _pair(out) == ("new", "new")
    assert _leftovers(out) == [] and not runtime.exists()


def test_publish_with_missing_manifest_changes_nothing(tmp_path: Path) -> None:
    out = tmp_path / "helper"
    _runtime(out / "fpengine", "old")
    (out / "fpengine-runtime.json").write_text("old")
    runtime = _runtime(out / "stage" / "fpengine", "new")
    result = _run(out, runtime, out / "stage" / "missing.json")
    assert result.returncode == 1
    assert _pair(out) == ("old", "old") and _leftovers(out) == []


# Each state is what an interrupted publish leaves behind after one more of its renames.
INTERRUPTED = {
    "journal_written": ["runtime", "manifest", "new_manifest"],
    "runtime_moved_aside": ["old_runtime", "manifest", "new_manifest"],
    "both_moved_aside": ["old_runtime", "old_manifest", "new_manifest"],
    "new_runtime_in_place": ["new_runtime", "old_runtime", "old_manifest", "new_manifest"],
    "new_manifest_in_place": ["new_runtime", "old_runtime", "old_manifest", "new_manifest_final"],
}


@pytest.mark.parametrize("state", INTERRUPTED)
def test_recover_restores_the_previous_pair_after_an_interrupted_publish(tmp_path: Path, state: str) -> None:
    out = tmp_path / "helper"
    out.mkdir()
    parts = INTERRUPTED[state]
    if "runtime" in parts:
        _runtime(out / "fpengine", "old")
    if "old_runtime" in parts:
        _runtime(out / ".fpengine.old", "old")
    if "new_runtime" in parts:
        _runtime(out / "fpengine", "new")
    if "manifest" in parts:
        (out / "fpengine-runtime.json").write_text("old")
    if "old_manifest" in parts:
        (out / ".fpengine-runtime.json.old").write_text("old")
    if "new_manifest" in parts:
        (out / ".fpengine-runtime.json.new").write_text("new")
    if "new_manifest_final" in parts:
        (out / "fpengine-runtime.json").write_text("new")
    (out / ".publish-journal").write_text("1 1\n")
    result = _run("--recover", out)
    assert result.returncode == 0, result.stderr
    assert _pair(out) == ("old", "old") and _leftovers(out) == []


def test_recover_removes_a_half_published_first_runtime(tmp_path: Path) -> None:
    out = tmp_path / "helper"
    _runtime(out / "fpengine", "new")
    (out / ".fpengine-runtime.json.new").write_text("new")
    (out / ".publish-journal").write_text("0 0\n")
    assert _run("--recover", out).returncode == 0
    assert _pair(out) == (None, None) and _leftovers(out) == []


def test_recover_after_commit_only_removes_backups(tmp_path: Path) -> None:
    out = tmp_path / "helper"
    _runtime(out / "fpengine", "new")
    _runtime(out / ".fpengine.old", "old")
    (out / "fpengine-runtime.json").write_text("new")
    (out / ".fpengine-runtime.json.old").write_text("old")
    assert _run("--recover", out).returncode == 0
    assert _pair(out) == ("new", "new") and _leftovers(out) == []
