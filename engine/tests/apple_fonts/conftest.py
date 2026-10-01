"""Opt-in real-file fixtures and one helper run per matrix row."""

from __future__ import annotations

import os
import sys
from dataclasses import dataclass, replace
from pathlib import Path

import pytest

from tests.apple_fonts.locate import FaceLocation, build_index, search_dirs
from tests.apple_fonts.runner import HelperRun, run_helper
from tests.apple_fonts.scenarios import BY_ID, Scenario, check_run, forge_request

_RESULTS: dict[str, dict] = {}
_CALIBRATION_ROWS: list[str] = []


def _enabled() -> bool:
    return sys.platform == "darwin" and os.environ.get("FP_APPLE_FONTS") == "1"


def pytest_collection_modifyitems(items) -> None:
    for item in items:
        if Path(item.path).is_relative_to(Path(__file__).parent):
            for marker in (pytest.mark.apple_fonts, pytest.mark.macos, pytest.mark.slow):
                item.add_marker(marker)
            if not _enabled():
                item.add_marker(pytest.mark.skip(reason="needs macOS and FP_APPLE_FONTS=1"))


@pytest.fixture(autouse=True, scope="session")
def _font_folders_untouched():
    if not _enabled():
        yield
        return
    folders = (Path.home() / "Library/Fonts", Path("/Library/Fonts"))

    def snapshot(folder):
        return (
            sorted((path.name, path.stat().st_size, path.stat().st_mtime) for path in folder.iterdir())
            if folder.exists()
            else []
        )

    before = [snapshot(folder) for folder in folders]
    yield
    assert [snapshot(folder) for folder in folders] == before, "A real font folder changed during the suite"


@pytest.fixture(scope="session")
def calibration_rows():
    return _CALIBRATION_ROWS


@pytest.fixture(scope="session")
def font_index():
    return build_index(search_dirs())


@dataclass
class ScenarioRun:
    scenario: Scenario
    run: HelperRun
    locations: list[FaceLocation]
    tmpdir: Path

    @property
    def output(self) -> Path:
        return self.tmpdir / "out.ttf"


@pytest.fixture(scope="session")
def scenario_run(font_index, tmp_path_factory):
    cache = {}
    factor = float(os.environ.get("FP_APPLE_FONTS_TIME_FACTOR", "1"))

    def execute(scenario_id: str, *, style: str | None = None) -> ScenarioRun:
        scenario = BY_ID[scenario_id]
        if style is not None:
            scenario = replace(scenario, style=style)
        key = f"{scenario.id}/{scenario.style}"
        if key in cache:
            return cache[key]
        for name in scenario.materials:
            if name not in font_index.faces:
                _RESULTS[key] = {"outcome": f"SKIP not installed: {name}", "scenario": scenario}
                pytest.skip(f"not installed: {name}")
        locations = [font_index.faces[name] for name in scenario.materials]
        tmpdir = tmp_path_factory.mktemp(f"{scenario.id}-{scenario.style}")
        run = run_helper(
            "forge", forge_request(scenario, locations, tmpdir), tmpdir=tmpdir, timeout_s=scenario.budget_s * factor
        )
        record = cache[key] = ScenarioRun(scenario, run, locations, tmpdir)
        _RESULTS[key] = {"outcome": "ran", "scenario": scenario, "run": run}
        return record

    return execute


@pytest.fixture(scope="session")
def checked_scenario(scenario_run, font_index):
    factor = float(os.environ.get("FP_APPLE_FONTS_TIME_FACTOR", "1"))
    checked = set()

    def check(scenario_id: str, *, style: str | None = None) -> ScenarioRun:
        record = scenario_run(scenario_id, style=style)
        key = f"{record.scenario.id}/{record.scenario.style}"
        if key not in checked:
            try:
                check_run(record.scenario, record.run, record.locations, font_index, record.output, factor)
                if scenario_id == "AF-31" and style is None:
                    bold = check(scenario_id, style="Bold")
                    assert record.run.result["postscript_name"] != bold.run.result["postscript_name"]
            except BaseException:
                _RESULTS[key]["outcome"] = "FAIL"
                raise
            checked.add(key)
            _RESULTS[key]["outcome"] = "ok" if record.scenario.expect == "ok" else record.scenario.expect
        return record

    return check


def pytest_terminal_summary(terminalreporter) -> None:
    if not _RESULTS:
        return
    terminalreporter.section("Apple-font scenario matrix")
    terminalreporter.write_line(
        "Scenario       Outcome                    Glyphs    Chars   Seconds     MB  Budget s/MB"
    )
    factor = float(os.environ.get("FP_APPLE_FONTS_TIME_FACTOR", "1"))
    for key, item in sorted(_RESULTS.items()):
        scenario = item["scenario"]
        run = item.get("run")
        if run is None:
            terminalreporter.write_line(f"{key:14} {item['outcome']}")
            continue
        report = run.result or {}
        terminalreporter.write_line(
            f"{key:14} {item['outcome']:26} {report.get('total_glyphs', '-'):>7} "
            f"{report.get('total_codepoints', '-'):>8} "
            f"{run.wall_s:9.2f} {run.peak_rss_mb:6.1f}  {scenario.budget_s * factor:g}/{scenario.budget_rss_mb}"
        )

    if _CALIBRATION_ROWS:
        terminalreporter.section("Glyph-estimate calibration")
        for row in _CALIBRATION_ROWS:
            terminalreporter.write_line(row)
