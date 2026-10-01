"""Build synthetic test fonts for FPMacServicesTests (never real fonts).

stdin: {"out_dir": "<dir>", "fonts": [<spec>, ...]}; stdout: {"files": ["<abs path>", ...]}.
<spec>: {"file": "A.ttf", "family": "FP Test A", "style": "Regular", "postscript_name": null, "full_name": null,
         "chars": "abc", "notice": null, "weight_class": 400, "os2": true,
         "axes": [{"tag": "wght", "min": 100, "default": 400, "max": 900}], "stat": true, "fea": null,
         "localized_family": {"0x0804": "测试字体"}}
A spec with "faces": [<spec>, ...] (and "file" ending in .ttc) builds a collection of those faces.
Glyph names are uniXXXX (uXXXXX above the BMP). Glyph i is a rectangle whose width encodes i,
so fonts that share names still differ in outlines.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

from fontTools.feaLib.builder import addOpenTypeFeaturesFromString
from fontTools.fontBuilder import FontBuilder
from fontTools.otlLib.builder import buildStatTable
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib import TTFont
from fontTools.ttLib.tables._g_v_a_r import TupleVariation
from fontTools.ttLib.ttCollection import TTCollection


def _gname(cp: int) -> str:
    return f"uni{cp:04X}" if cp <= 0xFFFF else f"u{cp:05X}"


def _glyph(i: int):
    pen = TTGlyphPen(None)
    right = 150 + 10 * (i % 30)
    pen.moveTo((100, 0))
    pen.lineTo((100, 700))
    pen.lineTo((right + 100, 700))
    pen.lineTo((right + 100, 0))
    pen.closePath()
    return pen.glyph()


def build_face(spec: dict) -> TTFont:
    chars = spec.get("chars", "abc")
    cps = [ord(c) for c in chars]
    names = [".notdef"] + [_gname(cp) for cp in cps]
    cmap = {cp: _gname(cp) for cp in cps}
    family, style = spec["family"], spec.get("style", "Regular")
    fb = FontBuilder(1000, isTTF=True)
    fb.setupGlyphOrder(names)
    fb.setupCharacterMap(cmap)
    fb.setupGlyf({n: _glyph(i) for i, n in enumerate(names)})
    fb.setupHorizontalMetrics({n: (600, 100) for n in names})
    fb.setupHorizontalHeader(ascent=800, descent=-200)
    ps = spec.get("postscript_name") or f"{family.replace(' ', '')}-{style.replace(' ', '')}"
    name = {
        "familyName": family,
        "styleName": style,
        "psName": ps,
        "fullName": spec.get("full_name") or f"{family} {style}",
        "uniqueFontIdentifier": f"{ps};test",
    }
    if spec.get("notice"):
        name["copyright"] = spec["notice"]  # name ID 0
    fb.setupNameTable(name)
    for lang, text in (spec.get("localized_family") or {}).items():  # e.g. {"0x0804": "测试字体"}: Windows records
        fb.font["name"].setName(text, 1, 3, 1, int(lang, 16))
    if spec.get("os2", True):
        fb.setupOS2(
            usWeightClass=int(spec.get("weight_class", 400)),
            sTypoAscender=800,
            sTypoDescender=-200,
            usWinAscent=800,
            usWinDescent=200,
        )
    fb.setupPost()
    axes = spec.get("axes") or []
    if axes:
        fb.setupFvar([(a["tag"], a["min"], a["default"], a["max"], a["tag"]) for a in axes], [])
        deltas = {"wght": [(0, 0), (0, 0), (200, 0), (200, 0)], "opsz": [(0, 0), (0, 100), (0, 100), (0, 0)]}
        fb.setupGvar(
            {
                n: [
                    TupleVariation({a["tag"]: (0, 1.0, 1.0)}, deltas.get(a["tag"], [(0, 0)] * 4) + [(0, 0)] * 4)
                    for a in axes
                ]
                for n in names
            }
        )
        if spec.get("stat", True):  # CoreText applies automatic optical sizing only to fonts with STAT (F7)
            buildStatTable(
                fb.font,
                [
                    {
                        "tag": a["tag"],
                        "name": a["tag"],
                        "values": [{"value": a["default"], "name": "Default", "flags": 2}],
                    }
                    for a in axes
                ],
            )
    if spec.get("fea"):  # OpenType feature code (feaLib syntax), e.g. a Latin-only GSUB (F8)
        addOpenTypeFeaturesFromString(fb.font, spec["fea"])
    return fb.font


def main() -> int:
    req = json.load(sys.stdin)
    out = Path(req["out_dir"])
    out.mkdir(parents=True, exist_ok=True)
    files = []
    for spec in req["fonts"]:
        path = out / spec["file"]
        if "faces" in spec:
            coll = TTCollection()
            coll.fonts = [build_face(f) for f in spec["faces"]]
            coll.save(str(path))
        else:
            build_face(spec).save(str(path))
        files.append(str(path))
    json.dump({"files": files}, sys.stdout)
    return 0


if __name__ == "__main__":
    sys.exit(main())
