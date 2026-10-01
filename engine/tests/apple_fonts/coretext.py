"""Inspect output shaping with URL descriptors, leaving system font registration untouched."""

from __future__ import annotations

import re
import struct
from dataclasses import dataclass

from fontTools.ttLib import TTFont

from tests.apple_fonts.locate import FaceLocation


@dataclass
class Shaped:
    glyph_names: list[str]
    foreign_glyphs: int
    width: float


def _font(path: str, postscript_name: str | None, size: float):
    import CoreText as CT
    from Foundation import NSURL

    descriptors = CT.CTFontManagerCreateFontDescriptorsFromURL(NSURL.fileURLWithPath_(path))
    assert descriptors, f"No descriptors for {path}"
    descriptor = next(
        (
            desc
            for desc in descriptors
            if postscript_name is None
            or CT.CTFontDescriptorCopyAttribute(desc, CT.kCTFontNameAttribute) == postscript_name
        ),
        None,
    )
    assert descriptor is not None, f"No descriptor for {postscript_name} in {path}"
    return CT.CTFontCreateWithFontDescriptor(descriptor, size, None)


def shape(path: str, postscript_name: str | None, text: str, face_index: int = -1, size: float = 24.0) -> Shaped:
    import CoreText as CT
    from Foundation import NSAttributedString

    font = _font(path, postscript_name, size)
    chosen_name = CT.CTFontCopyPostScriptName(font)
    attributed = NSAttributedString.alloc().initWithString_attributes_(text, {CT.kCTFontAttributeName: font})
    line = CT.CTLineCreateWithAttributedString(attributed)
    with TTFont(path, fontNumber=face_index, lazy=True) as source:
        order = source.getGlyphOrder()
    glyph_names = []
    foreign = 0
    for run in CT.CTLineGetGlyphRuns(line):
        count = CT.CTRunGetGlyphCount(run)
        run_font = CT.CTRunGetAttributes(run)[CT.kCTFontAttributeName]
        glyphs = CT.CTRunGetGlyphs(run, (0, count), None)
        if CT.CTFontCopyPostScriptName(run_font) != chosen_name:
            foreign += count
            glyph_names.extend(f"foreign:{glyph}" for glyph in glyphs)
        else:
            glyph_names.extend(re.sub(r"#\d+$", "", order[glyph]) for glyph in glyphs)
    width = CT.CTLineGetTypographicBounds(line, None, None, None)[0]
    return Shaped(glyph_names, foreign, width)


def glyph_for(path: str, postscript_name: str | None, char: str) -> int:
    import CoreText as CT

    font = _font(path, postscript_name, 24.0)
    units = struct.unpack(f">{len(char.encode('utf-16-be')) // 2}H", char.encode("utf-16-be"))
    mapped, glyphs = CT.CTFontGetGlyphsForCharacters(font, tuple(chr(unit) for unit in units), None, len(units))
    return glyphs[0] if mapped else 0


def check_shaping(scenario_id: str, locations: list[FaceLocation], output: str) -> None:
    if scenario_id in {"AF-15", "AF-16"}:
        text = "مرحبا بالعالم" if scenario_id == "AF-15" else "नमस्ते क्षत्रिय"
        source = locations[1]
        original = shape(source.path, source.postscript_name, text, source.index)
        forged = shape(output, None, text)
        assert original.glyph_names == forged.glyph_names
        assert original.foreign_glyphs == forged.foreign_glyphs == 0
    elif scenario_id == "AF-22":
        source = locations[0]
        text = "office fifty flow AVAWAY"
        original = shape(source.path, source.postscript_name, text, source.index)
        forged = shape(output, None, text)
        assert abs(original.width - forged.width) <= 0.5, (original.width, forged.width)
        assert forged.foreign_glyphs == 0
    elif scenario_id == "AF-20":
        assert glyph_for(output, None, "한") != 0
        assert glyph_for(output, None, "힣") != 0
