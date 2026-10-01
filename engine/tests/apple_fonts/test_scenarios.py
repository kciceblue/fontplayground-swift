import pytest

from tests.apple_fonts.scenarios import BY_ID, FINDING_PROOFS, SCENARIOS

pytestmark = [pytest.mark.apple_fonts, pytest.mark.macos, pytest.mark.slow]


@pytest.mark.parametrize("scenario", SCENARIOS, ids=lambda scenario: scenario.id)
def test_scenario(scenario, checked_scenario):
    checked_scenario(scenario.id)


@pytest.mark.parametrize("finding", FINDING_PROOFS)
def test_engine_finding(finding, checked_scenario):
    for scenario_id in FINDING_PROOFS[finding]:
        try:
            checked_scenario(scenario_id)
        except pytest.skip.Exception:
            if not BY_ID[scenario_id].optional:
                pytest.fail(f"{finding} requires {scenario_id}, whose system font is missing")
