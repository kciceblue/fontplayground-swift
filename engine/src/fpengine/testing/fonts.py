"""Tiny rectangle fonts, adapted from the original test fixtures without test dependencies."""

from __future__ import annotations

import os
import tempfile
from collections.abc import Iterable, Sequence
from pathlib import Path

from fontTools.fontBuilder import FontBuilder
from fontTools.pens.t2CharStringPen import T2CharStringPen
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib import TTCollection, TTFont
from fontTools.ttLib.tables.TupleVariation import TupleVariation

FIXED_TIMESTAMP = 3_900_000_000


def atomic_write(path: Path, data: bytes) -> None:
    temporary_path = None
    try:
        with tempfile.NamedTemporaryFile(dir=path.parent, prefix=f".{path.name}.", delete=False) as temporary:
            temporary_path = Path(temporary.name)
            temporary.write(data)
            temporary.flush()
            os.fsync(temporary.fileno())
        os.replace(temporary_path, path)
    finally:
        if temporary_path is not None:
            temporary_path.unlink(missing_ok=True)


def _save(font: TTFont | TTCollection, path: Path) -> Path:
    import io

    output = io.BytesIO()
    font.save(output)
    atomic_write(path, output.getvalue())
    return path


def build_font(
    path: Path,
    family: str,
    style: str,
    codepoints: Iterable[int],
    *,
    upem: int = 1000,
    cff: bool = False,
    weight: int = 400,
    italic: bool = False,
    fs_type: int = 0,
    variable: bool = False,
    color: bool = False,
) -> Path:
    codepoints = sorted(set(codepoints))
    names = {cp: f"uni{cp:04X}" if cp <= 0xFFFF else f"u{cp:05X}" for cp in codepoints}
    order = [".notdef", *names.values()]
    scale = upem / 1000
    lsb, stem, height = round(50 * scale), round(100 * scale), round(700 * scale)
    advance = stem + 2 * lsb
    ps = f"{family}-{style}".replace(" ", "")
    fb = FontBuilder(upem, isTTF=not cff)
    fb.setupGlyphOrder(order)
    fb.setupCharacterMap(names)
    outlines = {}
    for name in order:
        pen = T2CharStringPen(advance, None) if cff else TTGlyphPen(None)
        pen.moveTo((lsb, 0))
        pen.lineTo((lsb + stem, 0))
        pen.lineTo((lsb + stem, height))
        pen.lineTo((lsb, height))
        pen.closePath()
        outlines[name] = pen.getCharString() if cff else pen.glyph()
    if cff:
        fb.setupCFF(ps, {"FullName": f"{family} {style}"}, outlines, {})
    else:
        fb.setupGlyf(outlines)
    fb.setupHorizontalMetrics({name: (advance, lsb) for name in order})
    fb.setupHorizontalHeader(ascent=round(800 * scale), descent=-round(200 * scale))
    fb.setupNameTable(
        {
            "familyName": family,
            "styleName": style,
            "psName": ps,
            "uniqueFontIdentifier": f"{ps};fixture",
            "version": "Version 1.000",
        }
    )
    bold = weight >= 700
    selection = (1 if italic else 0) | (0x20 if bold else 0) | (0x40 if not italic and not bold else 0)
    fb.setupOS2(
        sTypoAscender=round(800 * scale),
        sTypoDescender=-round(200 * scale),
        usWinAscent=round(800 * scale),
        usWinDescent=round(200 * scale),
        usWeightClass=weight,
        fsType=fs_type,
        fsSelection=selection,
    )
    fb.setupPost()
    if variable:
        fb.setupFvar([("wght", 100, 400, 900, "Weight")], [])
        deltas = [(0, 0), (100, 0), (100, 0), (0, 0), (0, 0), (100, 0), (0, 0), (0, 0)]
        fb.setupGvar({name: [TupleVariation({"wght": (0.0, 1.0, 1.0)}, deltas)] for name in order})
    if color:
        fb.setupCPAL([[(1, 0, 0, 1)]])
        fb.setupCOLR({order[1]: [(order[1], 0)]})
    fb.font["head"].macStyle = (1 if bold else 0) | (2 if italic else 0)
    fb.font["head"].created = fb.font["head"].modified = FIXED_TIMESTAMP
    fb.font.recalcTimestamp = False
    return _save(fb.font, path)


def build_collection(path: Path, font_paths: Sequence[Path]) -> Path:
    with TTCollection() as collection:
        collection.fonts = [TTFont(member, recalcTimestamp=False) for member in font_paths]
        return _save(collection, path)
