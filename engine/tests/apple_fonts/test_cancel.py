import pytest

from tests.apple_fonts.runner import run_helper
from tests.apple_fonts.scenarios import BY_ID, forge_request

pytestmark = [pytest.mark.apple_fonts, pytest.mark.macos, pytest.mark.slow]


def test_sigterm_during_prepare(font_index, tmp_path):
    scenario = BY_ID["AF-02"]
    name = scenario.materials[0]
    if name not in font_index.faces:
        pytest.skip(f"not installed: {name}")
    run = run_helper(
        "forge",
        forge_request(scenario, [font_index.faces[name]], tmp_path),
        tmpdir=tmp_path,
        timeout_s=30,
        cancel_after_s=5.0,
    )
    assert run.returncode == 143, (run.returncode, run.stderr_tail)
    assert not run.timed_out and run.wall_s <= 7.5
    assert not any(event["type"] in {"result", "error"} for event in run.events)
    progress = [event for event in run.events if event["type"] == "progress"]
    assert progress and progress[-1]["stage"] == "prepare"
    assert list((tmp_path / "helper-tmp").iterdir()) == []
    assert not (tmp_path / "out.ttf").exists()
