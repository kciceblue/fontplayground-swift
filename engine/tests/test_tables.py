"""Malformed discarded tables never reach a reader, and bitmap losses remain visible."""

import struct
from pathlib import Path

import pytest
from fontTools.subset import Subsetter
from fontTools.ttLib import TTFont
from fontTools.ttLib.tables.DefaultTable import DefaultTable

from fpengine.face import read_faces
from fpengine.forge import forge
from fpengine.prepare import KEEP_TABLES, PREPARE_TABLES, drop_unused_tables, prepare, subset_options
from fpengine.spec import ForgeSpec, Issue, MaterialSpec
from tests.fixtures import build_font, cps


def _font_with_tables(path: Path, tables: dict[str, bytes]) -> Path:
    build_font(path, "Bitmap Fixture", "Regular", cps("gh"))
    with TTFont(path) as font:
        for tag, data in tables.items():
            table = DefaultTable(tag)
            table.data = data
            font[tag] = table
        font.save(path)
    return path


@pytest.mark.parametrize("under_a", [False, True], ids=["alone", "under-A"])
def test_engine_m2_malformed_apple_bitmap_tables(tmp_path, font_dir, under_a):
    """Reference crashes in prepare with 'unpack requires a buffer of 16 bytes'."""
    path = _font_with_tables(
        tmp_path / "apple-bitmaps.ttf",
        {
            "bloc": struct.pack(">LL", 0x00020000, 1) + b"\0\0",
            "bdat": struct.pack(">L", 0x00020000),
            "bhed": b"\0\1",
        },
    )
    face = read_faces(path)[0]
    faces = [read_faces(font_dir / "A.ttf")[0], face] if under_a else [face]
    index = 1 if under_a else 0
    output = tmp_path / "forged.ttf"
    report = forge(ForgeSpec([MaterialSpec(face) for face in faces]), output)
    with TTFont(output) as font:
        assert set(font.keys()) - {"GlyphOrder"} <= KEEP_TABLES
        assert set(font.getBestCmap()) == set().union(*(face.codepoints for face in faces))
    note = "embedded bitmaps (bdat, bhed, bloc) are not kept; the forged font draws outlines at every size"
    message = f"{report.materials[index].name}: {note}"
    assert [issue for issue in report.issues if not issue.code.startswith("licence_")] == [
        Issue("bitmaps_dropped", "warning", index, None, message)
    ]
    assert note in report.materials[index].warnings
    assert message in report.warnings


@pytest.mark.parametrize("tags", [("EBDT", "EBLC"), ("bdat", "bloc")])
def test_engine_12_bitmap_strikes_reported(tmp_path, tags):
    """Reference silently drops standard bitmap strikes; Apple's malformed ones crash."""
    path = _font_with_tables(tmp_path / "strikes.ttf", {tag: b"\0\2\0\0junk" for tag in tags})
    face = read_faces(path)[0]
    part = prepare(MaterialSpec(face), face.codepoints, 1000, None, 1.0, tmp_path, 0)
    note = f"embedded bitmaps ({', '.join(sorted(tags))}) are not kept; the forged font draws outlines at every size"
    assert part.warnings == [note]
    assert part.issues == [Issue("bitmaps_dropped", "warning", 0, None, f"{face.display_name}: {note}")]
    assert part.dropped_tables == sorted(tags)


def test_unused_tables_dropped_before_subsetting(tmp_path, monkeypatch):
    tags = [
        "morx",
        "mort",
        "feat",
        "trak",
        "kerx",
        "ankr",
        "just",
        "prop",
        "lcar",
        "opbd",
        "bsln",
        "fond",
        "Zapf",
        "meta",
    ]
    path = _font_with_tables(tmp_path / "unused.ttf", {tag: b"\0\1junk" for tag in tags})
    face = read_faces(path)[0]
    observed = []
    real_subset = Subsetter.subset

    def record_tables(subsetter, font):
        observed.append(set(font.keys()) - {"GlyphOrder"})
        return real_subset(subsetter, font)

    monkeypatch.setattr(Subsetter, "subset", record_tables)
    part = prepare(MaterialSpec(face), face.codepoints, 1000, None, 1.0, tmp_path, 0)
    assert len(observed) == 1
    assert observed[0] <= PREPARE_TABLES
    assert part.dropped_tables == sorted(tags)
    assert part.issues == []


def test_drop_unused_tables_does_not_decompile(tmp_path, monkeypatch):
    path = _font_with_tables(tmp_path / "lazy.ttf", {"bloc": b"broken", "meta": b"broken"})
    with TTFont(path, lazy=True) as font:

        def reject_read(tag):
            pytest.fail(f"drop_unused_tables tried to decompile {tag}")

        monkeypatch.setattr(font, "_readTable", reject_read)
        assert drop_unused_tables(font) == ["bloc", "meta"]
        assert drop_unused_tables(font) == []
        assert "GlyphOrder" in font.keys()


def test_subset_options_drop_apple_bitmaps():
    tables = subset_options().drop_tables
    assert {"DSIG", "bdat", "bloc", "bhed"} <= set(tables)
    assert len(tables) == len(set(tables))


@pytest.mark.parametrize("filename", ["A.ttf", "B.otf"])
def test_plain_fonts_drop_nothing(font_dir, tmp_path, filename):
    face = read_faces(font_dir / filename)[0]
    part = prepare(MaterialSpec(face), face.codepoints, 1000, None, 1.0, tmp_path, 0)
    assert part.dropped_tables == []
    assert part.issues == []
