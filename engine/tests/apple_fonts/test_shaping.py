import pytest

pytestmark = [pytest.mark.apple_fonts, pytest.mark.macos, pytest.mark.slow]


def test_damascus_shapes_like_source(checked_scenario):
    checked_scenario("AF-15")


def test_kohinoor_shapes_like_source(checked_scenario):
    checked_scenario("AF-16")


def test_helvetica_neue_kerning_width(checked_scenario):
    checked_scenario("AF-22")


def test_hangul_beyond_format4_maps(checked_scenario):
    checked_scenario("AF-20")
