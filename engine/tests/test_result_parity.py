"""The Result parity item: names, layout, metrics, outlines and hinting in one forge."""

import array

from fontTools.feaLib.builder import addOpenTypeFeaturesFromString
from fontTools.ttLib import TTFont, newTable
from fontTools.ttLib.tables.ttProgram import Program

from fpengine.face import read_faces
from fpengine.forge import forge
from fpengine.prepare import KEEP_TABLES
from fpengine.spec import ForgeSpec, MaterialSpec
from tests.fixtures import build_font, cps
from tests.meta_fixtures import _save


def _pairpos_values(font):
    out = {}
    if "GPOS" not in font:
        return out
    for lookup in font["GPOS"].table.LookupList.Lookup:
        for subtable in lookup.SubTable:
            if getattr(subtable, "Format", None) != 1 or lookup.LookupType != 2:
                continue
            for left, pairs in zip(subtable.Coverage.glyphs, subtable.PairSet):
                for record in pairs.PairValueRecord:
                    out[(left, record.SecondGlyph)] = record.Value1.XAdvance
    return out


def test_parity_result_properties(tmp_path):
    p = build_font(tmp_path / "P.ttf", "Fixture P", "Regular", cps("ab"), kern={(ord("a"), ord("b")): -50})
    with TTFont(p) as font:
        for tag in ("fpgm", "prep"):
            table = font[tag] = newTable(tag)
            table.program = Program()
            table.program.fromBytecode(b"\xb0\x00")
        font["cvt "] = newTable("cvt ")
        font["cvt "].values = array.array("h", [16])
        font["glyf"]["uni0061"].program = Program()
        font["glyf"]["uni0061"].program.fromBytecode(b"\xb0\x00\x21")
        _save(font, p)
    q = build_font(tmp_path / "Q.ttf", "Fixture Q", "Regular", cps("漢字"))
    with TTFont(q) as font:
        addOpenTypeFeaturesFromString(
            font,
            "languagesystem DFLT dflt; languagesystem hani dflt;\n"
            "feature liga { sub uni6F22 uni5B57 by uni5B57; } liga;\n",
        )
        font["hhea"].ascent, font["hhea"].descent, font["hhea"].lineGap = 950, -250, 30
        os2 = font["OS/2"]
        os2.sTypoAscender, os2.sTypoDescender, os2.sTypoLineGap, os2.usWinAscent, os2.usWinDescent = (
            950,
            -250,
            30,
            960,
            260,
        )
        _save(font, q)
    spec = ForgeSpec(
        [MaterialSpec(read_faces(path)[0]) for path in (p, q)],
        base_index=1,
        script_rules={"han": 1},
        family_name="Parity Mix",
        style_name="Regular",
    )
    output = tmp_path / "out.ttf"
    report = forge(spec, output)
    with TTFont(output) as font:
        assert set(font.getBestCmap()) == cps("ab漢字")
        assert font["maxp"].numGlyphs == report.total_glyphs == 5
        assert not set(font.keys()) & {"fpgm", "prep", "cvt "}
        assert set(font.keys()) - {"GlyphOrder"} <= KEEP_TABLES
        for glyph_name in font.getGlyphOrder():
            program = getattr(font["glyf"][glyph_name], "program", None)
            assert program is None or program.getBytecode() == b""
        assert "liga" in {record.FeatureTag for record in font["GSUB"].table.FeatureList.FeatureRecord}
        assert "kern" in {record.FeatureTag for record in font["GPOS"].table.FeatureList.FeatureRecord}
        assert "kern" not in font and _pairpos_values(font)[("uni0061", "uni0062")] == -50
        name = font["name"]
        assert name.getDebugName(0).startswith("Forged with Font Playground")
        assert name.getDebugName(1) == "Parity Mix"
        assert all(
            "Fixture P" not in record.toUnicode() and "Fixture Q" not in record.toUnicode()
            for record in name.names
            if record.nameID != 0
        )
        hhea, os2 = font["hhea"], font["OS/2"]
        assert (hhea.ascent, hhea.descent, hhea.lineGap) == (950, -250, 30)
        assert (os2.sTypoAscender, os2.sTypoDescender, os2.sTypoLineGap, os2.usWinAscent, os2.usWinDescent) == (
            950,
            -250,
            30,
            960,
            260,
        )
    spec.base_index = 0
    control = tmp_path / "control.ttf"
    forge(spec, control)
    with TTFont(control) as font:
        hhea = font["hhea"]
        assert (hhea.ascent, hhea.descent, hhea.lineGap) == (800, -200, 0)
