"""Synthetic ENGINE-1 and N-1 regressions; no installed font files are needed."""

import struct
from pathlib import Path

import pytest
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib import TTFont, newTable
from fontTools.ttLib.tables._c_m_a_p import CmapSubtable

from fpengine.face import read_faces
from fpengine.forge import forge
from fpengine.prepare import FORMAT4_MAX_BYTES, build_unicode_cmap, prepare
from fpengine.spec import ForgeError, ForgeSpec, MaterialSpec
from tests.fixtures import build_font, cps, glyph_name


def _subtable(platform: int, encoding: int, format_number: int, mapping: dict[int, str]) -> CmapSubtable:
    table = CmapSubtable.newSubtable(format_number)
    table.platformID, table.platEncID, table.language = platform, encoding, 0
    table.cmap = mapping
    return table


def _rectangle_builder(order: list[str]) -> FontBuilder:
    builder = FontBuilder(1000, isTTF=True)
    builder.setupGlyphOrder(order)
    glyphs = {}
    for name in order:
        pen = TTGlyphPen(None)
        pen.moveTo((50, 0))
        pen.lineTo((150, 0))
        pen.lineTo((150, 700))
        pen.lineTo((50, 700))
        pen.closePath()
        glyphs[name] = pen.glyph()
    builder.setupGlyf(glyphs)
    builder.setupHorizontalMetrics({name: (200, 50) for name in order})
    builder.setupHorizontalHeader(ascent=800, descent=-200)
    builder.setupNameTable({"familyName": "Cmap Fixture", "styleName": "Regular"})
    builder.setupPost()
    return builder


def _save_fixture(builder: FontBuilder, path: Path) -> Path:
    builder.setupOS2(sTypoAscender=800, sTypoDescender=-200, usWinAscent=800, usWinDescent=200, fsType=0)
    builder.save(str(path))
    return path


@pytest.fixture
def overflow_font(tmp_path: Path) -> Path:
    mapping = {0x4E00 + 2 * k: glyph_name(0x4E00 + 2 * k) for k in range(8500)}
    builder = _rectangle_builder([".notdef", *mapping.values()])
    # N-1: setupCharacterMap itself overflows format 4, so construct only format 12.
    builder.font["cmap"] = newTable("cmap")
    builder.font["cmap"].tableVersion = 0
    builder.font["cmap"].tables = [_subtable(3, 10, 12, mapping)]
    return _save_fixture(builder, tmp_path / "overflow.ttf")


@pytest.mark.parametrize("platform,encoding,format_number", [(0, 1, 4), (0, 0, 4), (0, 3, 12), (0, 4, 12)])
@pytest.mark.parametrize("under_a", [False, True], ids=["alone", "under-A"])
def test_engine_1_mac_unicode_cmap(tmp_path, font_dir, platform, encoding, format_number, under_a):
    """Reference loses Apple's (0,1)/(0,0) format 4 and (0,3) format 12 at verify."""
    codepoints = cps("xyz") | ({0x1F600} if format_number == 12 else set())
    path = build_font(tmp_path / "apple.ttf", "Apple Cmap Fixture", "Regular", codepoints)
    with TTFont(path) as font:
        font["cmap"].tables = [_subtable(platform, encoding, format_number, dict(font.getBestCmap()))]
        font.save(path)
    face = read_faces(path)[0]
    faces = [read_faces(font_dir / "A.ttf")[0], face] if under_a else [face]
    output = tmp_path / "forged.ttf"
    report = forge(ForgeSpec([MaterialSpec(face) for face in faces]), output)
    expected = set().union(*(face.codepoints for face in faces))
    with TTFont(output) as font:
        assert set(font.getBestCmap()) == expected
    assert report.total_codepoints == len(expected)
    assert [issue for issue in report.issues if not issue.code.startswith("licence_")] == []


@pytest.mark.parametrize("assigned", [cps("xyz"), cps("xyz") | {0x1F600}, set()], ids=["BMP", "full", "empty"])
def test_prepared_part_cmap_is_windows_unicode(tmp_path, assigned):
    path = build_font(tmp_path / "source.ttf", "Cmap Fixture", "Regular", cps("xyz") | {0x1F600})
    with TTFont(path) as font:
        font["cmap"].tables = [_subtable(0, 3, 12, dict(font.getBestCmap()))]
        font.save(path)
    face = read_faces(path)[0]
    part = prepare(MaterialSpec(face), assigned, 1000, None, 1.0, tmp_path, 0)
    with TTFont(part.path) as font:
        tables = font["cmap"].tables
        expected = [(3, 1, 4), (3, 10, 12)] if 0x1F600 in assigned else [(3, 1, 4)]
        assert [(table.platformID, table.platEncID, table.format) for table in tables] == expected
        assert all(table.language == 0 for table in tables)
        assert font["cmap"].tableVersion == 0
        assert set(tables[0].cmap) == {cp for cp in assigned if cp <= 0xFFFF}
        if 0x1F600 in assigned:
            assert set(tables[1].cmap) == assigned
        assert set(font.getBestCmap()) == assigned
    assert part.issues == []


def test_uvs_subtable_kept_as_0_5(tmp_path):
    builder = _rectangle_builder([".notdef", "uni0061", "uni0061.alt", "uniFE00"])
    builder.setupCharacterMap(
        {0x61: "uni0061", 0xFE00: "uniFE00"},
        uvs=[(0x61, 0xFE00, "uni0061.alt"), (0x61, 0xFE01, None)],
    )
    path = _save_fixture(builder, tmp_path / "uvs.ttf")
    face = read_faces(path)[0]
    output = tmp_path / "forged.ttf"
    forge(ForgeSpec([MaterialSpec(face)]), output)
    with TTFont(output) as font:
        variation_tables = [table for table in font["cmap"].tables if table.format == 14]
        assert len(variation_tables) == 1
        table = variation_tables[0]
        assert (table.platformID, table.platEncID, table.format) == (0, 5, 14)
        assert table.uvsDict[0xFE00] == [(0x61, "uni0061.alt")]
        assert 0xFE01 not in table.uvsDict  # The unassigned selector is rightly removed by subsetting.


def test_cmap_format4_overflow_keeps_every_character(overflow_font, tmp_path):
    """N-1: reference fails at finish with 'H' format requires 0 <= number <= 65535."""
    face = read_faces(overflow_font)[0]
    output = tmp_path / "forged.ttf"
    report = forge(ForgeSpec([MaterialSpec(face)]), output)
    with TTFont(output) as font:
        tables = font["cmap"].tables
        assert [(table.platformID, table.platEncID, table.format) for table in tables] == [(3, 1, 4), (3, 10, 12)]
        m = len(tables[0].cmap)
        assert 0 < m < 8500
        assert set(tables[0].cmap) == {0x4E00 + 2 * k for k in range(m)}
        assert len(tables[0].compile(font)) <= FORMAT4_MAX_BYTES
        assert set(tables[1].cmap) == set(face.codepoints) == set(font.getBestCmap())
    assert report.total_codepoints == 8500
    issues = [issue for issue in report.issues if not issue.code.startswith("licence_")]
    assert len(issues) == 1
    issue = issues[0]
    assert (issue.code, issue.severity, issue.material_index, issue.group) == (
        "cmap_format4_partial",
        "warning",
        None,
        None,
    )
    note = (
        f"{8500 - m:,} characters from U+{0x4E00 + 2 * m:04X} up are only in the font's full Unicode character map; "
        "current apps read it, but very old apps that read only the basic map will not show them"
    )
    assert issue.message == note
    assert report.warnings[-1] == note
    assert report.materials[0].warnings == []
    assert note in report.as_text()


def test_build_unicode_cmap_prefix_is_maximal(overflow_font):
    with TTFont(overflow_font) as font:
        best = font.getBestCmap()
        tables, omitted = build_unicode_cmap(font, best, [])
        basic = tables[0]
        assert len(basic.compile(font)) <= FORMAT4_MAX_BYTES
        assert omitted == 8500 - len(basic.cmap) > 0
        next_prefix = sorted(best)[: len(basic.cmap) + 1]
        larger = _subtable(3, 1, 4, {cp: best[cp] for cp in next_prefix})
        try:
            compiled = larger.compile(font)
        except struct.error:
            pass
        else:
            assert len(compiled) > FORMAT4_MAX_BYTES


def test_build_unicode_cmap_keeps_u_ffff_out_of_format4(tmp_path):
    """Format 4 reserves U+FFFF for its sentinel; a real U+FFFF mapping must survive in format 12."""
    mapping = {0x41: "A", 0xFFFF: "uniFFFF"}
    builder = _rectangle_builder([".notdef", *mapping.values()])
    builder.font["cmap"] = newTable("cmap")
    builder.font["cmap"].tableVersion = 0
    builder.font["cmap"].tables = [_subtable(3, 10, 12, mapping)]
    path = _save_fixture(builder, tmp_path / "ffff.ttf")
    with TTFont(path) as font:
        tables, omitted = build_unicode_cmap(font, font.getBestCmap(), [])
        assert [(table.platformID, table.platEncID, table.format) for table in tables] == [(3, 1, 4), (3, 10, 12)]
        assert tables[0].cmap == {0x41: "A"}
        assert tables[1].cmap == mapping
        assert omitted == 1
        font["cmap"].tables = tables
        font.save(str(tmp_path / "normalized.ttf"))
    with TTFont(tmp_path / "normalized.ttf") as font:
        assert font.getBestCmap() == mapping
        assert 0xFFFF not in font["cmap"].getcmap(3, 1).cmap


def test_symbol_cmap_font_is_rejected_with_explicit_reason(tmp_path, font_dir):
    path = build_font(tmp_path / "symbol.ttf", "Symbol Fixture", "Regular", {0xF061})
    with TTFont(path) as font:
        font["cmap"].tables = [_subtable(3, 0, 4, dict(font.getBestCmap()))]
        font.save(path)
    a, symbol = read_faces(font_dir / "A.ttf")[0], read_faces(path)[0]
    assert symbol.codepoints == frozenset()
    output = tmp_path / "forged.ttf"
    with pytest.raises(ForgeError) as error:
        forge(ForgeSpec([MaterialSpec(a), MaterialSpec(symbol)]), output)
    assert error.value.stage == "validate"
    assert error.value.message == ("Symbol Fixture Regular: no Unicode characters (symbol or empty character map)")
    assert not output.exists()
