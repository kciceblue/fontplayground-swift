import random

from common import ALPHABET, SEED, fixture

from fpengine.records import ranges
from fpengine.scripts import GROUP_IDS, LABELS, group_of, groups_covered

SAMPLE_TEXT = "a1,éΩдبאनก한あ漢，、→☺€😀\u1200"


def generate() -> dict:
    runs = []
    for cp in range(0x110000):
        group = group_of(cp)
        if runs and runs[-1][2] == group:
            runs[-1][1] = cp
        else:
            runs.append([cp, cp, group])
    rng = random.Random(SEED)
    cases = [{ord("漢"), ord("a"), 0xFF0C}]
    cases += [{cp for cp in ALPHABET if rng.random() < 0.5} for _ in range(16)]
    return {
        "scripts/group-ranges.json": fixture(
            "scripts/group-ranges",
            ["fpengine.scripts.group_of", "fpengine.scripts.groups_covered"],
            seed=SEED,
            groups=GROUP_IDS,
            labels=LABELS,
            ranges=runs,
            samples=[[ord(character), group_of(ord(character))] for character in SAMPLE_TEXT],
            groups_covered=[{"codepoints": ranges(values), "expected": groups_covered(values)} for values in cases],
        )
    }
