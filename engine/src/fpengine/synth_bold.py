"""Fake bold: stroke every outline and union it with the fill."""

from __future__ import annotations

from dataclasses import dataclass, field

import pathops
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib import TTFont

MAX_DELTA = 500


def stroke_width(delta_weight: int, upem: int) -> float:
    """+300 weight on a 1000-upem font thickens stems by 60 units."""
    return delta_weight / 1000 * 0.2 * upem


@dataclass
class BoldResult:
    delta: int
    emboldened: int = 0
    skipped: list[str] = field(default_factory=list)
    added_bytes: int = 0


def union_with_stroke(path: pathops.Path, width: float) -> pathops.Path:
    """ENGINE-4: simplified operands can rescue a failed outline union."""
    stroked = pathops.Path(path)
    stroked.stroke(width, pathops.LineCap.ROUND_CAP, pathops.LineJoin.ROUND_JOIN, 4.0)
    stroked.convertConicsToQuads()
    try:
        return pathops.op(path, stroked, pathops.PathOp.UNION)
    except pathops.PathOpsError:
        return pathops.op(pathops.simplify(path), pathops.simplify(stroked), pathops.PathOp.UNION)


def embolden(font: TTFont, delta_weight: int) -> BoldResult:
    delta = min(delta_weight, MAX_DELTA)
    summary = BoldResult(delta)
    glyf, hmtx = font["glyf"], font["hmtx"]
    glyph_set = font.getGlyphSet()
    w = stroke_width(delta, font["head"].unitsPerEm)

    # Pass 1: snapshot every outline (components decomposed) BEFORE anything is modified.
    # A composite drawn after its base glyph would otherwise be thickened twice.
    paths: dict[str, tuple[pathops.Path, int]] = {}
    for name in font.getGlyphOrder():
        path = pathops.Path()
        glyph_set[name].draw(path.getPen(glyphSet=glyph_set))
        if list(path.contours):
            paths[name] = (path, len(glyf[name].compile(glyf, recalcBBoxes=False)))

    # Pass 2: stroke + union each snapshot and write the (now simple) glyph back.
    for name, (path, before) in paths.items():
        try:
            result = union_with_stroke(path, w)
        except pathops.PathOpsError:
            # ENGINE-4: retain the regular outline and uniform bold spacing, then report it.
            summary.skipped.append(name)
            result = pathops.Path(path)
        else:
            summary.emboldened += 1
        result.convertConicsToQuads()
        result = result.transform(translateX=w / 2)  # keep the left side bearing
        pen = TTGlyphPen(None)
        result.draw(pen)
        glyph = pen.glyph()
        glyph.recalcBounds(glyf)
        glyf.glyphs[name] = glyph
        advance, _ = hmtx[name]
        hmtx[name] = (advance + round(w), glyph.xMin)
        summary.added_bytes += len(glyph.compile(glyf, recalcBBoxes=False)) - before
    font["hhea"].advanceWidthMax = max(a for a, _ in hmtx.metrics.values())
    return summary
