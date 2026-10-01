import pytest
from fontTools.ttLib import TTFont

from tests.apple_fonts.calibration import CALIBRATION, GLYPH_WARN, MAX_GLYPHS, estimate

pytestmark = [pytest.mark.apple_fonts, pytest.mark.macos, pytest.mark.slow]


def test_glyph_estimate_calibration(checked_scenario, calibration_rows):
    large_errors = []
    for scenario_id in CALIBRATION:
        record = checked_scenario(scenario_id)
        glyph_counts, cmap_sizes = [], []
        for location in record.locations:
            with TTFont(location.path, fontNumber=location.index, lazy=True) as font:
                glyph_counts.append(font["maxp"].numGlyphs)
                cmap_sizes.append(len(font.getBestCmap()))
        report = record.run.result
        predicted = estimate(glyph_counts, cmap_sizes, [material["codepoints"] for material in report["materials"]])
        error = (predicted - report["total_glyphs"]) / report["total_glyphs"]
        row = f"{scenario_id}: estimated {predicted}, actual {report['total_glyphs']}, error {error:+.3%}"
        calibration_rows.append(row)
        print(row)
        if report["total_glyphs"] >= 30_000:
            large_errors.append(error)
            assert -0.18 <= error <= 0.22, (scenario_id, error)
        if scenario_id == "AF-19":
            assert abs(error) <= 0.10
    assert large_errors and GLYPH_WARN <= MAX_GLYPHS * (1 + min(large_errors))
