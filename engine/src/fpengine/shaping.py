"""Keep scripts together when the forged font cannot carry their original shaping."""

from __future__ import annotations

import argparse
import json
import os
import tempfile
from bisect import bisect_left
from collections import Counter
from collections.abc import Iterable, Mapping
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import TYPE_CHECKING

from fontTools.unicodedata import Scripts, category, ot_tags_from_script, script_extension

from fpengine.scripts import LABELS, group_of

if TYPE_CHECKING:
    from fpengine.face import FontFace
    from fpengine.spec import ForgeSpec

COMPLEX_GROUPS = ("hebrew", "arabic", "indic", "southeast_asian")
PRESENTATION_FORMS = ((0xFB1D, 0xFB4F), (0xFB50, 0xFDFF), (0xFE70, 0xFEFF))


@dataclass(frozen=True)
class ScriptShaping:
    script: str
    name: str
    group: str
    ot_tags: tuple[str, ...]
    marks_only: bool
    gpos_ok: bool


SCRIPT_SHAPING: dict[str, ScriptShaping] = {
    code: ScriptShaping(code, name, group, tuple(ot_tags_from_script(code)), marks_only, gpos_ok)
    for code, name, group, marks_only, gpos_ok in (
        ("Arab", "Arabic", "arabic", False, False),
        ("Hebr", "Hebrew", "hebrew", True, True),
        ("Deva", "Devanagari", "indic", False, False),
        ("Beng", "Bengali", "indic", False, False),
        ("Guru", "Gurmukhi", "indic", False, False),
        ("Gujr", "Gujarati", "indic", False, False),
        ("Orya", "Odia", "indic", False, False),
        ("Taml", "Tamil", "indic", False, False),
        ("Telu", "Telugu", "indic", False, False),
        ("Knda", "Kannada", "indic", False, False),
        ("Mlym", "Malayalam", "indic", False, False),
        ("Sinh", "Sinhala", "indic", False, False),
        ("Thai", "Thai", "southeast_asian", True, True),
        ("Laoo", "Lao", "southeast_asian", True, True),
        ("Khmr", "Khmer", "southeast_asian", False, False),
        ("Mymr", "Myanmar", "southeast_asian", False, False),
        ("Syrc", "Syriac", "other", False, False),
        ("Thaa", "Thaana", "other", True, True),
        ("Nkoo", "N'Ko", "other", False, False),
        ("Mong", "Mongolian", "other", False, False),
        ("Tibt", "Tibetan", "other", False, False),
        ("Adlm", "Adlam", "other", False, False),
        ("Rohg", "Hanifi Rohingya", "other", False, False),
    )
}
_SCRIPT_ORDER = {code: i for i, code in enumerate(SCRIPT_SHAPING)}
_SCRIPT_RANGES = tuple(
    (start, end, code) for start, end, code in zip(Scripts.RANGES, (*Scripts.RANGES[1:], 0x110000), Scripts.VALUES)
)
_TABLE_RANGES = tuple(row for row in _SCRIPT_RANGES if row[2] in SCRIPT_SHAPING)


def needs_shaping(cp: int, s: ScriptShaping) -> bool:
    if any(start <= cp <= end for start, end in PRESENTATION_FORMS):
        return False
    kind = category(chr(cp))
    return kind != "Nd" and (not s.marks_only or kind in {"Mn", "Mc", "Me"})


def satisfied(s: ScriptShaping, gsub: Iterable[str], gpos: Iterable[str]) -> bool:
    return bool(set(s.ot_tags).intersection(gsub) or s.gpos_ok and set(s.ot_tags).intersection(gpos))


def _script_members(ordered: list[int]) -> dict[str, list[int]]:
    members: dict[str, list[int]] = {code: [] for code in SCRIPT_SHAPING}
    for start, end, code in _TABLE_RANGES:
        members[code].extend(ordered[bisect_left(ordered, start) : bisect_left(ordered, end)])
    return {code: cps for code, cps in members.items() if cps}


def script_members(codepoints: Iterable[int]) -> dict[str, list[int]]:
    """Bisect Unicode ranges, avoiding a script lookup for each glyph in huge faces."""
    return _script_members(sorted(codepoints))


def explain_unshaped(codepoints: Iterable[int], gsub: Iterable[str], gpos: Iterable[str]) -> dict[int, str]:
    ordered = sorted(codepoints)
    gsub, gpos = set(gsub), set(gpos)
    unshaped: dict[int, str] = {}
    failed = set()
    for code, members in _script_members(ordered).items():
        shaping = SCRIPT_SHAPING[code]
        if not satisfied(shaping, gsub, gpos) and any(needs_shaping(cp, shaping) for cp in members):
            # ENGINE-2: move the entire script, including its digits and precomposed forms.
            failed.add(code)
            unshaped.update(dict.fromkeys(members, code))
    if not failed:
        return unshaped
    covered = set()
    shared = []
    for start, end, code in _SCRIPT_RANGES:
        lo, hi = bisect_left(ordered, start), bisect_left(ordered, end)
        if lo == hi:
            continue
        if code in {"Zyyy", "Zinh"}:
            shared.extend(ordered[lo:hi])
        elif code != "Zzzz":
            covered.add(code)
    for cp in shared:
        related = set(script_extension(chr(cp))) & covered
        if related and related <= failed:
            unshaped[cp] = min(related, key=_SCRIPT_ORDER.__getitem__)
    return unshaped


def unshaped_codepoints(codepoints: Iterable[int], gsub: Iterable[str], gpos: Iterable[str]) -> frozenset[int]:
    return frozenset(explain_unshaped(codepoints, gsub, gpos))


def shapes_groups(codepoints: Iterable[int], unshaped: Iterable[int]) -> tuple[str, ...]:
    present = {group_of(cp) for cp in set(codepoints).difference(unshaped)}
    return tuple(group for group in COMPLEX_GROUPS if group in present)


def plannable(face: FontFace) -> frozenset[int]:
    return face.codepoints - face.unshaped


def responsible_scripts(explanation: Mapping[int, str]) -> list[str]:
    """Most affected scripts first; table order breaks ties in errors and reports alike."""
    counts = Counter(explanation.values())
    return sorted(counts, key=lambda code: (-counts[code], _SCRIPT_ORDER[code]))


def join_names(names: Iterable[str], conjunction: str = "and") -> str:
    parts = list(names)
    return f"{', '.join(parts[:-1])} {conjunction} {parts[-1]}" if len(parts) > 1 else "".join(parts)


def rule_errors(spec: ForgeSpec) -> list[tuple[int, str, str]]:
    errors = []
    for group in COMPLEX_GROUPS:
        index = spec.script_rules.get(group)
        if index is None or not 0 <= index < len(spec.materials):
            continue
        face = spec.materials[index].face
        if group in shapes_groups(face.codepoints, face.unshaped) or not any(
            group_of(cp) == group for cp in face.codepoints
        ):
            continue
        explanation = explain_unshaped(face.codepoints, face.ot_gsub, face.ot_gpos)
        scripts = responsible_scripts(
            {cp: code for cp, code in explanation.items() if SCRIPT_SHAPING[code].group == group}
        )
        names = join_names(SCRIPT_SHAPING[code].name for code in scripts)
        reason = (
            f"shapes {names} with Apple-only rules (AAT) that can't be carried over"
            if face.aat_morx
            else f"has no OpenType shaping rules for {names}"
        )
        message = f"{face.display_name} can't draw {LABELS[group]} in the forged font: it {reason}."
        alternatives = OT_ALTERNATIVES[scripts[0]] if scripts else ()
        if alternatives:
            choices = join_names((alternative.family for alternative in alternatives[:3]), "or")
            message += f" Choose an OpenType font instead, for example {choices}."
        errors.append((index, group, message))
    return errors


@dataclass(frozen=True)
class Alternative:
    family: str
    postscript_name: str
    where: str


OT_ALTERNATIVES: dict[str, tuple[Alternative, ...]] = {
    "Arab": (
        Alternative("Damascus", "Damascus", "system"),
        Alternative("Noto Nastaliq Urdu", "NotoNastaliqUrdu", "system"),
        Alternative("Arial", "ArialMT", "system"),
        Alternative("Times New Roman", "TimesNewRomanPSMT", "system"),
        Alternative("Tahoma", "Tahoma", "system"),
        Alternative("Courier New", "CourierNewPSMT", "system"),
        Alternative("Microsoft Sans Serif", "MicrosoftSansSerif", "system"),
    ),
    "Hebr": (
        Alternative("Arial Hebrew", "ArialHebrew", "system"),
        Alternative("Arial Hebrew Scholar", "ArialHebrewScholar", "system"),
        Alternative("Arial", "ArialMT", "system"),
        Alternative("Times New Roman", "TimesNewRomanPSMT", "system"),
        Alternative("Tahoma", "Tahoma", "system"),
    ),
    "Deva": (
        Alternative("Kohinoor Devanagari", "KohinoorDevanagari-Regular", "system"),
        Alternative("ITF Devanagari", "ITFDevanagari-Book", "system"),
        Alternative("Devanagari Sangam MN", "DevanagariSangamMN", "system"),
        Alternative("Shree Devanagari 714", "ShreeDev0714", "system"),
    ),
    "Beng": (
        Alternative("Kohinoor Bangla", "KohinoorBangla-Regular", "system"),
        Alternative("Bangla Sangam MN", "BanglaSangamMN", "system"),
        Alternative("Bangla MN", "BanglaMN", "system"),
        Alternative("Tiro Bangla", "TiroBangla", "asset"),
    ),
    "Guru": (
        Alternative("Gurmukhi Sangam MN", "GurmukhiSangamMN", "system"),
        Alternative("Gurmukhi MN", "GurmukhiMN", "system"),
    ),
    "Gujr": (
        Alternative("Kohinoor Gujarati", "KohinoorGujarati-Regular", "system"),
        Alternative("Gujarati Sangam MN", "GujaratiSangamMN", "system"),
    ),
    "Orya": (
        Alternative("Oriya Sangam MN", "OriyaSangamMN", "system"),
        Alternative("Oriya MN", "OriyaMN", "system"),
        Alternative("Noto Sans Oriya", "NotoSansOriya", "system"),
    ),
    "Taml": (
        Alternative("Tamil MN", "TamilMN", "system"),
        Alternative("InaiMathi", "InaiMathi", "system"),
        Alternative("Tamil Sangam MN", "TamilSangamMN-Medium", "asset"),
    ),
    "Telu": (
        Alternative("Kohinoor Telugu", "KohinoorTelugu-Regular", "system"),
        Alternative("Telugu Sangam MN", "TeluguSangamMN", "system"),
        Alternative("Telugu MN", "TeluguMN", "system"),
    ),
    "Knda": (
        Alternative("Kannada Sangam MN", "KannadaSangamMN", "system"),
        Alternative("Kannada MN", "KannadaMN", "system"),
        Alternative("Noto Sans Kannada", "NotoSansKannada-Regular", "system"),
    ),
    "Mlym": (
        Alternative("Sama Malayalam", "SamaMalayalam-Regular", "asset"),
        Alternative("Baloo Chettan 2", "BalooChettan2-Regular", "asset"),
    ),
    "Sinh": (
        Alternative("Sinhala Sangam MN", "SinhalaSangamMN", "system"),
        Alternative("Sinhala MN", "SinhalaMN", "system"),
    ),
    "Thai": (
        Alternative("Sukhumvit Set", "SukhumvitSet-Text", "system"),
        Alternative("Tahoma", "Tahoma", "system"),
        Alternative("Microsoft Sans Serif", "MicrosoftSansSerif", "system"),
    ),
    "Laoo": (
        Alternative("Lao Sangam MN", "LaoSangamMN", "system"),
        Alternative("Lao MN", "LaoMN", "system"),
    ),
    "Khmr": (
        Alternative("Khmer Sangam MN", "KhmerSangamMN", "system"),
        Alternative("Khmer MN", "KhmerMN", "system"),
    ),
    "Mymr": (
        Alternative("Myanmar Sangam MN", "MyanmarSangamMN", "system"),
        Alternative("Myanmar MN", "MyanmarMN", "system"),
        Alternative("Noto Sans Myanmar", "NotoSansMyanmar-Regular", "system"),
    ),
    "Syrc": (Alternative("Noto Sans Syriac", "NotoSansSyriac-Regular", "system"),),
    "Thaa": (Alternative("Noto Sans Thaana", "NotoSansThaana-Regular", "system"),),
    "Nkoo": (Alternative("Noto Sans NKo", "NotoSansNKo-Regular", "system"),),
    "Mong": (Alternative("Noto Sans Mongolian", "NotoSansMongolian-Regular", "system"),),
    "Tibt": (),
    "Adlm": (Alternative("Noto Sans Adlam", "NotoSansAdlam-Regular", "system"),),
    "Rohg": (Alternative("Noto Sans Hanifi Rohingya", "NotoSansHanifiRohingya-Regular", "system"),),
}


def fixture_payload() -> dict:
    from fpengine import __version__

    return {
        "header": {
            "generator": "python -m fpengine.shaping write-fixture",
            "fpengine_version": __version__,
            "inputs": ["engine/src/fpengine/shaping.py"],
        },
        "complex_groups": list(COMPLEX_GROUPS),
        "scripts": [dict(asdict(script), ot_tags=list(script.ot_tags)) for script in SCRIPT_SHAPING.values()],
        "alternatives": {
            code: [asdict(alternative) for alternative in entries] for code, entries in OT_ALTERNATIVES.items()
        },
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("write-fixture",))
    parser.add_argument("path", type=Path)
    args = parser.parse_args()
    args.path.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=args.path.parent, delete=False) as stream:
            temporary = Path(stream.name)
            json.dump(fixture_payload(), stream, ensure_ascii=False, indent=2, sort_keys=False)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, args.path)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


if __name__ == "__main__":
    main()
