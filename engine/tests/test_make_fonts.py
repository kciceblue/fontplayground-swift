"""Verify the shipped synthetic font inventory as real fonts, not just its manifest."""

import json
import subprocess
import sys
import time

import pytest
from fontTools.ttLib import TTFont, TTLibError

from fpengine.face import read_faces
from fpengine.records import ranges
from fpengine.testing.fonts import FIXED_TIMESTAMP, build_font
from fpengine.testing.make_fonts import FIXTURE_FONTS, make_fonts

EXPECTED_FILES = {
    "FixtureSans-Regular.ttf",
    "FixtureSans-Bold.ttf",
    "FixtureCJK-Regular.otf",
    "FixtureHangul-Regular.ttf",
    "FixtureSerif.ttc",
    "FixtureVariable-Regular.ttf",
    "FixtureColor-Regular.ttf",
    "FixtureRestricted-Regular.ttf",
    "NotAFont.ttf",
    "fonts.json",
}


def test_make_fonts_set_and_manifest(tmp_path):
    start = time.monotonic()
    first = make_fonts(tmp_path / "first")
    assert time.monotonic() - start < 5
    second = make_fonts(tmp_path / "second")
    assert first.name == "fonts.json" and first.is_absolute()
    assert {path.name for path in first.parent.iterdir()} == EXPECTED_FILES
    assert {fixture.file for fixture in FIXTURE_FONTS} == EXPECTED_FILES - {"fonts.json"}
    assert all((first.parent / name).read_bytes() == (second.parent / name).read_bytes() for name in EXPECTED_FILES)
    data = json.loads(first.read_text())
    assert data["generator"] == "fpengine.testing.make_fonts" and data["version"] == 1
    assert len(data["fonts"]) == 9
    for fixture in data["fonts"]:
        path = first.parent / fixture["file"]
        if fixture["expect"] == "file_error:unreadable":
            assert fixture["faces"] == [] and path.read_bytes() == b"This is not a font file.\n" * 3
            assert path.stat().st_size == 75
            with pytest.raises(TTLibError):
                read_faces(path)
            continue
        assert fixture["expect"] == "faces"
        faces = read_faces(path)
        assert len(faces) == len(fixture["faces"])
        for face, expected in zip(faces, fixture["faces"], strict=True):
            for key, value in expected.items():
                assert (ranges(face.codepoints) if key == "coverage" else getattr(face, key)) == value
            with TTFont(path, fontNumber=face.index, recalcTimestamp=False) as font:
                assert font["head"].created == font["head"].modified == FIXED_TIMESTAMP
                assert font["name"].getDebugName(3) == f"{face.postscript_name};fixture"
                assert font["name"].getDebugName(5) == "Version 1.000"
                bold = face.weight_class >= 700
                assert font["OS/2"].fsSelection == (
                    (1 if face.italic else 0) | (32 if bold else 0) | (64 if not face.italic and not bold else 0)
                )
                assert font["head"].macStyle == ((1 if bold else 0) | (2 if face.italic else 0))
                if face.outline == "CFF":
                    assert font["CFF "].cff.fontNames == [face.postscript_name]
                if face.family == "Fixture Variable":
                    assert face.is_variable and face.axes == (("wght", 100.0, 400.0, 900.0),)
                    assert font["gvar"].variations
                if face.family == "Fixture Color":
                    assert "COLR" in font and "CPAL" in font and not face.supported
                    assert face.unsupported_reason == "colour fonts are not supported"
                if face.family == "Fixture Restricted":
                    assert font["OS/2"].fsType == 2
    counts = {
        entry["file"]: sum(end - start + 1 for start, end in entry["faces"][0]["coverage"])
        for entry in data["fonts"]
        if entry["faces"]
    }
    assert counts["FixtureSans-Regular.ttf"] == 240
    assert counts["FixtureCJK-Regular.otf"] == 3505
    assert counts["FixtureHangul-Regular.ttf"] == 2058


def test_make_fonts_cli(tmp_path):
    directory = tmp_path / "fonts"
    result = subprocess.run(
        [sys.executable, "-m", "fpengine.testing.make_fonts", str(directory)], capture_output=True, text=True
    )
    assert result.returncode == 0, result.stderr
    assert result.stdout == str((directory / "fonts.json").resolve()) + "\n"
    assert set(path.name for path in directory.iterdir()) == EXPECTED_FILES
    result = subprocess.run([sys.executable, "-m", "fpengine.testing.make_fonts"], capture_output=True, text=True)
    assert result.returncode == 2 and "usage:" in result.stderr and not result.stdout


def test_font_builder_supplementary_glyphs_and_combined_style(tmp_path):
    path = build_font(
        tmp_path / "supplementary.ttf", "Fixture Supplementary", "Bold Italic", [0x1F600, 65], weight=700, italic=True
    )
    with TTFont(path) as font:
        assert font.getBestCmap() == {65: "uni0041", 0x1F600: "u1F600"}
        assert font["OS/2"].fsSelection == 0x21 and font["head"].macStyle == 3
    face = read_faces(path)[0]
    assert face.weight_class == 700 and face.italic
