from dataclasses import replace
from pathlib import Path
from types import SimpleNamespace

import pytest
from fontTools.ttLib import TTFont, newTable
from fontTools.ttLib.tables._c_m_a_p import CmapSubtable

from fpengine.face import (
    READER_VERSION,
    _head,
    is_apple_kern,
    is_hidden,
    is_suspicious_coverage,
    read_faces,
    script_tags,
)
from fpengine.licence import normalise_notice, vendor_id_of
from tests.fixtures import build_font, cps, fake_face
from tests.meta_fixtures import build_bitmap_only_font, build_many_to_one_font, decorate

AAT_TABLES = {
    "morx": b"\0\2\0\0\0\0\0\0",
    "kerx": b"\0\2\0\0\0\0\0\0",
    "trak": b"\0\1\0\0\0\0\0\0\0\0\0\0",
}


def test_catalog_8_bhed_bitmap_font_is_unsupported_not_unreadable(tmp_path: Path) -> None:
    path = build_bitmap_only_font(tmp_path / "bitmap.ttf", "Fixture Bitmap", cps("a一"))
    with TTFont(path) as font:
        assert "bhed" in font
        assert all(tag not in font for tag in ("head", "glyf", "loca", "CFF ", "hmtx", "hhea"))
    (face,) = read_faces(path)
    assert face.outline == "none"
    assert not face.supported
    assert face.unsupported_reason == "bitmap-only font (no outlines)"
    assert face.upem == 1000
    assert face.font_revision == "1.000"
    assert face.fs_type == 2
    assert face.codepoints == cps("a一")


def test_catalog_2_dot_faces_are_hidden(tmp_path: Path) -> None:
    assert is_hidden(".LastResort", "LastResort")
    assert is_hidden("System Font", ".SFNS-Regular")
    assert is_hidden(".SF Arabic", None)
    assert not is_hidden("Helvetica", "Helvetica")
    path = build_font(
        tmp_path / "s.ttf",
        "Fixture S",
        "Regular",
        cps("a"),
        name_records={6: [(3, 1, 0x409, ".FixtureS-Regular")]},
    )
    face = read_faces(path)[0]
    assert face.hidden and face.supported


def test_engine_10_dot_families_are_hidden(tmp_path: Path) -> None:
    path = build_font(tmp_path / "hidden.ttf", ".Fixture Hidden", "Regular", cps("a"))
    face = read_faces(path)[0]
    assert face.hidden and face.supported


def test_catalog_2_suspicious_coverage_rule(font_dir: Path, tmp_path: Path) -> None:
    assert is_suspicious_coverage(256, 63)
    assert is_suspicious_coverage(1114112, 7)
    for n_codepoints, glyphs in ((256, 64), (255, 1), (35854, 49533), (226, 200)):
        assert not is_suspicious_coverage(n_codepoints, glyphs)
    path = build_many_to_one_font(tmp_path / "lr.ttf", 2000)
    face = read_faces(path)[0]
    assert len(face.codepoints) == 2000 and face.glyph_count == 3
    assert face.suspicious_coverage and face.supported
    assert not read_faces(font_dir / "A.ttf")[0].suspicious_coverage


def test_engine_2_script_tags_and_aat_flags(font_dir: Path, tmp_path: Path) -> None:
    path = decorate(
        font_dir / "A.ttf",
        out=tmp_path / "decorated.ttf",
        fea="languagesystem arab dflt; feature init { sub uni0061 by uni0062; } init;",
        tables=AAT_TABLES,
        kern_v1_format=1,
    )
    face = read_faces(path)[0]
    assert face.ot_gsub == ("arab",) and face.ot_gpos == ()
    assert face.aat_morx and face.aat_kerx and face.aat_trak and face.aat_kern_v1
    assert not read_faces(font_dir / "K.ttf")[0].aat_kern_v1
    path = decorate(font_dir / "A.ttf", out=tmp_path / "kern0.ttf", kern_v1_format=0)
    assert read_faces(path)[0].aat_kern_v1
    path = decorate(
        font_dir / "A.ttf",
        out=tmp_path / "gpos.ttf",
        fea="languagesystem lao dflt; feature kern { pos uni0061 uni0062 -10; } kern;",
    )
    face = read_faces(path)[0]
    assert face.ot_gsub == () and face.ot_gpos == ("lao ",)


def test_native_6_aat_only_face_flags(font_dir: Path, tmp_path: Path) -> None:
    path = decorate(font_dir / "A.ttf", out=tmp_path / "aat.ttf", tables=AAT_TABLES, kern_v1_format=1)
    face = read_faces(path)[0]
    assert face.ot_gsub == face.ot_gpos == ()
    assert face.aat_morx and face.aat_kerx and face.aat_trak and face.aat_kern_v1
    assert face.shapes_groups == () and face.unshaped == frozenset()
    path = decorate(font_dir / "A.ttf", out=tmp_path / "mort.ttf", tables={"mort": b"\0" * 8})
    assert read_faces(path)[0].aat_morx


@pytest.mark.parametrize("tag", ["GSUB", "GPOS"])
def test_malformed_layout_table_does_not_fail_the_face(font_dir: Path, tmp_path: Path, tag: str) -> None:
    path = decorate(
        font_dir / "A.ttf",
        out=tmp_path / "malformed.ttf",
        tables={tag: b"\x00\x01\x00\x00\xff\xff\x00\x00\x00\x00"},
    )
    face = read_faces(path)[0]
    assert face.ot_gsub == face.ot_gpos == ()
    assert face.supported


def test_script_tags_are_sorted_unique_and_preserve_spaces() -> None:
    font = TTFont()
    assert script_tags(font, "GSUB") == ()
    font["GSUB"] = SimpleNamespace(table=SimpleNamespace(ScriptList=None))
    assert script_tags(font, "GSUB") == ()
    records = [SimpleNamespace(ScriptTag=tag) for tag in ("nko ", "arab", "lao ", "arab")]
    font["GSUB"].table.ScriptList = SimpleNamespace(ScriptRecord=records)
    assert script_tags(font, "GSUB") == ("arab", "lao ", "nko ")


@pytest.mark.parametrize("format", [0, 1, 2, 3])
def test_apple_kern_header_is_read_without_decompiling(font_dir: Path, tmp_path: Path, format: int) -> None:
    path = decorate(font_dir / "A.ttf", out=tmp_path / "kern.ttf", kern_v1_format=format)
    with TTFont(path, lazy=True) as font:
        assert is_apple_kern(font)
        assert not font.isLoaded("kern")
        assert font["kern"].version == 1.0
        assert font["kern"].kernTables[0].format == format
    font = TTFont()
    assert not is_apple_kern(font)
    font["kern"] = newTable("kern")
    font["kern"].version = 1.0
    assert is_apple_kern(font)
    font["kern"].version = "broken"
    assert not is_apple_kern(font)


def test_malformed_kern_does_not_fail_the_face(font_dir: Path, tmp_path: Path) -> None:
    path = decorate(font_dir / "A.ttf", out=tmp_path / "kern.ttf", tables={"kern": b"\0"})
    face = read_faces(path)[0]
    assert not face.aat_kern_v1 and face.supported


def test_postscript_full_name_and_os2_fields(font_dir: Path, tmp_path: Path) -> None:
    path = decorate(
        font_dir / "A.ttf",
        out=tmp_path / "names.ttf",
        name_records={
            6: [(3, 1, 0x409, "FixtureA-Regular"), (1, 0, 0, "FixtureA-Regular")],
            4: [(3, 1, 0x409, "Fixture A Regular")],
        },
    )
    face = read_faces(path)[0]
    assert face.postscript_name == "FixtureA-Regular" and face.full_name == "Fixture A Regular"
    face = read_faces(font_dir / "A.ttf")[0]
    assert face.postscript_name is None and face.full_name == "Fixture A Regular"
    path = decorate(font_dir / "A.ttf", out=tmp_path / "no-os2.ttf", drop=("OS/2",))
    face = read_faces(path)[0]
    assert not face.has_os2 and face.fs_type is None and face.embedding == "installable"
    assert face.vendor_id is None
    face = read_faces(font_dir / "C.ttf")[0]
    assert face.fs_type == 2 and face.embedding == "restricted"


def test_vendor_id_and_licence_notice(font_dir: Path, tmp_path: Path) -> None:
    path = decorate(
        font_dir / "A.ttf",
        out=tmp_path / "licence.ttf",
        vendor="APPL",
        name_records={13: [(3, 1, 0x409, "x" * 200 + "\r\n" + "y" * 198)]},
    )
    face = read_faces(path)[0]
    assert face.vendor_id == "APPL" and face.licence_class == "apple-sla"
    assert len(face.licence_notice) == 300 and face.licence_notice.endswith("…")
    assert "\r" not in face.licence_notice and "\n" not in face.licence_notice
    path = decorate(
        font_dir / "A.ttf",
        out=tmp_path / "copyright.ttf",
        vendor="MS  ",
        name_records={0: [(3, 1, 0x409, "Copyright 2024 Example Foundry")]},
    )
    face = read_faces(path)[0]
    assert face.licence_notice == "Copyright 2024 Example Foundry" and face.vendor_id == "MS"
    face = read_faces(font_dir / "A.ttf")[0]
    assert face.licence_notice is None and face.vendor_id == "????"
    assert normalise_notice(None) is None and normalise_notice(" \t\r\n") is None
    assert normalise_notice("  One\r\n two\tthree  ") == "One two three"
    assert normalise_notice("x" * 300) == "x" * 300
    assert vendor_id_of(SimpleNamespace(achVendID=" \x00 ")) is None


def test_is_forged_field_reads_the_notice(font_dir: Path, tmp_path: Path) -> None:
    path = decorate(
        font_dir / "A.ttf",
        out=tmp_path / "forged.ttf",
        name_records={0: [(3, 1, 0x409, "Forged with Font Playground from: Fixture A Regular")]},
    )
    assert read_faces(path)[0].is_forged
    assert not read_faces(font_dir / "A.ttf")[0].is_forged


def test_symbol_only_cmap_is_unsupported(font_dir: Path, tmp_path: Path) -> None:
    path = tmp_path / "symbol.ttf"
    with TTFont(font_dir / "A.ttf") as font:
        subtable = CmapSubtable.newSubtable(4)
        subtable.platformID, subtable.platEncID, subtable.language = 3, 0, 0
        subtable.cmap = {0xF061: "uni0061", 0xF062: "uni0062", 0xF063: "uni0063"}
        font["cmap"].tables = [subtable]
        font.save(path)
    face = read_faces(path)[0]
    assert face.codepoints == frozenset() and not face.supported
    assert face.unsupported_reason == "no Unicode characters (symbol or empty character map)"


def test_unsupported_reason_priority() -> None:
    face = fake_face([], outline="none", has_color=True)
    assert face.unsupported_reason == "bitmap-only font (no outlines)"
    assert replace(face, outline="CFF2").unsupported_reason == "CFF2 outlines are not supported"
    assert replace(face, outline="glyf").unsupported_reason == "colour fonts are not supported"


def test_reader_version_is_an_int() -> None:
    assert type(READER_VERSION) is int and READER_VERSION >= 4


def test_header_and_fixture_metadata_overrides(font_dir: Path, tmp_path: Path) -> None:
    with pytest.raises(KeyError):
        _head(TTFont())
    path = decorate(font_dir / "A.ttf", out=tmp_path / "overrides.ttf", font_revision=2.125, fs_type=8)
    face = read_faces(path)[0]
    assert face.font_revision == "2.125" and face.fs_type == 8 and face.embedding == "editable"
    assert read_faces(font_dir / "A.ttf")[0].font_revision == "1.000"
