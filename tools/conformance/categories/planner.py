import random

from common import ALPHABET, SEED, fixture

from fpengine.planner import source_of
from fpengine.records import ranges
from fpengine.scripts import GROUP_IDS

REFERENCE_CASES = (
    ("test_priority_order_wins_without_rules", ("abc1", "ab漢，"), {}),
    ("test_rule_overrides_priority", ("abc1", "ab漢，"), {"latin": 1}),
    ("test_rule_falls_back_when_material_lacks_char", ("ab漢，", "abc1"), {"han": 1}),
    ("test_assignments_are_disjoint_and_complete", ("abc1", "ab漢，"), {}),
    ("test_source_of_prefers_the_rule_font_when_it_has_the_character", ("a漢", "a漢b"), {"han": 1}),
    ("test_source_of_falls_back_to_priority_order_then_none", ("a", "漢"), {"han": 0, "latin": 7}),
    ("test_source_of_agrees_with_the_plan", ("abc1,", "ab漢，"), {"latin": 1, "han": 1}),
)


def _case(name, sets, rules, queries):
    assignments = [set() for _ in sets]
    for cp in sorted(set().union(*sets)):
        assignments[source_of(cp, sets, rules)].add(cp)
    return {
        "name": name,
        "coverages": [ranges(values) for values in sets],
        "rules": rules,
        "assignments": [ranges(values) for values in assignments],
        "queries": [[cp, source_of(cp, sets, rules)] for cp in sorted(set(queries))],
    }


def generate() -> dict:
    cases = []
    for name, texts, rules in REFERENCE_CASES:
        sets = [set(map(ord, text)) for text in texts]
        cases.append(_case(name, sets, rules, set().union(*sets) | {ord("한"), 0x10FFFF}))
    rng = random.Random(SEED)
    for index in range(64):
        n = rng.randint(1, 4)
        sets = [{cp for cp in ALPHABET if rng.random() < 0.5} for _ in range(n)]
        rules = {group: rng.choice([None, *range(n), n, 7, -1]) for group in GROUP_IDS if rng.random() < 0.4}
        cases.append(_case(f"random_{index:02}", sets, rules, (*ALPHABET, 0xE000, 0x10FFFF)))
    return {
        "planner/cases.json": fixture(
            "planner/cases", ["fpengine.planner.source_of", "fpengine.scripts.group_of"], seed=SEED, cases=cases
        )
    }
