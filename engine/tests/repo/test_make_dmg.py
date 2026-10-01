"""WP-601: make-dmg.sh never replaces the last good DMG with a partial one (AGENTS.md rule 8)."""

import os
import subprocess
from pathlib import Path

import pytest

SCRIPT = Path(__file__).resolve().parents[3] / "scripts" / "make-dmg.sh"

# Stand-ins for the macOS tools: `diskutil image create` is unavailable, so the script takes the hdiutil path.
STUBS = {
    "ditto": '#!/bin/sh\ncp -R "$1" "$2"\n',
    "diskutil": "#!/bin/sh\nexit 1\n",
    "hdiutil": """#!/bin/sh
case "$1" in
  create)
    for last; do :; done
    printf 'new image' > "$last"
    [ -z "${FAIL_CREATE:-}" ] || exit 1;;
  verify) exit "${FAIL_VERIFY:-0}";;
esac
""",
}


def _run(tmp_path: Path, **env: str) -> tuple[subprocess.CompletedProcess, Path]:
    tools = tmp_path / "bin"
    tools.mkdir(exist_ok=True)
    for name, text in STUBS.items():
        (tools / name).write_text(text)
        (tools / name).chmod(0o755)
    app = tmp_path / "Font Playground.app"
    (app / "Contents").mkdir(parents=True, exist_ok=True)
    out = tmp_path / "dist" / "FontPlayground-1.0.0-arm64.dmg"
    environment = {**os.environ, "PATH": f"{tools}{os.pathsep}{os.environ['PATH']}", **env}
    result = subprocess.run(
        ["bash", str(SCRIPT), str(app), str(out)], capture_output=True, text=True, env=environment, check=False
    )
    return result, out


def test_new_dmg_replaces_the_previous_one(tmp_path: Path) -> None:
    out = tmp_path / "dist" / "FontPlayground-1.0.0-arm64.dmg"
    out.parent.mkdir()
    out.write_text("previous image")
    result, out = _run(tmp_path)
    assert result.returncode == 0, result.stderr
    assert out.read_text() == "new image"
    assert [p.name for p in out.parent.iterdir()] == [out.name]


@pytest.mark.parametrize("failure", [{"FAIL_CREATE": "1"}, {"FAIL_VERIFY": "1"}])
def test_failed_creation_keeps_the_previous_dmg(tmp_path: Path, failure: dict[str, str]) -> None:
    out = tmp_path / "dist" / "FontPlayground-1.0.0-arm64.dmg"
    out.parent.mkdir()
    out.write_text("previous image")
    result, out = _run(tmp_path, **failure)
    assert result.returncode != 0
    assert out.read_text() == "previous image"
    assert [p.name for p in out.parent.iterdir()] == [out.name]
