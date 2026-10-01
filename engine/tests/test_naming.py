from datetime import UTC, datetime, timedelta
from pathlib import Path

import pytest
from fontTools.misc.fixedTools import floatToFixed
from fontTools.ttLib import TTFont

from fpengine import merge, naming
from fpengine.face import read_faces
from fpengine.forge import forge
from fpengine.naming import ForgeStamp, font_revision, postscript_name, version_parts, version_string
from fpengine.spec import ForgeError, ForgeSpec, MaterialSpec
from tests.fixtures import build_collection, build_font, cps

EXAMPLES = [
    ("Avenir Next PingFang", "Regular", "AvenirNextPingFangFP61d27706-Regular"),
    ("Avenir Next", "Regular", "AvenirNextFP76fdbbf4-Regular"),
    ("我的字体", "Regular", "ForgedFP5ef09893-Regular"),
    ("你的字体", "Regular", "ForgedFP4f4f31c7-Regular"),
    ("Noto 我的", "Regular", "NotoFP193bc651-Regular"),
    ("Noto 你的", "Regular", "NotoFP39174c89-Regular"),
    ("甲字体", "粗体", "ForgedFP4baff28f-Regular"),
    ("甲字体", "细体", "ForgedFP865d96ec-Regular"),
    ("My Font", "Bold Italic", "MyFontFP072c765b-BoldItalic"),
    ("MyFont", "Bold Italic", "MyFontFP3601e1d1-BoldItalic"),
    ("  Forged Test ", " Regular ", "ForgedTestFP373d14cc-Regular"),
    (
        "A Very Long Family Name That Keeps Going And Going Forever",
        "Extra Condensed Semibold Italic",
        "AVeryLongFamilyNameThatKeepsGoinFP4bedb3c1-ExtraCondensedSemibo",
    ),
    ("", "Regular", "ForgedFP55a0a3da-Regular"),
]


def _spec(font_dir: Path, family: str = "Forged Test", style: str = "Regular") -> ForgeSpec:
    return ForgeSpec(materials=[MaterialSpec(read_faces(font_dir / "A.ttf")[0])], family_name=family, style_name=style)


def _written_names(path: Path) -> dict[int, str]:
    with TTFont(path) as font:
        return {record.nameID: font["name"].getDebugName(record.nameID) for record in font["name"].names}


@pytest.mark.parametrize("family,style,expected", EXAMPLES)
def test_postscript_name_examples(family: str, style: str, expected: str) -> None:
    assert postscript_name(family, style) == expected
    assert merge.postscript_name is naming.postscript_name
    assert naming.fnv1a64(b"") == 0xCBF29CE484222325
    assert naming.fnv1a64(b"a") == 0xAF63DC4C8601EC8C


def test_clean_names_preserve_unicode_spelling() -> None:
    whitespace = "\t\n\v\f\r\x1c\x1d\x1e\x1f \x85\xa0\u1680" + "".join(chr(cp) for cp in range(0x2000, 0x200B))
    whitespace += "\u2028\u2029\u202f\u205f\u3000"
    assert naming.clean_name(whitespace + "Café" + whitespace) == "Café"
    assert postscript_name("\u3000Noto\u00a0", "Regular") == postscript_name("Noto", "Regular")
    assert postscript_name("Café", "Regular") != postscript_name("Cafe\u0301", "Regular")
    assert naming.ascii_alnum("Az 09-é，.-") == "Az09"
    assert naming.name_tag("Forged Test", "Regular") == "373d14cc"


def test_install_5_postscript_names_are_unique() -> None:
    import re

    families = (
        [f"Family {i}" for i in range(500)]
        + [chr(0x4E00 + i) + "字体" for i in range(500)]
        + [f"Noto {chr(0x4E00 + i)}" for i in range(250)]
        + [f"My Font {i}" for i in range(125)]
        + [f"MyFont {i}" for i in range(125)]
    )
    styles = ["Regular", "Bold", "Bold Italic", "BoldItalic", "粗体", "细体"]
    names = [postscript_name(family, style) for family in families for style in styles]
    assert len(names) == len(set(names)) == 9000
    assert all(len(name) <= 63 and re.fullmatch(r"[A-Za-z0-9]+-[A-Za-z0-9]+", name) for name in names)


def test_engine_m3_ps_name_never_equals_the_plain_system_name(font_dir: Path, tmp_path: Path) -> None:
    output = tmp_path / "avenir.ttf"
    report = forge(_spec(font_dir, "Avenir Next"), output)
    name = _written_names(output)[6]
    assert name == report.postscript_name == "AvenirNextFP76fdbbf4-Regular"
    assert name != "AvenirNext-Regular"


def test_install_5_cjk_families_get_distinct_ps_names(font_dir: Path, tmp_path: Path) -> None:
    pairs = [("我的字体", "Regular"), ("你的字体", "Regular"), ("甲字体", "粗体"), ("甲字体", "细体")]
    names = []
    for index, (family, style) in enumerate(pairs + pairs):
        output = tmp_path / f"cjk-{index}.ttf"
        forge(_spec(font_dir, family, style), output)
        names.append(_written_names(output)[6])
    assert len(set(names[:4])) == 4
    assert names[:4] == names[4:]


def test_version_and_unique_id_change_every_forge(font_dir: Path, tmp_path: Path) -> None:
    import re

    first = ForgeStamp(datetime(2026, 9, 29, 14, 42, 7, tzinfo=UTC), "0a1b2c3d")
    one_second = ForgeStamp(first.when + timedelta(seconds=1), first.nonce)
    two_seconds = ForgeStamp(first.when + timedelta(seconds=2), first.nonce)
    other_nonce = ForgeStamp(first.when, "ffffffff")
    assert version_string(first) == "Version 9768.61258"
    assert font_revision(two_seconds) > font_revision(first)

    names, revisions, tables = [], [], []
    spec = _spec(font_dir)
    for index, stamp in enumerate([first, one_second, two_seconds, other_nonce, first]):
        output = tmp_path / f"version-{index}.ttf"
        forge(spec, output, stamp=stamp)
        names.append(_written_names(output))
        with TTFont(output, recalcTimestamp=False) as font:
            revisions.append(font["head"].fontRevision)
            tables.append(font["name"].compile(font))
        assert re.fullmatch(r"Version \d+\.\d{5}", names[-1][5])
        assert abs(float(names[-1][5][8:]) - revisions[-1]) < 1e-4

    assert names[0][5] != names[1][5] != names[2][5]
    assert names[0][3] != names[1][3] != names[2][3]
    assert revisions[2] > revisions[0]
    assert names[0][3] == "Forged Test Regular; FontPlayground 2026-09-29T14:42:07Z; 0a1b2c3d"
    assert {key for key in names[0] if names[0][key] != names[3][key]} == {3}
    assert revisions[0] == revisions[3] == revisions[4]
    assert tables[0] == tables[4]

    midnight = first.when.replace(hour=0, minute=0, second=0)
    parts, fixed = [], []
    for second in range(86400):
        stamp = ForgeStamp(midnight + timedelta(seconds=second), first.nonce)
        parts.append(version_parts(stamp))
        fixed.append(floatToFixed(font_revision(stamp), 16))
    assert all(left < right for left, right in zip(parts, parts[1:]))
    assert all(left <= right for left, right in zip(fixed, fixed[1:]))
    assert all(left < right for left, right in zip(fixed, fixed[2:]))


def test_version_epoch_and_fixed_range() -> None:
    assert version_parts(ForgeStamp(naming.VERSION_EPOCH, "00000000")) == (0, 0)
    last = naming.VERSION_EPOCH + timedelta(days=32767, hours=23, minutes=59, seconds=59)
    assert floatToFixed(font_revision(ForgeStamp(last, "00000000")), 16) <= 0x7FFFFFFF
    for outside in [naming.VERSION_EPOCH - timedelta(seconds=1), naming.VERSION_EPOCH + timedelta(days=32768)]:
        with pytest.raises(ValueError, match="16.16"):
            version_parts(ForgeStamp(outside, "00000000"))


def test_new_stamp_uses_utc_seconds_and_a_nonce(monkeypatch: pytest.MonkeyPatch) -> None:
    def nonce(length: int) -> str:
        assert length == 4
        return "1234abcd"

    monkeypatch.setattr(naming.secrets, "token_hex", nonce)
    before = datetime.now(UTC).replace(microsecond=0)
    stamp = naming.new_stamp()
    after = datetime.now(UTC).replace(microsecond=0)
    assert before <= stamp.when <= after
    assert stamp.when.tzinfo is UTC and stamp.when.microsecond == 0
    assert stamp.nonce == "1234abcd"


def test_default_stamp_changes_unique_id_within_one_second(
    font_dir: Path, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    when = datetime(2026, 9, 29, 14, 42, 7, tzinfo=UTC)
    stamps = iter([ForgeStamp(when, "11111111"), ForgeStamp(when, "22222222")])
    monkeypatch.setattr("fpengine.forge.new_stamp", lambda: next(stamps))
    first, second = tmp_path / "first.ttf", tmp_path / "second.ttf"
    forge(_spec(font_dir), first)
    forge(_spec(font_dir), second)
    assert _written_names(first)[3] != _written_names(second)[3]
    assert _written_names(first)[5] == _written_names(second)[5]


def test_forged_notice_is_unchanged(font_dir: Path, tmp_path: Path) -> None:
    assert naming.FORGED_NOTICE == "Forged with Font Playground"
    assert merge.FORGED_NOTICE is naming.FORGED_NOTICE
    output = tmp_path / "marker.ttf"
    forge(_spec(font_dir), output)
    with TTFont(output) as font:
        for platform, encoding, language in [(3, 1, 0x409), (1, 0, 0)]:
            assert font["name"].getName(0, platform, encoding, language).toUnicode().startswith(naming.FORGED_NOTICE)


def test_is_forged_reads_the_notice_in_name_id_0(font_dir: Path, tmp_path: Path) -> None:
    output = tmp_path / "marker.ttf"
    forge(_spec(font_dir), output)
    assert naming.is_forged(output)
    reference = build_font(
        tmp_path / "reference.ttf",
        "Old Forge",
        "Regular",
        cps("a"),
        name_records={0: [(3, 1, 0x409, "Forged with Font Playground from: Fixture A Regular")]},
    )
    assert naming.is_forged(reference)
    junk = tmp_path / "junk.ttf"
    junk.write_bytes(b"not a font")
    for path in [font_dir / "A.ttf", tmp_path / "missing.ttf", junk, font_dir / "T.ttc"]:
        assert not naming.is_forged(path)
    mixed = build_collection(tmp_path / "mixed.ttc", [font_dir / "A.ttf", output])
    assert not naming.is_forged(mixed)
    assert naming.is_forged(mixed, index=1)
    assert not naming.is_forged(mixed, index=2)


@pytest.mark.parametrize(
    "family,style,expected",
    [
        (".Hidden", "Regular", "Family name can't start with “.”: macOS hides fonts whose names start with a dot."),
        ("Bad\x07Name", "Regular", "Family name contains a control character."),
        ("Normal", "Bold\x1b", "Style name contains a control character."),
        ("Bad\x7fName", "Regular", "Family name contains a control character."),
        ("Normal", "Bo\x00ld", "Style name contains a control character."),
    ],
)
def test_name_validation_rules(font_dir: Path, tmp_path: Path, family: str, style: str, expected: str) -> None:
    spec = _spec(font_dir, family, style)
    assert spec.validate() == [expected]
    with pytest.raises(ForgeError) as error:
        forge(spec, tmp_path / "invalid.ttf")
    assert error.value.stage == "validate"
    assert not (tmp_path / "invalid.ttf").exists()
    assert _spec(font_dir, "  Normal ").validate() == []


@pytest.mark.parametrize("style", ["Regular", "Semibold Condensed"])
def test_report_carries_written_names(font_dir: Path, tmp_path: Path, style: str) -> None:
    output = tmp_path / "report.ttf"
    report = forge(_spec(font_dir, "  My Name\u3000", f" {style} "), output)
    names = _written_names(output)
    assert report.family_name == names.get(16, names[1]) == "My Name"
    assert report.style_name == names.get(17, names[2]) == style
    assert report.full_name == names[4] == f"My Name {style}"
    assert report.postscript_name == names[6] == postscript_name("My Name", style)
