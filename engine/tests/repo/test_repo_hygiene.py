"""Keep the development workflow reproducible on macOS."""

import re
import subprocess
import tomllib
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[3]


def _make(directory: Path, *arguments: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["make", "-C", str(directory), "-f", str(ROOT / "Makefile"), *arguments],
        capture_output=True,
        text=True,
        check=False,
    )


def _git(directory: Path, *arguments: str) -> None:
    subprocess.run(
        [
            "git",
            "-C",
            str(directory),
            "-c",
            "user.name=test",
            "-c",
            "user.email=test@example.invalid",
            "-c",
            "commit.gpgsign=false",
            "-c",
            "core.hooksPath=/dev/null",
            *arguments,
        ],
        capture_output=True,
        text=True,
        check=True,
    )


def _pyproject() -> dict:
    return tomllib.loads((ROOT / "engine/pyproject.toml").read_text())


def test_make_targets_match_testing_md() -> None:
    testing = (ROOT / "docs/testing.md").read_text()
    target_section = testing.split("## 1.", 1)[1].split("## 2.", 1)[0]
    documented = set(re.findall(r"^\| `make ([a-z][a-z0-9-]*)` \|", target_section, re.MULTILINE))
    implemented = set(re.findall(r"^([a-z][a-z0-9-]*):(?!=)", (ROOT / "Makefile").read_text(), re.MULTILINE))
    assert documented
    assert implemented == documented


def test_conformance_check_detects_fixture_drift(tmp_path: Path) -> None:
    fixture_dir = tmp_path / "spec/fixtures"
    fixture_dir.mkdir(parents=True)
    fixture = fixture_dir / "a.json"
    fixture.write_text("{}\n")
    _git(tmp_path, "init")
    _git(tmp_path, "add", "spec/fixtures/a.json")
    _git(tmp_path, "commit", "-m", "Initial fixture")

    result = _make(tmp_path, "conformance-check", "UV=/usr/bin/true")
    assert result.returncode == 0, result.stdout + result.stderr

    fixture.write_text('{"changed": true}\n')
    result = _make(tmp_path, "conformance-check", "UV=/usr/bin/true")
    assert result.returncode != 0, "Changed tracked fixtures must fail conformance-check"

    _git(tmp_path, "restore", "spec/fixtures/a.json")
    (fixture_dir / "b.json").write_text("{}\n")
    result = _make(tmp_path, "conformance-check", "UV=/usr/bin/true")
    assert result.returncode != 0, "New untracked fixtures must fail conformance-check"
    assert "b.json" in result.stdout + result.stderr


def test_tooling_m1_setup_explains_missing_uv() -> None:
    result = _make(ROOT, "setup", "UV=/nonexistent/uv")
    assert result.returncode != 0
    assert "uv not found" in result.stderr
    assert "brew install uv" in result.stderr


def test_tooling_m1_python_version_is_pinned() -> None:
    assert (ROOT / ".python-version").read_text().strip() == "3.12"
    assert _pyproject()["project"]["requires-python"] == ">=3.12"


@pytest.mark.parametrize("target", ["setup", "test", "app"])
def test_make_refuses_other_platforms(target: str, tmp_path: Path) -> None:
    """ADR-0014: one clear error instead of a confusing tool failure off macOS."""
    result = _make(tmp_path, target, "UNAME_S=Linux")
    assert result.returncode == 2, result.stdout + result.stderr
    assert "macOS only" in result.stderr


def test_tooling_17_engine_pyproject_hygiene() -> None:
    pyproject = _pyproject()
    project = pyproject["project"]
    assert project["license"] == "MIT"
    assert "scripts" not in project
    assert "gui-scripts" not in project
    assert set(project["dependencies"]) == {"fonttools[unicode]>=4.65", "skia-pathops>=0.9"}
    dev_names = {re.split(r"[<>=!~;\[]", item, maxsplit=1)[0].strip() for item in pyproject["dependency-groups"]["dev"]}
    assert {"pytest", "jsonschema", "ruff"} <= dev_names
    assert pyproject["build-system"]["build-backend"] == "uv_build"
    assert "ruff" not in pyproject.get("tool", {})


def test_tooling_6_dev_docs_have_no_windows_only_commands() -> None:
    readme = (ROOT / "README.md").read_text()
    development = (ROOT / "docs/development.md").read_text()
    for name, content in [("README.md", readme), ("docs/development.md", development)]:
        for command in ["\\Scripts\\", ".venv\\", "run.bat", "pip install -e .[dev]"]:
            assert command not in content, f"{name} includes a Windows-only or unquoted command: {command}"
    assert "docs/development.md" in readme
    assert "make setup" in development
    assert "uv" in development


def test_tooling_4_ci_runs_the_macos_job() -> None:
    workflow = (ROOT / ".github/workflows/ci.yml").read_text()
    section = workflow.split("\njobs:\n", 1)[1]
    jobs = dict(re.findall(r"^  ([a-z]+):\n(.*?)(?=^  [a-z]+:\n|\Z)", section, re.MULTILINE | re.DOTALL))
    assert set(jobs) == {"macos"}, "CI runs on macOS only (ADR-0014)"
    macos = jobs["macos"]
    assert "runs-on: [self-hosted, macOS, ARM64, kcice-ci, kcice-build]" in macos
    for command in ["make setup", "make lint", "make test", "make app", "make self-test"]:
        assert f"run: {command}\n" in macos
    # Everything after setup must work offline (AGENTS.md rule 6).
    for command in ["make lint", "make test"]:
        step = macos.split(f"run: {command}\n", 1)[1].split("- ", 1)[0]
        assert 'UV_OFFLINE: "1"' in step, command


def test_kit_is_foundation_only() -> None:
    forbidden = {"AppKit", "SwiftUI", "CoreText", "CoreGraphics", "Cocoa", "UIKit", "Combine"}
    package = ROOT / "Packages/FontPlaygroundKit"
    files = [
        path
        for path in package.rglob("*.swift")
        if not any(part.startswith(".") for part in path.relative_to(package).parts)
    ]
    assert files, "The Foundation package must contain Swift sources"
    for path in files:
        for number, line in enumerate(path.read_text().splitlines(), 1):
            code = line.split("//", 1)[0].strip()
            imported = re.search(r"\bimport\s+(?:(?:typealias|struct|class|enum|protocol|let|var|func)\s+)?(\w+)", code)
            if imported is None:
                continue
            location = f"{path.relative_to(ROOT)}:{number}"
            assert imported.group(1) not in forbidden, f"{location}: UI and CoreText code goes in FontPlaygroundMacKit"
