"""ENGINE-4: outline failures keep uniform metrics and surface complete report notes."""

import re

import pathops
from fontTools.ttLib import TTFont

from fpengine.face import read_faces
from fpengine.forge import forge
from fpengine.prepare import prepare
from fpengine.spec import ForgeSpec, Issue, MaterialSpec
from fpengine.synth_bold import MAX_DELTA, embolden
from tests.fixtures import build_font, cps


def _bold_fixture(tmp_path, text="ab"):
    path = build_font(tmp_path / "bold.ttf", "Bold Fixture", "Regular", cps(text))
    return read_faces(path)[0]


def _assert_bold_glyph(font, name):
    glyph = font["glyf"][name]
    glyph.recalcBounds(font["glyf"])
    assert glyph.xMin == 50
    assert abs(glyph.xMax - 210) <= 1
    assert font["hmtx"][name] == (260, 50)


def test_engine_4_pathops_failure_keeps_glyph(tmp_path, monkeypatch):
    """Reference propagates PathOpsError and aborts prepare on the first bad glyph."""
    face = _bold_fixture(tmp_path)
    real_op = pathops.op
    calls = 0

    def fail_first_glyph(*args, **kwargs):
        nonlocal calls
        calls += 1
        if calls <= 2:
            raise pathops.PathOpsError("injected union failure")
        return real_op(*args, **kwargs)

    monkeypatch.setattr(pathops, "op", fail_first_glyph)
    part = prepare(MaterialSpec(face), face.codepoints, 1000, 700, 1.0, tmp_path, 7)
    with TTFont(part.path) as font:
        glyph = font["glyf"][".notdef"]
        glyph.recalcBounds(font["glyf"])
        assert glyph.numberOfContours == 1
        assert len(glyph.coordinates) == 4
        assert (glyph.xMin, glyph.xMax) == (80, 180)
        assert font["hmtx"][".notdef"] == (260, 80)
        _assert_bold_glyph(font, "uni0061")
        _assert_bold_glyph(font, "uni0062")
        assert font["hhea"].advanceWidthMax == 260
    assert calls == 4
    note = "1 of 3 glyphs could not be made bolder and keep their regular outline (.notdef)"
    assert part.warnings == ["synthetic bold (+300)", note]
    assert part.issues == [
        Issue("synthetic_bold", "warning", 7, None, f"{face.display_name}: synthetic bold (+300)"),
        Issue("bold_glyphs_skipped", "warning", 7, None, f"{face.display_name}: {note}"),
    ]
    assert part.bold_added_bytes > 0


def test_engine_4_pathops_retry_on_simplified_paths(tmp_path, monkeypatch):
    """Reference aborts before a simplified-path retry can recover the outline."""
    face = _bold_fixture(tmp_path)
    real_op = pathops.op
    calls = 0

    def fail_first_attempt(*args, **kwargs):
        nonlocal calls
        calls += 1
        if calls % 2:
            raise pathops.PathOpsError("injected first-attempt failure")
        return real_op(*args, **kwargs)

    monkeypatch.setattr(pathops, "op", fail_first_attempt)
    part = prepare(MaterialSpec(face), face.codepoints, 1000, 700, 1.0, tmp_path, 0)
    assert calls == 6
    with TTFont(part.path) as font:
        for name in (".notdef", "uni0061", "uni0062"):
            _assert_bold_glyph(font, name)
    assert part.warnings == ["synthetic bold (+300)"]
    assert part.issues == [Issue("synthetic_bold", "warning", 0, None, f"{face.display_name}: synthetic bold (+300)")]


def test_engine_4_all_glyphs_fail(tmp_path, monkeypatch):
    """Reference fails the forge at prepare when pathops cannot union an outline."""
    face = _bold_fixture(tmp_path, "abcdefg")

    def fail_every_union(*args, **kwargs):
        raise pathops.PathOpsError("injected permanent failure")

    monkeypatch.setattr(pathops, "op", fail_every_union)
    output = tmp_path / "forged.ttf"
    report = forge(ForgeSpec([MaterialSpec(face)], default_weight=700), output)
    note = (
        "8 of 8 glyphs could not be made bolder and keep their regular outline "
        "(.notdef, uni0061, uni0062, uni0063, uni0064, …)"
    )
    message = f"{report.materials[0].name}: {note}"
    skipped = [issue for issue in report.issues if issue.code == "bold_glyphs_skipped"]
    assert skipped == [Issue("bold_glyphs_skipped", "warning", 0, None, message)]
    assert note in report.materials[0].warnings
    assert message in report.warnings
    with TTFont(output) as font:
        assert set(font.getBestCmap()) == cps("abcdefg")
        assert len(font.getGlyphOrder()) == 8
        assert all(advance == 260 for advance, _ in font["hmtx"].metrics.values())


def test_synthetic_bold_issue_and_legacy_warning(font_dir, tmp_path):
    face = read_faces(font_dir / "A.ttf")[0]
    part = prepare(MaterialSpec(face), face.codepoints, 1000, 700, 1.0, tmp_path, 0)
    assert part.warnings == ["synthetic bold (+300)"]
    assert part.issues == [Issue("synthetic_bold", "warning", 0, None, f"{face.display_name}: synthetic bold (+300)")]
    assert part.bold_added_bytes > 0


def test_engine_4_bold_size_doubled_warning(tmp_path, font_dir):
    """Reference silently doubles outline-heavy output size when applying synthetic bold."""
    path = build_font(tmp_path / "large.ttf", "Large Bold Fixture", "Regular", set(range(0x4E00, 0x4E00 + 300)))
    face = read_faces(path)[0]
    report = forge(ForgeSpec([MaterialSpec(face)], default_weight=700), tmp_path / "large-forged.ttf")
    issues = [issue for issue in report.issues if issue.code == "bold_size_doubled"]
    assert len(issues) == 1
    issue = issues[0]
    assert (issue.severity, issue.material_index, issue.group) == ("warning", 0, None)
    note = issue.message.removeprefix(f"{report.materials[0].name}: ")
    assert re.match(
        r"^synthetic bold more than doubled the file size \(\d+ KB without it, \d+ KB with it\); "
        r"a heavier weight of this font",
        note,
    )
    assert note.endswith("a heavier weight of this font, if you have one, gives a smaller, better-looking result")
    assert report.materials[0].warnings[-1] == note
    assert issue.message in report.warnings
    small = read_faces(font_dir / "A.ttf")[0]
    small_report = forge(ForgeSpec([MaterialSpec(small)], default_weight=700), tmp_path / "small-forged.ttf")
    assert all(issue.code != "bold_size_doubled" for issue in small_report.issues)


def test_bold_result(font_dir):
    with TTFont(font_dir / "A.ttf") as font:
        result = embolden(font, 300)
        assert result.delta == 300
        assert result.emboldened == 6
        assert result.skipped == []
        assert result.added_bytes > 0
    with TTFont(font_dir / "A.ttf") as font:
        capped = embolden(font, 900)
        assert capped.delta == MAX_DELTA == 500
        assert capped.emboldened == 6
        assert capped.skipped == []
        assert capped.added_bytes > 0
