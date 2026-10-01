"""Capture the engine's collision-resistant PostScript names."""

import random
import unicodedata

from common import SEED, fixture

from fpengine.naming import postscript_name
from fpengine.scripts import GROUP_IDS, group_of

WORKED_PAIRS = (
    ("Avenir Next PingFang", "Regular"),
    ("Avenir Next", "Regular"),
    ("我的字体", "Regular"),
    ("你的字体", "Regular"),
    ("Noto 我的", "Regular"),
    ("Noto 你的", "Regular"),
    ("甲字体", "粗体"),
    ("甲字体", "细体"),
    ("My Font", "Bold Italic"),
    ("MyFont", "Bold Italic"),
    ("  Forged Test ", " Regular "),
    ("A Very Long Family Name That Keeps Going And Going Forever", "Extra Condensed Semibold Italic"),
)
EXTRA_PAIRS = (
    ("Forged Test", "Regular"),
    ("合体字体", "Regular"),
    ("合体字体", "粗体"),
    ("中文", "Regular"),
    ("日本語", "Regular"),
    ("한글", "Bold"),
    ("Helvetica Neue PingFang SC", "Regular"),
    ("Avenir Next", "Regular"),
    ("Forged", "Regular"),
    ("", ""),
    ("  ", "Regular"),
    ("A" * 80, "Regular"),
    ("Fixture Sans CJK", "Regular"),
    ("Café Crème", "Italic"),
    ("Segoe UI YaHei", "Semibold Italic"),
    ("123", "456"),
    ("-", "-"),
    ("Noto Sans CJK SC", "Black"),
    ("😀 Emoji", "Regular"),
    ("Fixture Sans", "Bold"),
    ("Fixture Sans", "Bold "),
    ("Fixture\tSans", "Bold"),
    ("ΑΒΓ", "Regular"),
    ("Кириллица", "Bold"),
)


def postscript_pairs() -> list[tuple[str, str]]:
    pairs = list(WORKED_PAIRS) + [
        ("", "Regular"),
        ("Café", "Regular"),
        ("Cafe\u0301", "Regular"),
        ("　Noto ", "Regular"),
    ]
    alphabets = {group: [] for group in GROUP_IDS}
    for cp in range(0x21, 0x110000):
        group = group_of(cp)
        if len(alphabets[group]) < 64 and unicodedata.category(chr(cp))[0] in "LNPS":
            alphabets[group].append(chr(cp))
        if all(len(alphabet) == 64 for alphabet in alphabets.values()):
            break
    rng = random.Random(SEED)
    for group in GROUP_IDS:
        for _ in range(20):
            characters = [rng.choice(alphabets[group]) for _ in range(rng.randint(1, 3))]
            family = characters[0] + "".join((" " if rng.random() < 0.3 else "") + char for char in characters[1:])
            pairs.append((family, rng.choice(("Regular", "Bold", "Italic", "Bold Italic", "粗体"))))
    return list(dict.fromkeys(pairs + list(EXTRA_PAIRS)))


def generate() -> dict:
    return {
        "naming/postscript_names.json": fixture(
            "naming/postscript_names",
            ["fpengine.naming.postscript_name", "fpengine.scripts.group_of"],
            seed=SEED,
            cases=[[family, style, postscript_name(family, style)] for family, style in postscript_pairs()],
        )
    }
