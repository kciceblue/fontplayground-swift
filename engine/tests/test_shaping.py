import json
import re
import subprocess
import sys
from pathlib import Path

import pytest
from fontTools import unicodedata
from fontTools.unicodedata import Scripts, ot_tags_from_script

from fpengine.scripts import group_of
from fpengine.shaping import (
    COMPLEX_GROUPS,
    OT_ALTERNATIVES,
    SCRIPT_SHAPING,
    explain_unshaped,
    fixture_payload,
    join_names,
    responsible_scripts,
    script_members,
    shapes_groups,
    unshaped_codepoints,
)

ARABIC = set(range(0x0627, 0x064B)) | set(range(0x0660, 0x066A)) | {0xFE8D, 0x064E}
HEBREW = set(range(0x05D0, 0x05EB)) | {0x05B8}
DEVA = set(range(0x0915, 0x093A)) | {0x094D}
TIBETAN = set(range(0x0F40, 0x0F48)) | set(range(0x0F49, 0x0F6D))


def test_shaping_table_matches_fonttools() -> None:
    assert COMPLEX_GROUPS == ("hebrew", "arabic", "indic", "southeast_asian")
    for code, script in SCRIPT_SHAPING.items():
        assert script.script == code
        assert script.ot_tags == tuple(ot_tags_from_script(code))
        first = Scripts.RANGES[Scripts.VALUES.index(code)]
        assert script.group == group_of(first)
        assert script.name and script.name.isascii()


@pytest.mark.parametrize(
    "codepoints,gsub,gpos,expected,groups",
    [
        (ARABIC | {97}, (), (), ARABIC, ()),
        (ARABIC | {97}, ("arab",), (), set(), ("arabic",)),
        (HEBREW, (), ("hebr",), set(), ("hebrew",)),
        (HEBREW, (), (), HEBREW, ()),
        (HEBREW - {0x05B8}, (), (), set(), ("hebrew",)),
        (DEVA, ("deva",), (), set(), ("indic",)),
        (DEVA, ("dev2",), (), set(), ("indic",)),
        (DEVA, (), ("dev2",), DEVA, ()),
        (DEVA | {0x0A15}, ("dev2",), (), {0x0A15}, ("indic",)),
        (set(range(0x0E01, 0x0E2F)) | {0x0E31}, (), ("thai",), set(), ("southeast_asian",)),
        (set(range(0x0660, 0x066A)), (), (), set(), ("arabic",)),
        (TIBETAN | {97}, (), (), TIBETAN, ()),
        ({0x0E81, 0x0EB1}, (), ("lao ",), set(), ("southeast_asian",)),
        (HEBREW | {97, 0x0307}, (), (), HEBREW, ()),
    ],
    ids=["a", "b", "c", "d", "e", "f-deva", "f-dev2", "f-gpos", "g", "h", "i", "j", "k", "l"],
)
def test_unshaped_and_shapes_groups_cases(codepoints, gsub, gpos, expected, groups) -> None:
    unshaped = unshaped_codepoints(codepoints, gsub, gpos)
    assert unshaped == frozenset(expected)
    assert shapes_groups(codepoints, unshaped) == groups


def test_script_ranges_handle_full_unicode_without_per_character_script_lookup(monkeypatch) -> None:
    def unexpected_lookup(*args):
        pytest.fail("Script membership must bisect Unicode ranges instead of looking up every code point")

    monkeypatch.setattr(unicodedata, "script", unexpected_lookup)
    members = script_members(range(0x110000))
    assert tuple(members) == tuple(SCRIPT_SHAPING)
    assert 0x0627 in members["Arab"] and 0x0640 not in members["Arab"]
    explanation = explain_unshaped(ARABIC | {97, 0x0307}, (), ())
    assert explanation[0x0640] == explanation[0x064E] == "Arab"
    assert 97 not in explanation and 0x0307 not in explanation


def test_responsible_scripts_order_counts_and_ties() -> None:
    assert responsible_scripts({1: "Deva", 2: "Guru", 3: "Guru", 4: "Arab"}) == ["Guru", "Arab", "Deva"]
    assert join_names(["A"]) == "A"
    assert join_names(["A", "B"]) == "A and B"
    assert join_names(["A", "B", "C"]) == "A, B and C"
    assert join_names(["A", "B"], "or") == "A or B"


def test_shaping_fixture_is_current() -> None:
    path = Path(__file__).resolve().parents[2] / "spec/fixtures/shaping/ot_alternatives.json"
    actual, expected = json.loads(path.read_text()), fixture_payload()
    actual["header"].pop("fpengine_version")
    expected["header"].pop("fpengine_version")
    assert actual == expected
    assert list(actual["alternatives"]) == list(SCRIPT_SHAPING)
    assert OT_ALTERNATIVES["Tibt"] == ()
    for alternatives in actual["alternatives"].values():
        for alternative in alternatives:
            assert re.fullmatch(r"[A-Za-z0-9-]{1,63}", alternative["postscript_name"])
            assert alternative["where"] in {"system", "asset"}


def test_fixture_cli_replaces_atomically_and_deterministically(tmp_path: Path) -> None:
    path = tmp_path / "fixture.json"
    path.write_text("old fixture")
    original_inode = path.stat().st_ino
    subprocess.run([sys.executable, "-m", "fpengine.shaping", "write-fixture", str(path)], check=True)
    assert path.stat().st_ino != original_inode
    assert path.read_text() == json.dumps(fixture_payload(), ensure_ascii=False, indent=2, sort_keys=False) + "\n"
    assert list(tmp_path.iterdir()) == [path]
