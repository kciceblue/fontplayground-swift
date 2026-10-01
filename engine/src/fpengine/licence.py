"""Read licence metadata without depending on the face reader."""

from __future__ import annotations

import os
import re
from collections.abc import Iterable, Sequence

SYSTEM_ROOTS = ("/System/Library/",)
OFFICE_BUNDLE_RE = re.compile(r"/Microsoft [^/]+\.app/Contents/")
OPEN_RE = re.compile(
    r"open font licen[cs]e|openfontlicense\.org|scripts\.sil\.org/ofl|apache licen[cs]e|apache\.org/licenses", re.I
)
MICROSOFT_RE = re.compile(r"microsoft supplied font", re.I)
APPLE_RE = re.compile(r"\bapple (inc|computer)\b", re.I)
LICENCE_NOTES = {
    "apple-sla": "Bundled with macOS: licensed for use on this Mac only; do not distribute the forged font.",
    "microsoft-product": (
        "Supplied with a Microsoft product: licensed for use with that product only; do not distribute the forged font."
    ),
    "unknown": "Licence unknown: check the source font's licence before you share the forged font.",
}
OPEN_NOTE = "Made from fonts under the SIL Open Font License or the Apache License: their terms apply to this font."
EMBEDDING_NOTES = {
    0x0002: "source licence forbids embedding (restricted); check before distributing",
    0x0004: "source licence allows preview & print embedding only; check before distributing",
    0x0008: "source licence allows editable embedding only; check before distributing",
}
FS_LABELS = {0: "Installable", 0x0002: "Restricted", 0x0004: "Preview & Print", 0x0008: "Editable"}
# Source notices a forge carries into its output (ADR-0012): copyright, trademark, licence URL and licence
# description, in the order they are kept when the name table runs out of room.
NOTICE_IDS = (0, 7, 14, 13)


def output_fs_type(values: Iterable[int | None]) -> int:
    """ENGINE-5: retain the strictest contributing permission and both ancillary flags."""
    combined = 0
    for value in values:
        combined |= value or 0
    usage = next((bit for bit in EMBEDDING_NOTES if combined & bit), 0)
    return usage | (combined & 0x0300)


def licence_texts(name) -> tuple[list[str], list[str]]:
    licences, copyrights = [], []
    for record in name.names:
        if record.nameID not in (0, 7, 13, 14):
            continue
        try:
            text = record.toUnicode()
        except UnicodeDecodeError:
            continue
        (licences if record.nameID in (13, 14) else copyrights).append(text)
    return licences, copyrights


def classify_licence(
    *,
    licence_texts: Sequence[str],
    copyright_texts: Sequence[str],
    vendor_id: str | None,
    path: str,
    forged: bool = False,
    roots: Sequence[str] | None = None,
) -> str:
    """CRIT-3: source notices take precedence over location, without rewriting face identity."""
    if forged:
        for licence_class in ("microsoft-product", "apple-sla", "unknown", "open"):
            note = OPEN_NOTE if licence_class == "open" else LICENCE_NOTES[licence_class]
            if any(note in text for text in licence_texts):
                return licence_class
    if any(OPEN_RE.search(text) for text in licence_texts):
        return "open"
    paths = (path, os.path.realpath(path))
    if any(MICROSOFT_RE.search(text) for text in licence_texts) or any(OFFICE_BUNDLE_RE.search(p) for p in paths):
        return "microsoft-product"
    roots = SYSTEM_ROOTS if roots is None else roots
    if (
        vendor_id == "APPL"
        or any(APPLE_RE.search(text) for text in copyright_texts)
        or any(p.startswith(root) for p in paths for root in roots)
    ):
        return "apple-sla"
    return "unknown"


def forged_licence_classes(licence_texts: Sequence[str]) -> tuple[str, ...]:
    """Every class whose note a forged font carries, so re-forging keeps all of them rather than the first."""
    return tuple(
        licence_class for licence_class, note in LICENCE_NOTES.items() if any(note in text for text in licence_texts)
    )


def vendor_id_of(os2: object | None) -> str | None:
    if os2 is None:
        return None
    return str(os2.achVendID).rstrip(" \x00") or None


def normalise_notice(text: str | None) -> str | None:
    if text is None:
        return None
    notice = " ".join(text.split())
    if len(notice) > 300:
        return notice[:299] + "…"
    return notice or None
