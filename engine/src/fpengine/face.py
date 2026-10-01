"""FontFace metadata and reading it from font files."""

from __future__ import annotations

from dataclasses import dataclass
from functools import cached_property
from pathlib import Path

from fontTools.ttLib import TTCollection, TTFont

from fpengine.licence import (
    NOTICE_IDS,
    classify_licence,
    forged_licence_classes,
    licence_texts,
    normalise_notice,
    vendor_id_of,
)
from fpengine.naming import FORGED_NOTICE
from fpengine.scripts import GROUP_IDS, group_of
from fpengine.shaping import shapes_groups, unshaped_codepoints

READER_VERSION = 8
SUSPICIOUS_MIN_CODEPOINTS = 256
SUSPICIOUS_RATIO = 4
COLOR_TABLES = ("COLR", "CBDT", "sbix", "SVG ")
# Languages whose native family name is most useful, first: Chinese (PRC, Singapore, Taiwan, Hong Kong, Macao),
# Japanese, Korean; any other language follows by language ID.
LOCAL_LANGS = (0x804, 0x1004, 0x404, 0xC04, 0x1404, 0x411, 0x412)
MAC_LANG_TO_LCID = {33: 0x804, 19: 0x404, 11: 0x411, 23: 0x412}


@dataclass(frozen=True)
class FontFace:
    path: str
    index: int
    family: str
    style: str
    outline: str  # "glyf" | "CFF" | "CFF2" | "none"
    is_collection: bool
    is_variable: bool
    axes: tuple[tuple[str, float, float, float], ...]
    weight_class: int
    italic: bool
    upem: int
    glyph_count: int
    codepoints: frozenset[int]
    embedding: str  # "installable" | "editable" | "preview-print" | "restricted"
    has_color: bool
    size: int
    mtime: float
    local_names: tuple[str, ...] = ()  # native family names (微软雅黑), most useful first
    group_counts: tuple[tuple[str, int], ...] = ()  # (group id, characters) for non-empty groups, GROUPS order
    full_name: str = ""
    postscript_name: str | None = None
    fs_type: int | None = None
    has_os2: bool = True
    hidden: bool = False
    suspicious_coverage: bool = False
    ot_gsub: tuple[str, ...] = ()
    ot_gpos: tuple[str, ...] = ()
    aat_morx: bool = False
    aat_kerx: bool = False
    aat_kern_v1: bool = False
    aat_trak: bool = False
    font_revision: str = "1.000"
    is_forged: bool = False
    vendor_id: str | None = None
    licence_notice: str | None = None
    licence_class: str = "unknown"
    # A forged face made from several non-open classes carries a note for each; () means just licence_class.
    licence_classes: tuple[str, ...] = ()
    unshaped: frozenset[int] = frozenset()
    shapes_groups: tuple[str, ...] = ()

    @property
    def key(self) -> tuple[str, int]:
        return (self.path, self.index)

    @property
    def display_name(self) -> str:
        return f"{self.family} {self.style}"

    @property
    def format_tag(self) -> str:
        if self.is_variable:
            return "VAR"
        if self.is_collection:
            return "TTC"
        return "OTF" if self.outline.startswith("CFF") else "TTF"

    @property
    def has_wght_axis(self) -> bool:
        return any(a[0] == "wght" for a in self.axes)

    @property
    def unsupported_reason(self) -> str | None:
        if self.outline == "none":
            return "bitmap-only font (no outlines)"
        if self.outline == "CFF2":
            return "CFF2 outlines are not supported"
        if self.has_color:
            return "colour fonts are not supported"
        if not self.codepoints:
            return "no Unicode characters (symbol or empty character map)"
        return None

    @property
    def supported(self) -> bool:
        return self.unsupported_reason is None

    @cached_property
    def counts(self) -> dict[str, int]:
        """Characters per script group, every group present (0 when empty). Treat it as read-only."""
        counts = dict.fromkeys(GROUP_IDS, 0)
        if self.group_counts:
            counts.update(self.group_counts)
        else:  # a face built by hand (tests) or read by an older reader
            for cp in self.codepoints - self.unshaped:
                counts[group_of(cp)] += 1
        return counts

    @cached_property
    def scripts(self) -> list[str]:
        return [g for g in GROUP_IDS if self.counts[g]]


def _embedding(fs_type: int) -> str:
    if fs_type & 0x0002:
        return "restricted"
    if fs_type & 0x0004:
        return "preview-print"
    if fs_type & 0x0008:
        return "editable"
    return "installable"


def _name_rank(record) -> int | None:
    """Rank of a name record whose text decodes reliably, lower first; None for records left to fontTools."""
    if record.platformID == 3 and record.platEncID in (0, 1, 10):  # Windows Unicode, what Windows itself shows
        return 0 if record.langID == 0x409 else 2
    if (record.platformID, record.platEncID, record.langID) == (1, 0, 0):
        # CATALOG-3: Apple's English names win, but EPSON's mislabeled Shift-JIS must not.
        if all(0x20 <= byte <= 0x7E for byte in record.toBytes()):
            return 1
    if record.platformID == 1 and record.platEncID in (1, 2, 3, 25):
        return 3
    return None


def _decode(record) -> str | None:
    try:
        return record.toUnicode()
    except UnicodeDecodeError:
        return None


def _best_name(name, name_ids) -> str | None:
    """CATALOG-3 / ENGINE-M4: an English legacy name beats a native-only typographic name."""
    for name_id in name_ids:
        english = [r for r in name.names if r.nameID == name_id and _name_rank(r) in (0, 1)]
        for record in sorted(english, key=_name_rank):
            text = _decode(record)
            if text:
                return text
    for name_id in name_ids:
        ranked = [r for r in name.names if r.nameID == name_id and _name_rank(r) is not None]
        for record in sorted(ranked, key=_name_rank):
            text = _decode(record)
            if text:
                return text
        text = name.getDebugName(name_id)
        if text:
            return text
    return None


def _local_names(name, family: str) -> tuple[str, ...]:
    """Non-English family names: per language the typographic family (name ID 16) else the family (ID 1).

    Windows-Unicode records first; Mac CJK ones only when there is no Windows one. Names equal to `family`
    (ignoring case) and duplicates are dropped; LOCAL_LANGS order first, then by language ID.
    """

    def collect(accept, *, mac_languages: bool = False) -> dict[int, str]:
        found: dict[int, str] = {}
        for name_id in (16, 1):
            for record in name.names:
                if record.nameID != name_id or not accept(record):
                    continue
                language = (
                    MAC_LANG_TO_LCID.get(record.langID, 0x10000 + record.langID) if mac_languages else record.langID
                )
                if language in found:
                    continue
                try:
                    text = record.toUnicode().strip()
                except UnicodeDecodeError:
                    continue
                if text:
                    found[language] = text
        return found

    found = collect(lambda r: r.platformID == 3 and r.platEncID in (0, 1, 10) and r.langID != 0x409)
    if not found:
        # CATALOG-M2: map Macintosh language IDs before applying the existing CJK preference order.
        found = collect(lambda r: r.platformID == 1 and r.platEncID in (1, 2, 3, 25), mac_languages=True)
    rank = {lang: i for i, lang in enumerate(LOCAL_LANGS)}
    names: list[str] = []
    for lang in sorted(found, key=lambda lang: (rank.get(lang, len(rank)), lang)):
        text = found[lang]
        if text.casefold() != family.casefold() and text not in names:
            names.append(text)
    return tuple(names)


def _group_counts(codepoints) -> tuple[tuple[str, int], ...]:
    counts = dict.fromkeys(GROUP_IDS, 0)
    for cp in codepoints:
        counts[group_of(cp)] += 1
    return tuple((g, n) for g, n in counts.items() if n)


def _head(font: TTFont):
    # CATALOG-8: bitmap-only system fonts may carry bhed instead of head.
    return font["head"] if "head" in font else font["bhed"]


def is_hidden(family: str, postscript_name: str | None) -> bool:
    """CATALOG-2 / ENGINE-10: private families and private face names are both hidden."""
    return family.startswith(".") or (postscript_name or "").startswith(".")


def is_suspicious_coverage(n_codepoints: int, glyph_count: int) -> bool:
    """CATALOG-2: flag LastResort-like coverage without excluding usable small fonts."""
    return n_codepoints >= SUSPICIOUS_MIN_CODEPOINTS and n_codepoints > SUSPICIOUS_RATIO * glyph_count


def script_tags(font: TTFont, tag: str) -> tuple[str, ...]:
    """ENGINE-2: malformed layout metadata must not make an otherwise readable face fail."""
    try:
        if tag not in font or font[tag].table.ScriptList is None:
            return ()
        tags = {record.ScriptTag for record in font[tag].table.ScriptList.ScriptRecord}
        return tuple(sorted(script for script in tags if isinstance(script, str) and len(script) == 4))
    except Exception:
        return ()


def is_apple_kern(font: TTFont) -> bool:
    """Read the Apple kern header without decompiling its potentially large subtables."""
    try:
        if "kern" not in font:
            return False
        if font.reader is not None and "kern" in font.reader:
            return bytes(font.reader["kern"][:4]) == b"\x00\x01\x00\x00"
        return float(getattr(font["kern"], "version", 0)) == 1.0
    except Exception:
        return False


def _is_forged(name) -> bool:
    return (name.getDebugName(0) or "").startswith(FORGED_NOTICE)


def source_notices(name) -> tuple[tuple[int, str], ...]:
    """(name ID, text) of each notice a forge must carry over, in NOTICE_IDS order, each on one line.

    A forged font already holds its sources' notices one per line, after its own first line (the marker in
    name ID 0, the licence-class notes in ID 13), so re-forging carries them without nesting the marker.
    """
    forged = _is_forged(name)
    notices: list[tuple[int, str]] = []
    for name_id in NOTICE_IDS:
        text = _best_name(name, (name_id,))
        if not text:
            continue
        lines = text.splitlines() if forged else [text]
        if forged and (name_id == 13 or (name_id == 0 and lines[0].startswith(FORGED_NOTICE))):
            lines = lines[1:]
        for line in lines:
            notice = " ".join(line.split())
            if notice and (name_id, notice) not in notices:
                notices.append((name_id, notice))
    return tuple(notices)


def _face(font: TTFont, path: Path, index: int, is_collection: bool, size: int, mtime: float) -> FontFace:
    name = font["name"]
    fvar = font["fvar"] if "fvar" in font else None
    os2 = font["OS/2"] if "OS/2" in font else None
    if "glyf" in font:
        outline = "glyf"
    elif "CFF " in font:
        outline = "CFF"
    elif "CFF2" in font:
        outline = "CFF2"
    else:
        outline = "none"
    head = _head(font)
    family = _best_name(name, (21, 16, 1)) or path.stem
    style = _best_name(name, (22, 17, 2)) or "Regular"
    postscript_name = (name.getDebugName(6) or "").strip() or None
    codepoints = frozenset(font.getBestCmap() or {})
    ot_gsub, ot_gpos = script_tags(font, "GSUB"), script_tags(font, "GPOS")
    unshaped = unshaped_codepoints(codepoints, ot_gsub, ot_gpos)
    glyph_count = int(font["maxp"].numGlyphs)
    forged = _is_forged(name)
    vendor = vendor_id_of(os2)
    licences, copyrights = licence_texts(name)
    carried = forged_licence_classes(licences) if forged else ()
    return FontFace(
        path=str(path),
        index=index,
        family=family,
        style=style,
        outline=outline,
        is_collection=is_collection,
        is_variable=fvar is not None,
        axes=tuple((a.axisTag, float(a.minValue), float(a.defaultValue), float(a.maxValue)) for a in fvar.axes)
        if fvar
        else (),
        weight_class=int(os2.usWeightClass) if os2 else (700 if head.macStyle & 1 else 400),
        italic=bool(os2.fsSelection & 1) if os2 else bool(head.macStyle & 2),
        upem=int(head.unitsPerEm),
        glyph_count=glyph_count,
        codepoints=codepoints,
        embedding=_embedding(int(os2.fsType)) if os2 else "installable",
        has_color=any(t in font for t in COLOR_TABLES),
        size=size,
        mtime=mtime,
        local_names=_local_names(name, family),
        group_counts=_group_counts(codepoints - unshaped),
        unshaped=unshaped,
        shapes_groups=shapes_groups(codepoints, unshaped),
        full_name=_best_name(name, (4,)) or f"{family} {style}",
        postscript_name=postscript_name,
        fs_type=int(os2.fsType) if os2 else None,
        has_os2=os2 is not None,
        hidden=is_hidden(family, postscript_name),
        suspicious_coverage=is_suspicious_coverage(len(codepoints), glyph_count),
        ot_gsub=ot_gsub,
        ot_gpos=ot_gpos,
        aat_morx="morx" in font or "mort" in font,
        aat_kerx="kerx" in font,
        aat_kern_v1=is_apple_kern(font),
        aat_trak="trak" in font,
        font_revision=f"{float(head.fontRevision):.3f}",
        is_forged=forged,
        vendor_id=vendor,
        licence_notice=normalise_notice(_best_name(name, (13,)) or _best_name(name, (0,))),
        licence_class=classify_licence(
            licence_texts=licences, copyright_texts=copyrights, vendor_id=vendor, path=str(path), forged=forged
        ),
        licence_classes=carried if len(carried) > 1 else (),
    )


def read_faces(path: str | Path) -> list[FontFace]:
    """Read every face in a font file. Raises on unreadable files."""
    p = Path(path)
    st = p.stat()
    if p.suffix.lower() in (".ttc", ".otc"):
        coll = TTCollection(str(p), lazy=True)
        try:
            return [_face(f, p, i, True, st.st_size, st.st_mtime) for i, f in enumerate(coll.fonts)]
        finally:
            coll.close()
    font = TTFont(str(p), lazy=True)
    try:
        return [_face(font, p, 0, False, st.st_size, st.st_mtime)]
    finally:
        font.close()


def read_face(path: str | Path, index: int) -> FontFace:
    """Read only the requested face; IndexError carries the available face count."""
    p = Path(path)
    st = p.stat()
    if p.suffix.lower() in (".ttc", ".otc"):
        coll = TTCollection(str(p), lazy=True)
        try:
            if not 0 <= index < len(coll.fonts):
                raise IndexError(len(coll.fonts))
            return _face(coll.fonts[index], p, index, True, st.st_size, st.st_mtime)
        finally:
            coll.close()
    if index != 0:
        raise IndexError(1)
    font = TTFont(str(p), lazy=True)
    try:
        return _face(font, p, 0, False, st.st_size, st.st_mtime)
    finally:
        font.close()
