"""Stable font identity and per-forge versions, independent of the installed catalog."""

from __future__ import annotations

import re
import secrets
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path

from fontTools.ttLib import TTFont
from fontTools.ttLib.tables._n_a_m_e import table__n_a_m_e

FORGED_NOTICE = "Forged with Font Playground"
MAX_POSTSCRIPT = 63
MAX_STYLE_PART = 20
TAG_PREFIX = "FP"
VERSION_EPOCH = datetime(2000, 1, 1, tzinfo=UTC)


def clean_name(s: str) -> str:
    """Keep Python's whitespace semantics without normalising Unicode spellings."""
    return s.strip()


def ascii_alnum(s: str) -> str:
    return re.sub(r"[^A-Za-z0-9]", "", s)


def fnv1a64(data: bytes) -> int:
    value = 0xCBF29CE484222325
    for byte in data:
        value = ((value ^ byte) * 0x100000001B3) & 0xFFFFFFFFFFFFFFFF
    return value


def name_tag(family: str, style: str) -> str:
    value = fnv1a64(clean_name(family).encode("utf-8") + b"\0" + clean_name(style).encode("utf-8"))
    return f"{(value >> 32) ^ (value & 0xFFFFFFFF):08x}"


def postscript_name(family: str, style: str) -> str:
    """INSTALL-5: retain the full Unicode names in the hash before ASCII truncation."""
    family, style = clean_name(family), clean_name(style)
    tag = TAG_PREFIX + name_tag(family, style)
    style_part = (ascii_alnum(style) or "Regular")[:MAX_STYLE_PART]
    family_part = (ascii_alnum(family) or "Forged")[: MAX_POSTSCRIPT - 1 - len(style_part) - len(tag)]
    return f"{family_part}{tag}-{style_part}"


@dataclass(frozen=True)
class ForgeStamp:
    when: datetime
    nonce: str


def new_stamp() -> ForgeStamp:
    return ForgeStamp(datetime.now(UTC).replace(microsecond=0), secrets.token_hex(4))


def version_parts(stamp: ForgeStamp) -> tuple[int, int]:
    elapsed = stamp.when - VERSION_EPOCH
    if elapsed.days < 0 or elapsed.days > 32767:
        raise ValueError("Forge date is outside the signed 16.16 font version range.")
    return elapsed.days, elapsed.seconds * 100000 // 86400


def version_string(stamp: ForgeStamp) -> str:
    days, fraction = version_parts(stamp)
    return f"Version {days}.{fraction:05d}"


def font_revision(stamp: ForgeStamp) -> float:
    days, fraction = version_parts(stamp)
    return days + fraction / 100000


def unique_id(full_name: str, stamp: ForgeStamp) -> str:
    return f"{full_name}; FontPlayground {stamp.when:%Y-%m-%dT%H:%M:%SZ}; {stamp.nonce}"


def is_forged_name_table(name_table: table__n_a_m_e) -> bool:
    return (name_table.getDebugName(0) or "").startswith(FORGED_NOTICE)


def is_forged(path: str | Path, index: int = 0) -> bool:
    """Recognise both this app's output and fonts forged by the original Windows app."""
    try:
        with TTFont(str(path), lazy=True, fontNumber=index) as font:
            return "name" in font and is_forged_name_table(font["name"])
    except Exception:  # Missing, unreadable, malformed, or not a font.
        return False
