"""Turn one material into a merge-ready TrueType part."""

from __future__ import annotations

import re
import struct
from collections.abc import Mapping, Sequence
from dataclasses import dataclass, field
from pathlib import Path

from fontTools.fontBuilder import FontBuilder
from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.cu2quPen import Cu2QuPen
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.subset import Options, Subsetter
from fontTools.ttLib import TTFont, newTable
from fontTools.ttLib.scaleUpem import scale_upem
from fontTools.ttLib.tables._c_m_a_p import CmapSubtable
from fontTools.ttLib.tables.otBase import USE_HARFBUZZ_REPACKER
from fontTools.varLib.instancer import instantiateVariableFont

from fpengine.face import FontFace, script_tags, source_notices
from fpengine.kern import has_kern_feature, kern_to_gpos
from fpengine.shaping import SCRIPT_SHAPING, explain_unshaped, join_names, responsible_scripts
from fpengine.spec import ForgeError, Issue, MaterialSpec
from fpengine.synth_bold import embolden

KEEP_TABLES = {
    "head",
    "hhea",
    "maxp",
    "OS/2",
    "hmtx",
    "cmap",
    "loca",
    "glyf",
    "name",
    "post",
    "GSUB",
    "GPOS",
    "GDEF",
    "kern",
}
PREPARE_TABLES = frozenset(KEEP_TABLES | {"CFF "})
BITMAP_TABLES = frozenset({"EBDT", "EBLC", "EBSC", "bdat", "bloc", "bhed"})
MAX_UPEM = 16384
FORMAT4_MAX_BYTES = 65535


@dataclass
class PreparedFont:
    path: str
    upem: int
    warnings: list[str] = field(default_factory=list)
    issues: list[Issue] = field(default_factory=list)
    dropped_tables: list[str] = field(default_factory=list)
    bold_added_bytes: int = 0
    aat_losses: frozenset[str] = frozenset()
    notices: tuple[tuple[int, str], ...] = ()  # the source's copyright and licence notices (face.source_notices)


def _note(warnings: list[str], issues: list[Issue], code: str, note: str, index: int, display_name: str) -> None:
    """Every per-material issue is also a human-readable note (the text report stays complete)."""
    warnings.append(note)
    issues.append(Issue(code, "warning", index, None, f"{display_name}: {note}"))


def load_face(material: MaterialSpec) -> TTFont:
    face = material.face
    return TTFont(face.path, fontNumber=face.index if face.is_collection else -1)


def ensure_os2(font: TTFont) -> bool:
    """ENGINE-M1: derive missing metrics before the subsetter, instancer and merger need them."""
    if "OS/2" in font:
        return False
    head, hhea = font["head"], font["hhea"]
    upem = head.unitsPerEm
    cmap = font.getBestCmap() or {}
    glyph_set = font.getGlyphSet()

    def height(codepoint: int) -> int:
        glyph_name = cmap.get(codepoint)
        if glyph_name is None:
            return 0
        pen = BoundsPen(glyph_set)
        glyph_set[glyph_name].draw(pen)
        return round(pen.bounds[3]) if pen.bounds is not None else 0

    x_height, cap_height = height(0x78), height(0x48)
    selection = (0x01 if head.macStyle & 2 else 0) | (0x20 if head.macStyle & 1 else 0)
    underline = font["post"].underlineThickness if "post" in font else 0
    FontBuilder(font=font).setupOS2(
        version=4,
        usWeightClass=700 if head.macStyle & 1 else 400,
        usWidthClass=5,
        fsType=0,
        fsSelection=selection or 0x40,
        achVendID="NONE",
        sTypoAscender=hhea.ascent,
        sTypoDescender=hhea.descent,
        sTypoLineGap=hhea.lineGap,
        usWinAscent=max(hhea.ascent, head.yMax, 0),
        usWinDescent=max(-hhea.descent, -head.yMin, 0),
        sxHeight=x_height,
        sCapHeight=cap_height,
        ySubscriptXSize=round(upem * 0.65),
        ySuperscriptXSize=round(upem * 0.65),
        ySubscriptYSize=round(upem * 0.6),
        ySuperscriptYSize=round(upem * 0.6),
        ySubscriptXOffset=0,
        ySuperscriptXOffset=0,
        ySubscriptYOffset=round(upem * 0.075),
        ySuperscriptYOffset=round(upem * 0.35),
        yStrikeoutSize=underline if underline > 0 else round(upem * 0.05),
        yStrikeoutPosition=round(x_height * 0.6) if x_height else round(upem * 0.22),
        ulCodePageRange1=0,
        ulCodePageRange2=0,
        usDefaultChar=0,
        usBreakChar=32,
        usMaxContext=0,
    )
    return True


def refuse_lost_mark_positioning(face: FontFace, codepoints) -> None:
    """Assigned marks that were planned on this face only because of its GPOS can't survive dropping it."""
    assigned = set(codepoints)
    needed = explain_unshaped(face.codepoints, face.ot_gsub, ())
    lost = {cp: code for cp, code in needed.items() if cp in assigned and cp not in face.unshaped}
    if lost:
        names = join_names(SCRIPT_SHAPING[code].name for code in responsible_scripts(lost))
        raise ForgeError(
            "prepare",
            face.display_name,
            f"{names} marks need this font's positioning rules, but its variable positioning data (GPOS) is "
            f"broken and has to be dropped. Let another font draw {names}.",
        )


def instance_variable(font: TTFont, weight: int | None) -> TTFont:
    fvar = font["fvar"]
    limits = {a.axisTag: a.defaultValue for a in fvar.axes}
    if weight is not None and "wght" in limits:
        a = next(a for a in fvar.axes if a.axisTag == "wght")
        limits["wght"] = min(max(weight, a.minValue), a.maxValue)
    return instantiateVariableFont(font, limits, inplace=False)


def subset_options() -> Options:
    o = Options()
    o.layout_features = ["*"]
    o.hinting = False
    o.notdef_outline = True
    o.glyph_names = True
    o.desubroutinize = True
    o.name_IDs = ["*"]
    o.name_legacy = True
    o.name_languages = ["*"]
    # ENGINE-M2: final_subset also needs to avoid Apple's bitmap table readers.
    o.drop_tables = list(dict.fromkeys([*o.drop_tables, "DSIG", "bdat", "bloc", "bhed"]))
    return o


def drop_unused_tables(font: TTFont) -> list[str]:
    """Remove tables preparation cannot use without decompiling their potentially malformed data."""
    # ENGINE-M2: the subsetter would otherwise try Apple's bloc data with the EBLC reader.
    dropped = sorted(tag for tag in font.keys() if tag != "GlyphOrder" and tag not in PREPARE_TABLES)
    for tag in dropped:
        del font[tag]
    return dropped


DROPPED_FEATURES = frozenset({"locl"})
ALWAYS_DROPPED = frozenset({"aalt"})
DISCRETIONARY_FEATURES = frozenset(
    {
        "salt",
        "swsh",
        "cswh",
        "titl",
        "ornm",
        "nalt",
        "hist",
        "smpl",
        "trad",
        "tnam",
        "jp78",
        "jp83",
        "jp90",
        "jp04",
        "hojo",
        "nlck",
        "expt",
        "dlig",
        "hlig",
    }
)
_SS_CV = re.compile(r"ss(0[1-9]|1[0-9]|20)|cv(0[1-9]|[1-9][0-9])")


def is_discretionary(tag: str) -> bool:
    """Keep default-on shaping features even when they share a locale lookup."""
    return tag in DISCRETIONARY_FEATURES or _SS_CV.fullmatch(tag) is not None


def kept_features(font: TTFont) -> list[str]:
    """ENGINE-3: exclude locale aliases and palette alternates from glyph closure."""
    tags: set[str] = set()
    drop: set[str] = set()
    for table in ("GSUB", "GPOS"):
        if table not in font or not getattr(font[table].table, "FeatureList", None):
            continue
        records = font[table].table.FeatureList.FeatureRecord
        tags.update(record.FeatureTag for record in records)
        # GSUB and GPOS have separate lookup index spaces.
        dropped_lookups = {
            index
            for record in records
            if record.FeatureTag in DROPPED_FEATURES
            for index in record.Feature.LookupListIndex
        }
        drop.update(
            record.FeatureTag
            for record in records
            if is_discretionary(record.FeatureTag) and dropped_lookups.intersection(record.Feature.LookupListIndex)
        )
    return sorted(tags - DROPPED_FEATURES - ALWAYS_DROPPED - drop)


def disable_hb_repacker(font: TTFont) -> None:
    """ENGINE-3: avoid HarfBuzz's overflow/repack loop on large Apple layout tables."""
    font.cfg[USE_HARFBUZZ_REPACKER] = False


def subset_font(font: TTFont, codepoints) -> None:
    options = subset_options()
    options.layout_features = kept_features(font)
    s = Subsetter(options)
    s.populate(unicodes=sorted(codepoints))
    s.subset(font)


def build_unicode_cmap(
    font: TTFont, best: Mapping[int, str], uvs: Sequence[CmapSubtable]
) -> tuple[list[CmapSubtable], int]:
    """Build merger-readable Unicode subtables; return their format 4 omission count."""
    # Format 4 reserves U+FFFF for its end-of-table sentinel, so a real U+FFFF mapping lives only in format 12.
    bmp = sorted(cp for cp in best if cp < 0xFFFF)

    def format4(prefix_length: int) -> CmapSubtable:
        table = CmapSubtable.newSubtable(4)
        table.platformID, table.platEncID, table.language = 3, 1, 0
        table.cmap = {cp: best[cp] for cp in bmp[:prefix_length]}
        return table

    def fits(table: CmapSubtable) -> bool:
        try:
            return len(table.compile(font)) <= FORMAT4_MAX_BYTES
        except struct.error:  # N-1: the compiler packs the uint16 length before returning it.
            return False

    basic = format4(len(bmp))
    kept = len(bmp)
    if not fits(basic):
        # N-1: keep the largest deterministic prefix; format 12 carries every mapping.
        lo, hi = 0, len(bmp) - 1
        while lo < hi:
            mid = (lo + hi + 1) // 2
            if fits(format4(mid)):
                lo = mid
            else:
                hi = mid - 1
        kept = lo
        basic = format4(kept)
    omitted = sum(1 for cp in best if cp <= 0xFFFF) - kept
    tables = [basic]
    if omitted or any(cp > 0xFFFF for cp in best):
        full = CmapSubtable.newSubtable(12)
        full.platformID, full.platEncID, full.language = 3, 10, 0
        full.cmap = dict(best)
        tables.append(full)
    for table in uvs:
        table.platformID, table.platEncID = 0, 5
        tables.append(table)
    return tables, omitted


def normalize_cmap(font: TTFont) -> int:
    """ENGINE-1: preserve Apple's Unicode maps in encodings the merger understands."""
    cmap = font["cmap"]
    tables, omitted = build_unicode_cmap(
        font, font.getBestCmap() or {}, [table for table in cmap.tables if table.format == 14]
    )
    cmap.tableVersion = 0
    cmap.tables = tables
    return omitted


def cff_to_glyf(font: TTFont) -> None:
    """Replace CFF outlines with TrueType quadratic outlines.

    Adapted from fontTools Snippets/otf2ttf.py, Copyright (c) 2017 Just van Rossum, MIT License
    (https://github.com/fonttools/fonttools/blob/main/Snippets/otf2ttf.py).
    """
    upem = font["head"].unitsPerEm
    glyph_set = font.getGlyphSet()
    order = font.getGlyphOrder()
    glyf = newTable("glyf")
    glyf.glyphOrder = order
    glyf.glyphs = {}
    for name in order:
        tt_pen = TTGlyphPen(glyph_set)
        glyph_set[name].draw(Cu2QuPen(tt_pen, max_err=upem / 1000, reverse_direction=True))
        glyf.glyphs[name] = tt_pen.glyph()
    font["loca"] = newTable("loca")
    font["glyf"] = glyf
    del font["CFF "]
    if "VORG" in font:
        del font["VORG"]
    glyf.compile(font)
    hmtx = font["hmtx"]
    for name, g in glyf.glyphs.items():
        if hasattr(g, "xMin"):
            hmtx[name] = (hmtx[name][0], g.xMin)
    maxp = font["maxp"] = newTable("maxp")
    maxp.tableVersion = 0x00010000
    maxp.maxZones = 1
    maxp.maxTwilightPoints = maxp.maxStorage = maxp.maxFunctionDefs = maxp.maxInstructionDefs = 0
    maxp.maxStackElements = maxp.maxSizeOfInstructions = 0
    maxp.maxComponentElements = max((len(getattr(g, "components", [])) for g in glyf.glyphs.values()), default=0)
    maxp.compile(font)
    post = font["post"]
    post.formatType = 2.0
    post.extraNames = []
    post.mapping = {}
    post.glyphOrder = order
    try:
        post.compile(font)
    except OverflowError:
        post.formatType = 3
    font.sfntVersion = "\x00\x01\x00\x00"


def scale_font(font: TTFont, target_upem: int, scale: float) -> None:
    """Scale outlines and metrics by `scale`, expressed in `target_upem` units."""
    new_upem = round(target_upem * scale)
    if font["head"].unitsPerEm != new_upem:
        scale_upem(font, new_upem)
    font["head"].unitsPerEm = target_upem


def strip_tables(font: TTFont) -> None:
    for tag in list(font.keys()):
        if tag != "GlyphOrder" and tag not in KEEP_TABLES:
            del font[tag]


def prepare(
    material: MaterialSpec, codepoints, target_upem: int, weight: int | None, scale: float, workdir: Path, index: int
) -> PreparedFont:
    face = material.face
    warnings: list[str] = []
    issues: list[Issue] = []
    bold_added_bytes = 0
    font = load_face(material)
    notices = source_notices(font["name"])  # ADR-0012: read before instancing and subsetting change the font
    # ENGINE-7: inspect source capabilities before the early table filter removes AAT.
    aat_losses = set()
    if ("morx" in font or "mort" in font) and not script_tags(font, "GSUB"):
        aat_losses.add("morx")
    if "trak" in font:
        aat_losses.add("tracking")
    kerning_source = "kerx" in font or (
        "kern" in font and any(getattr(subtable, "format", 0) != 0 for subtable in font["kern"].kernTables)
    )
    synthesized = ensure_os2(font)
    if face.is_variable:
        try:
            font = instance_variable(font, weight)
        except Exception:
            # Some system fonts (e.g. Segoe UI Variable) carry GPOS variation indices that point
            # outside their VarStore; fontTools cannot instance those. Retry without GPOS.
            font.close()
            refuse_lost_mark_positioning(face, codepoints)
            font = load_face(material)
            synthesized = ensure_os2(font) or synthesized
            if "GPOS" in font:
                del font["GPOS"]
            try:
                font = instance_variable(font, weight)
            except Exception as e:
                raise ForgeError(
                    "prepare", face.display_name, f"cannot instance this variable font: {type(e).__name__}: {e}"
                ) from e
            warnings.append(
                "GPOS dropped: the font's variable positioning data is broken, so kerning and mark positioning are lost"
            )
    if synthesized:
        _note(
            warnings,
            issues,
            "os2_synthesized",
            "has no OS/2 table; one was made from its other tables, so its embedding permissions are unknown",
            index,
            face.display_name,
        )
    dropped = drop_unused_tables(font)
    bitmaps = sorted(set(dropped) & BITMAP_TABLES)
    if bitmaps:
        # ENGINE-12: explain the lost bitmap strikes even though outline forging succeeds.
        note = f"embedded bitmaps ({', '.join(bitmaps)}) are not kept; the forged font draws outlines at every size"
        _note(warnings, issues, "bitmaps_dropped", note, index, face.display_name)
    subset_font(font, codepoints)
    normalize_cmap(font)
    kern_to_gpos(font)  # legacy 'kern' would be dropped by the merger; GPOS survives
    if kerning_source and not has_kern_feature(font):
        aat_losses.add("kerning")
    if face.outline == "CFF":
        cff_to_glyf(font)
    # Synthetic bold runs in the material's own units, before scaling, so the extra
    # stem thickness shrinks or grows together with the glyphs.
    if weight is not None and not face.has_wght_axis:
        delta = weight - face.weight_class
        if delta >= 50:
            result = embolden(font, delta)
            bold_added_bytes = result.added_bytes
            _note(warnings, issues, "synthetic_bold", f"synthetic bold (+{result.delta})", index, face.display_name)
            if result.skipped:
                shown = ", ".join(result.skipped[:5]) + (", …" if len(result.skipped) > 5 else "")
                note = (
                    f"{len(result.skipped):,} of {result.emboldened + len(result.skipped):,} glyphs could not be made "
                    f"bolder and keep their regular outline ({shown})"
                )
                _note(warnings, issues, "bold_glyphs_skipped", note, index, face.display_name)
        elif delta <= -50:
            warnings.append("cannot make lighter than source; weight left as is")
    scale_font(font, target_upem, scale)
    strip_tables(font)
    out = Path(workdir) / f"{index}.ttf"
    try:
        disable_hb_repacker(font)
        font.save(str(out))
    except (struct.error, OverflowError, ValueError) as e:
        raise ForgeError(
            "prepare",
            face.display_name,
            f"scale {scale * 100:g}% pushes this font's coordinates past the TrueType limit; "
            f"use a smaller scale ({type(e).__name__}: {e})",
        ) from e
    finally:
        font.close()
    return PreparedFont(
        str(out),
        target_upem,
        warnings,
        issues,
        dropped,
        bold_added_bytes=bold_added_bytes,
        aat_losses=frozenset(aat_losses),
        notices=notices,
    )
