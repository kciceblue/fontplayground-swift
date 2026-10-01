"""Report the names actually saved, not the requested pre-normalization names."""

from collections.abc import Mapping
from dataclasses import dataclass

from fontTools.ttLib import TTFont

from fpengine.protocol.requests import ForgeRequestData
from fpengine.spec import ForgeReport

# The integrated engine now supplies every H9 field; WP-111 checks this stays empty.
INTERIM_REPORT_FIELDS: dict[str, list] = {}


@dataclass(frozen=True)
class OutputNames:
    family: str
    style: str
    postscript: str
    full: str
    fs_type: int


def read_output_names(path: str) -> OutputNames:
    font = TTFont(path)
    try:
        names = font["name"]
        return OutputNames(
            names.getDebugName(16) or names.getDebugName(1),
            names.getDebugName(17) or names.getDebugName(2),
            names.getDebugName(6),
            names.getDebugName(4),
            int(font["OS/2"].fsType),
        )
    finally:
        font.close()


def _get(obj: object, key: str) -> object:
    return obj[key] if isinstance(obj, Mapping) else getattr(obj, key)


def _interim(obj: object, key: str) -> object:
    try:
        return _get(obj, key)
    except (AttributeError, KeyError):
        return INTERIM_REPORT_FIELDS[key]


def forge_report(req: ForgeRequestData, engine_report: ForgeReport, names: OutputNames, duration_s: float) -> dict:
    return {
        "output_path": req.output_path,
        "family_name": names.family,
        "style_name": names.style,
        "postscript_name": names.postscript,
        "full_name": names.full,
        "total_codepoints": _get(engine_report, "total_codepoints"),
        "total_glyphs": _get(engine_report, "total_glyphs"),
        "fs_type": names.fs_type,
        "materials": [
            {
                "name": _get(material, "name"),
                "path": req.materials[i].path,
                "index": req.materials[i].index,
                "codepoints": _get(material, "codepoints"),
                "groups": list(_get(material, "groups")),
                "warnings": list(_get(material, "warnings")),
            }
            for i, material in enumerate(_get(engine_report, "materials"))
        ],
        "issues": [
            {key: _get(issue, key) for key in ("code", "severity", "material_index", "group", "message")}
            for issue in _interim(engine_report, "issues")
        ],
        "licence_notes": [
            {
                "class": _get(note, "licence_class"),
                "material_indexes": list(_get(note, "material_indexes")),
                "text": _get(note, "text"),
            }
            for note in _interim(engine_report, "licence_notes")
        ],
        "warnings": list(_get(engine_report, "warnings")),
        "duration_s": duration_s,
    }
