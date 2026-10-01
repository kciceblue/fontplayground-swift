"""Synthetic metadata fixtures shared by WP-106 through WP-110."""

from __future__ import annotations

import os
import struct
import tempfile
from collections.abc import Iterable, Mapping
from pathlib import Path

from fontTools.feaLib.builder import addOpenTypeFeaturesFromString
from fontTools.ttLib import TTFont, newTable
from fontTools.ttLib.tables._c_m_a_p import CmapSubtable
from fontTools.ttLib.tables._k_e_r_n import KernTable_format_0, KernTable_format_unkown
from fontTools.ttLib.tables._n_a_m_e import makeName
from fontTools.ttLib.tables.DefaultTable import DefaultTable

from tests.fixtures import build_font


def _save(font: TTFont, path: Path) -> Path:
    temporary_path = None
    try:
        with tempfile.NamedTemporaryFile(dir=path.parent, prefix=f".{path.name}.", delete=False) as temporary:
            temporary_path = Path(temporary.name)
            font.save(temporary)
            temporary.flush()
            os.fsync(temporary.fileno())
        os.replace(temporary_path, path)
    finally:
        if temporary_path is not None:
            temporary_path.unlink(missing_ok=True)
    return path


def decorate(
    path: Path,
    *,
    out: Path | None = None,
    tables: Mapping[str, bytes] | None = None,
    fea: str | None = None,
    drop: Iterable[str] = (),
    vendor: str | None = None,
    fs_type: int | None = None,
    font_revision: float | None = None,
    kern_v1_format: int | None = None,
    name_records: Mapping[int, list[tuple]] | None = None,
) -> Path:
    """Change a fixture without requiring a real font or decompiling opaque AAT tables."""
    with TTFont(path) as font:
        if fea is not None:
            addOpenTypeFeaturesFromString(font, fea)
        for tag, data in (tables or {}).items():
            font[tag] = DefaultTable(tag)
            font[tag].data = data
        if vendor is not None:
            font["OS/2"].achVendID = vendor.ljust(4)
        if fs_type is not None:
            font["OS/2"].fsType = fs_type
        if font_revision is not None:
            font["head"].fontRevision = font_revision
        if name_records:
            names = font["name"]
            names.names = [record for record in names.names if record.nameID not in name_records]
            names.names += [
                makeName(text, name_id, *where) for name_id, records in name_records.items() for *where, text in records
            ]
        if kern_v1_format is not None:
            kern = font["kern"] = newTable("kern")
            kern.version = 1.0
            if kern_v1_format == 0:
                subtable = KernTable_format_0(apple=True)
                subtable.coverage, subtable.format, subtable.tupleIndex = 0, 0, 0
                glyphs = [glyph for glyph in font.getGlyphOrder() if glyph != ".notdef"]
                subtable.kernTable = {(glyphs[0], glyphs[1]): -40}
            elif kern_v1_format in (1, 2, 3):
                subtable = KernTable_format_unkown(kern_v1_format)
                subtable.data = struct.pack(">LBBH", 14, 0, kern_v1_format, 0) + b"\0" * 6
            else:
                raise ValueError("kern_v1_format must be 0, 1, 2 or 3")
            kern.kernTables = [subtable]
        for tag in drop:
            if tag in font:
                del font[tag]
        return _save(font, out if out is not None else path)


def build_bitmap_only_font(path: Path, family: str, codepoints: Iterable[int], *, fs_type: int = 2) -> Path:
    """CATALOG-8: a readable bitmap face has bhed instead of head and no outline tables."""
    build_font(path, family, "Regular", set(codepoints), fs_type=fs_type)
    with TTFont(path) as font:
        bhed = font["bhed"] = newTable("bhed")
        bhed.__dict__.update({key: value for key, value in vars(font["head"]).items() if key != "tableTag"})
        for tag in ("glyf", "loca", "head", "hmtx", "hhea"):
            del font[tag]
        font["maxp"].tableVersion = 0x00005000
        return _save(font, path)


def build_many_to_one_font(path: Path, n_codepoints: int, *, glyphs: int = 3, start: int = 0x4E00) -> Path:
    """CATALOG-2: many characters deliberately share one glyph, like LastResort."""
    if glyphs < 2 or n_codepoints < 0 or start < 0 or start + n_codepoints > 0x110000:
        raise ValueError("Expected at least two glyphs and a valid Unicode code-point range")
    build_font(path, "Fixture Many to One", "Regular", set(range(0x61, 0x61 + glyphs - 1)))
    with TTFont(path) as font:
        subtable = CmapSubtable.newSubtable(12)
        subtable.platformID, subtable.platEncID, subtable.language = 3, 10, 0
        subtable.cmap = dict.fromkeys(range(start, start + n_codepoints), font.getGlyphOrder()[1])
        font["cmap"].tables = [subtable]
        return _save(font, path)
