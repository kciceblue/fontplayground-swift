"""Merge prepared parts into one font, then set names, metrics and flags."""

from __future__ import annotations

from collections.abc import Mapping, Sequence
from pathlib import Path

from fontTools.merge import Merger
from fontTools.otlLib.maxContextCalc import maxCtxFont
from fontTools.subset import Subsetter
from fontTools.ttLib import TTFont

from fpengine.naming import FORGED_NOTICE as FORGED_NOTICE
from fpengine.naming import ForgeStamp, clean_name, font_revision, unique_id, version_string
from fpengine.naming import postscript_name as postscript_name
from fpengine.prepare import disable_hb_repacker, normalize_cmap, subset_options
from fpengine.spec import ForgeError, ForgeSpec

STANDARD_STYLES = {"Regular", "Bold", "Italic", "Bold Italic"}
MAX_GLYPHS = 65535
LEFTOVER_TABLES = ("DSIG", "fpgm", "prep", "cvt ")
# 'name' addresses its strings with 16-bit offsets, so every record together must fit in 64 KB.
NAME_TABLE_LIMIT = 0xFFFF


def merge_fonts(paths: list[str]) -> TTFont:
    font = Merger().merge(paths)
    disable_hb_repacker(font)
    return font


def final_subset(font: TTFont, codepoints) -> None:
    """Drop every glyph not reachable from the planned code points (e.g. a duplicate .notdef)."""
    s = Subsetter(subset_options())
    s.populate(unicodes=sorted(codepoints))
    s.subset(font)


def _mac_roman_safe(value: str) -> bool:
    try:
        value.encode("mac_roman")
        return True
    except UnicodeEncodeError:
        return False


def _record_bytes(value: str) -> int:
    """Room a record takes: UTF-16 in the Windows record, plus the Mac copy when it has one."""
    return len(value.encode("utf-16-be")) + (len(value) if _mac_roman_safe(value) else 0)


def notice_bytes(text: str) -> int:
    """Most room a carried notice adds: UTF-16 (Windows), a byte per character (Mac), a line break in each."""
    return len(text.encode("utf-16-be")) + len(text) + 3


def _set_name(name, name_id: int, value: str) -> None:
    name.setName(value, name_id, 3, 1, 0x409)
    if _mac_roman_safe(value):  # the Macintosh record cannot hold CJK etc.; platform 3 is enough everywhere
        name.setName(value, name_id, 1, 0, 0)


def _spec_names(spec: ForgeSpec) -> tuple[str, str, list[str]]:
    return clean_name(spec.family_name), clean_name(spec.style_name), [m.face.display_name for m in spec.materials]


def _own_names(family: str, style: str, sources: list[str], stamp: ForgeStamp) -> dict[int, str]:
    """Font Playground's own name records, before any source notice is added."""
    full = f"{family} {style}"
    records = {
        # FORGED_NOTICE must start name ID 0: is_forged() and the Swift ForgedMarker test for it.
        0: f"{FORGED_NOTICE} from: " + ", ".join(sources),
        3: unique_id(full, stamp),
        4: full,
        5: version_string(stamp),
        6: postscript_name(family, style),
    }
    if style in STANDARD_STYLES:
        records[1], records[2] = family, style
    else:
        legacy = "Bold" if "bold" in style.lower() else "Regular"
        if "italic" in style.lower() or "oblique" in style.lower():
            legacy = "Bold Italic" if legacy == "Bold" else "Italic"
        records[1], records[2], records[16], records[17] = full, legacy, family, style
    return records


def notice_budget(spec: ForgeSpec, stamp: ForgeStamp, licence_description: str | None) -> int:
    """Room left for carried notices: the name table's limit less the records Font Playground writes itself.

    Family and source names are not length-limited, so a fixed share could still overflow the table.
    """
    records = list(_own_names(*_spec_names(spec), stamp).values())
    if licence_description is not None:
        records.append(licence_description)
    return NAME_TABLE_LIMIT - sum(_record_bytes(value) for value in records)


def set_names(
    font: TTFont,
    family: str,
    style: str,
    sources: list[str],
    stamp: ForgeStamp,
    notices: Mapping[int, Sequence[str]] | None = None,
) -> None:
    """A fresh name table that keeps the sources' notices (ADR-0012): `notices[name_id]` go one per line."""
    notices = notices or {}
    records = _own_names(family, style, sources, stamp)
    records[0] = "\n".join([records[0], *notices.get(0, ())])
    for name_id in (7, 14):
        if notices.get(name_id):
            records[name_id] = "\n".join(notices[name_id])
    name = font["name"]
    name.names = []
    for name_id, value in records.items():
        _set_name(name, name_id, value)


OS2_V4_FIELDS = (
    ("ulCodePageRange1", 0),
    ("ulCodePageRange2", 0),
    ("sxHeight", 0),
    ("sCapHeight", 0),
    ("usDefaultChar", 0),
    ("usBreakChar", 32),
    ("usMaxContext", 0),
)


def upgrade_os2(font: TTFont, base: TTFont) -> None:
    """Raise OS/2 to version 4 (needed for fsSelection bit 7), filling fields older tables lack."""
    os2, base_os2 = font["OS/2"], base["OS/2"]
    for attr, default in OS2_V4_FIELDS:
        if not hasattr(os2, attr):
            setattr(os2, attr, getattr(base_os2, attr, default))
    os2.version = max(int(os2.version), 4)


def set_style_bits(font: TTFont, style: str) -> None:
    s = style.lower()
    bold, italic = "bold" in s, ("italic" in s or "oblique" in s)
    font["head"].macStyle = (1 if bold else 0) | (2 if italic else 0)
    os2 = font["OS/2"]
    sel = os2.fsSelection & ~((1 << 0) | (1 << 5) | (1 << 6))
    if italic:
        sel |= 1 << 0
    if bold:
        sel |= 1 << 5
    if not bold and not italic:
        sel |= 1 << 6
    os2.fsSelection = sel | (1 << 7)  # USE_TYPO_METRICS; upgrade_os2() guarantees version >= 4


def copy_vertical_metrics(font: TTFont, base: TTFont) -> None:
    for attr in ("ascent", "descent", "lineGap"):
        setattr(font["hhea"], attr, getattr(base["hhea"], attr))
    for attr in ("sTypoAscender", "sTypoDescender", "sTypoLineGap", "usWinAscent", "usWinDescent"):
        setattr(font["OS/2"], attr, getattr(base["OS/2"], attr))
    for attr in ("sxHeight", "sCapHeight"):
        if hasattr(base["OS/2"], attr) and hasattr(font["OS/2"], attr):
            setattr(font["OS/2"], attr, getattr(base["OS/2"], attr))


def finish(
    font: TTFont,
    spec: ForgeSpec,
    base: TTFont,
    codepoints,
    weight_class: int,
    *,
    stamp: ForgeStamp,
    fs_type: int,
    licence_description: str | None,
    notices: Mapping[int, Sequence[str]] | None = None,
) -> None:
    notices = notices or {}
    final_subset(font, codepoints)
    set_names(font, *_spec_names(spec), stamp, notices)
    font["head"].fontRevision = font_revision(stamp)
    if licence_description is not None:
        # The class notes stay on the first line: classify_licence(forged=True) and re-forging rely on them.
        _set_name(font["name"], 13, "\n".join([licence_description, *notices.get(13, ())]))
    upgrade_os2(font, base)
    set_style_bits(font, spec.style_name)
    copy_vertical_metrics(font, base)
    os2 = font["OS/2"]
    os2.usWeightClass = weight_class
    os2.fsType = fs_type
    os2.recalcUnicodeRanges(font)
    os2.recalcCodePageRanges(font)
    os2.usMaxContext = maxCtxFont(font)
    for tag in LEFTOVER_TABLES:
        if tag in font:
            del font[tag]


def finalize_cmap(font: TTFont) -> tuple[int, int | None]:
    """N-1: make the merged map safe to save without losing any Unicode mappings."""
    best = font.getBestCmap() or {}
    omitted = normalize_cmap(font)
    if not omitted:
        return 0, None
    basic = font["cmap"].tables[0].cmap
    first = min(cp for cp in best if cp <= 0xFFFF and cp not in basic)
    return omitted, first


def verify(path: Path, codepoints: set[int]) -> tuple[int, int]:
    """Reload the saved font and check coverage. Returns (code points, glyphs)."""
    font = TTFont(str(path))
    try:
        got = set(font.getBestCmap() or {})
        missing, extra = codepoints - got, got - codepoints
        if missing or extra:
            raise ForgeError("verify", None, f"coverage mismatch: {len(missing)} missing, {len(extra)} unexpected")
        glyphs = font["maxp"].numGlyphs
        if glyphs > MAX_GLYPHS:
            raise ForgeError(
                "verify", None, f"{glyphs} glyphs exceed the TrueType limit of {MAX_GLYPHS}", code="glyph_limit"
            )
        return len(got), glyphs
    finally:
        font.close()
