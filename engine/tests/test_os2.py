from pathlib import Path

import pytest
from fontTools.feaLib.builder import addOpenTypeFeaturesFromString
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib import TTFont

from fpengine import prepare as prepare_module
from fpengine.face import READER_VERSION, read_faces
from fpengine.forge import forge
from fpengine.prepare import ensure_os2
from fpengine.spec import ForgeReport, ForgeSpec, Issue, MaterialSpec
from tests.fixtures import build_font, cps

NOTE = "has no OS/2 table; one was made from its other tables, so its embedding permissions are unknown"


def _missing_os2(path: Path, *, cff: bool = False, variable: bool = False, mac_style: int = 3) -> Path:
    build_font(path, "Fixture N", "Bold Italic", cps("xyzH"), cff=cff, variable=variable)
    with TTFont(path) as font:
        del font["OS/2"]
        font["head"].macStyle = mac_style
        font.save(path)
    return path


def _assert_issue(report: ForgeReport, index: int) -> None:
    expected = Issue("os2_synthesized", "warning", index, None, f"{report.materials[index].name}: {NOTE}")
    assert [issue for issue in report.issues if not issue.code.startswith("licence_")] == [expected]
    assert NOTE in report.materials[index].warnings
    assert expected.message in report.warnings


def test_engine_m1_missing_os2_as_main(tmp_path: Path) -> None:
    """Reference: missing base OS/2 crashes at finish with KeyError instead of producing a font."""
    face = read_faces(_missing_os2(tmp_path / "missing.ttf"))[0]
    output = tmp_path / "main.ttf"
    report = forge(ForgeSpec([MaterialSpec(face)]), output)
    with TTFont(output) as font:
        assert font["OS/2"].version >= 4
        assert set(font.getBestCmap()) == cps("xyzH")
    _assert_issue(report, 0)


def test_engine_m1_missing_os2_as_secondary(font_dir: Path, tmp_path: Path) -> None:
    """Reference: merging a secondary face without OS/2 raises a NotImplementedType TypeError."""
    a = read_faces(font_dir / "A.ttf")[0]
    face = read_faces(_missing_os2(tmp_path / "missing.ttf"))[0]
    output = tmp_path / "secondary.ttf"
    report = forge(ForgeSpec([MaterialSpec(a), MaterialSpec(face)]), output)
    with TTFont(output) as font:
        assert set(font.getBestCmap()) == cps("abc1,xyzH")
    _assert_issue(report, 1)


@pytest.mark.parametrize("mac_style,weight,selection", [(3, 700, 0x21), (0, 400, 0x40), (1, 700, 0x20), (2, 400, 0x01)])
def test_ensure_os2_field_derivation(tmp_path: Path, mac_style: int, weight: int, selection: int) -> None:
    path = _missing_os2(tmp_path / "missing.ttf", mac_style=mac_style)
    with TTFont(path) as font:
        assert ensure_os2(font)
        table = font["OS/2"]
        expected = {
            "version": 4,
            "usWeightClass": weight,
            "usWidthClass": 5,
            "fsSelection": selection,
            "sTypoAscender": 800,
            "sTypoDescender": -200,
            "sTypoLineGap": 0,
            "usWinAscent": 800,
            "usWinDescent": 200,
            "sxHeight": 700,
            "sCapHeight": 700,
            "achVendID": "NONE",
            "fsType": 0,
            "ySubscriptXSize": 650,
            "ySuperscriptXSize": 650,
            "ySubscriptYSize": 600,
            "ySuperscriptYSize": 600,
            "ySubscriptXOffset": 0,
            "ySuperscriptXOffset": 0,
            "ySubscriptYOffset": 75,
            "ySuperscriptYOffset": 350,
            "yStrikeoutSize": 50,
            "yStrikeoutPosition": 420,
            "ulCodePageRange1": 0,
            "ulCodePageRange2": 0,
            "usDefaultChar": 0,
            "usBreakChar": 32,
            "usMaxContext": 0,
            "sFamilyClass": 0,
            "xAvgCharWidth": 200,
        }
        assert {field: getattr(table, field) for field in expected} == expected
        assert set(vars(table.panose).values()) == {0}
        assert table.ulUnicodeRange1 & 1
        table.compile(font)
        assert table.usFirstCharIndex == ord("H") and table.usLastCharIndex == ord("z")


def test_ensure_os2_keeps_existing_table(font_dir: Path) -> None:
    with TTFont(font_dir / "A.ttf") as font:
        table = font["OS/2"]
        before = table.compile(font)
        fields = vars(table).copy()
        assert not ensure_os2(font)
        assert font["OS/2"] is table
        assert vars(table) == fields
        assert table.compile(font) == before


def test_missing_os2_cff_face(tmp_path: Path) -> None:
    """Reference: the CFF conversion still leaves finish without its required OS/2 table."""
    path = _missing_os2(tmp_path / "missing.otf", cff=True)
    with TTFont(path) as font:
        assert ensure_os2(font)
        assert font["OS/2"].sxHeight == 700
    face = read_faces(path)[0]
    output = tmp_path / "converted.ttf"
    report = forge(ForgeSpec([MaterialSpec(face)]), output)
    with TTFont(output) as font:
        assert "glyf" in font and "CFF " not in font
        assert set(font.getBestCmap()) == cps("xyzH")
    _assert_issue(report, 0)


def test_no_os2_bold_face_reads_as_bold(tmp_path: Path) -> None:
    """Reference reads weight 400 and applies +300 synthetic bold to an already-bold face."""
    bold = read_faces(_missing_os2(tmp_path / "bold.ttf"))[0]
    regular = read_faces(_missing_os2(tmp_path / "regular.ttf", mac_style=0))[0]
    assert bold.weight_class == 700
    assert regular.weight_class == 400
    assert READER_VERSION >= 4
    report = forge(ForgeSpec([MaterialSpec(bold)], default_weight=700), tmp_path / "out.ttf")
    assert all(issue.code != "synthetic_bold" for issue in report.issues)
    assert all("synthetic bold" not in warning for warning in report.warnings)


def test_os2_height_and_strikeout_fallbacks(tmp_path: Path) -> None:
    path = _missing_os2(tmp_path / "fallback.ttf")
    with TTFont(path) as font:
        font["glyf"]["uni0078"] = TTGlyphPen(None).glyph()
        for table in font["cmap"].tables:
            table.cmap.pop(ord("H"), None)
        font["head"].yMax, font["head"].yMin = 950, -400
        font["post"].underlineThickness = 35
        assert ensure_os2(font)
        table = font["OS/2"]
        assert table.sxHeight == table.sCapHeight == 0
        assert table.yStrikeoutPosition == 220
        assert table.yStrikeoutSize == 35
        assert table.usWinAscent == 950 and table.usWinDescent == 400


def test_variable_retry_synthesizes_os2_again_and_reports_once(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    path = _missing_os2(tmp_path / "variable.ttf", variable=True)
    with TTFont(path) as font:
        addOpenTypeFeaturesFromString(font, "feature kern { pos uni0078 uni0079 -50; } kern;")
        font.save(path)
    face = read_faces(path)[0]
    original_instance = prepare_module.instance_variable
    calls = 0

    def instance(font: TTFont, weight: int | None) -> TTFont:
        nonlocal calls
        calls += 1
        assert "OS/2" in font
        if calls == 1:
            assert "GPOS" in font
            raise ValueError("broken variable GPOS fixture")
        assert "GPOS" not in font
        return original_instance(font, weight)

    monkeypatch.setattr(prepare_module, "instance_variable", instance)
    report = forge(ForgeSpec([MaterialSpec(face)], default_weight=900), tmp_path / "out.ttf")
    assert calls == 2
    _assert_issue(report, 0)
    assert report.materials[0].warnings.count(NOTE) == 1
    assert any(warning.startswith("GPOS dropped:") for warning in report.materials[0].warnings)
