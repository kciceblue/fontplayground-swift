"""FontFace <-> JSON-ready dict. Code points travel as sorted, inclusive ranges (contracts §2)."""

from __future__ import annotations

from collections.abc import Iterable, Mapping
from dataclasses import asdict
from typing import Any

from fpengine.face import FontFace
from fpengine.scripts import GROUP_IDS

FACE_RECORD_KEYS: tuple[str, ...] = (
    "path",
    "index",
    "size",
    "mtime",
    "family",
    "style",
    "full_name",
    "postscript_name",
    "local_names",
    "outline",
    "is_collection",
    "is_variable",
    "axes",
    "weight_class",
    "italic",
    "upem",
    "glyph_count",
    "coverage",
    "group_counts",
    "embedding",
    "fs_type",
    "has_color",
    "supported",
    "unsupported_reason",
    "hidden",
    "suspicious_coverage",
    "ot_scripts",
    "aat",
    "shapes_groups",
    "licence",
    "has_os2",
    "is_forged",
    "font_revision",
    "unshaped",
)


def ranges(codepoints: Iterable[int]) -> list[list[int]]:
    out: list[list[int]] = []
    for cp in sorted(set(codepoints)):
        if out and cp == out[-1][1] + 1:
            out[-1][1] = cp
        else:
            out.append([cp, cp])
    return out


def expand(rs: Iterable[Iterable[int]]) -> frozenset[int]:
    return frozenset(cp for lo, hi in rs for cp in range(lo, hi + 1))


def face_to_dict(face: FontFace) -> dict:
    d = asdict(face)
    d["codepoints"] = ranges(face.codepoints)
    d["unshaped"] = ranges(face.unshaped)
    d["axes"] = [list(a) for a in face.axes]
    return d


def face_from_dict(d: dict) -> FontFace:
    d = dict(d)
    d["codepoints"] = expand(d["codepoints"])
    d["axes"] = tuple(tuple(a) for a in d["axes"])
    d["local_names"] = tuple(d.get("local_names", ()))
    d["group_counts"] = tuple((g, n) for g, n in d.get("group_counts", ()))
    d["unshaped"] = expand(d.get("unshaped", ()))
    for key in ("ot_gsub", "ot_gpos", "shapes_groups", "licence_classes"):
        d[key] = tuple(d.get(key, ()))
    return FontFace(**d)


def face_record(face: FontFace) -> dict[str, Any]:
    """Return the complete scan record, including placeholders owned by later WPs."""
    return {
        "path": face.path,
        "index": face.index,
        "size": face.size,
        "mtime": face.mtime,
        "family": face.family,
        "style": face.style,
        "full_name": face.full_name or face.display_name,
        "postscript_name": face.postscript_name,
        "local_names": list(face.local_names),
        "outline": face.outline,
        "is_collection": face.is_collection,
        "is_variable": face.is_variable,
        "axes": [
            {"tag": tag, "min": float(lo), "default": float(default), "max": float(hi)}
            for tag, lo, default, hi in face.axes
        ],
        "weight_class": face.weight_class,
        "italic": face.italic,
        "upem": face.upem,
        "glyph_count": face.glyph_count,
        "coverage": ranges(face.codepoints),
        "group_counts": {group: face.counts[group] for group in GROUP_IDS if face.counts[group]},
        "embedding": face.embedding,
        "fs_type": face.fs_type,
        "has_color": face.has_color,
        "supported": face.supported,
        "unsupported_reason": face.unsupported_reason,
        "hidden": face.hidden,
        "suspicious_coverage": face.suspicious_coverage,
        "ot_scripts": {"gsub": list(face.ot_gsub), "gpos": list(face.ot_gpos)},
        "aat": {"morx": face.aat_morx, "kerx": face.aat_kerx, "kern_v1": face.aat_kern_v1, "trak": face.aat_trak},
        "shapes_groups": list(face.shapes_groups),
        "licence": {"class": face.licence_class, "vendor_id": face.vendor_id, "notice": face.licence_notice},
        "has_os2": face.has_os2,
        "is_forged": face.is_forged,
        "font_revision": face.font_revision,
        "unshaped": ranges(face.unshaped),
    }


def face_from_record(record: Mapping[str, Any]) -> FontFace:
    """Read known fields only, so newer helper records remain forwards compatible."""
    groups = record.get("group_counts") or {}
    scripts = record.get("ot_scripts") or {}
    aat = record.get("aat") or {}
    licence = record.get("licence") or {}
    return FontFace(
        path=record["path"],
        index=record["index"],
        family=record["family"],
        style=record["style"],
        outline=record["outline"],
        is_collection=record["is_collection"],
        is_variable=record["is_variable"],
        axes=tuple((a["tag"], float(a["min"]), float(a["default"]), float(a["max"])) for a in record["axes"]),
        weight_class=record["weight_class"],
        italic=record["italic"],
        upem=record["upem"],
        glyph_count=record["glyph_count"],
        codepoints=expand(record["coverage"]),
        embedding=record["embedding"],
        has_color=record["has_color"],
        size=record["size"],
        mtime=record["mtime"],
        local_names=tuple(record.get("local_names", ())),
        group_counts=tuple((group, groups[group]) for group in GROUP_IDS if groups.get(group)),
        full_name=record.get("full_name", ""),
        postscript_name=record.get("postscript_name"),
        fs_type=record.get("fs_type"),
        has_os2=record.get("has_os2", True),
        hidden=record.get("hidden", False),
        suspicious_coverage=record.get("suspicious_coverage", False),
        ot_gsub=tuple(scripts.get("gsub", ())),
        ot_gpos=tuple(scripts.get("gpos", ())),
        aat_morx=aat.get("morx", False),
        aat_kerx=aat.get("kerx", False),
        aat_kern_v1=aat.get("kern_v1", False),
        aat_trak=aat.get("trak", False),
        font_revision=record.get("font_revision", "1.000"),
        is_forged=record.get("is_forged", False),
        vendor_id=licence.get("vendor_id"),
        licence_notice=licence.get("notice"),
        licence_class=licence.get("class", "unknown"),
        unshaped=expand(record.get("unshaped", ())),
        shapes_groups=tuple(record.get("shapes_groups", ())),
    )
