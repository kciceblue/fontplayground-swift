from pathlib import Path

import pytest
from fontTools.ttLib import TTFont, newTable
from fontTools.ttLib.tables._n_a_m_e import makeName

from fpengine.face import READER_VERSION, _best_name, _name_rank, read_faces
from fpengine.forge import forge
from fpengine.records import face_record
from fpengine.spec import ForgeSpec, MaterialSpec
from tests.fixtures import build_font, cps


def _al_bayan(path: Path) -> Path:
    return build_font(
        path,
        "Unused",
        "Unused",
        cps("ab"),
        name_records={
            1: [(1, 0, 0, "Al Bayan"), (3, 1, 0x0C01, "البيان")],
            2: [(1, 0, 0, "Bold"), (3, 1, 0x0C01, "عريض")],
            4: [(1, 0, 0, "Al Bayan Bold"), (3, 1, 0x0C01, "البيان عريض")],
        },
    )


def test_catalog_3_mac_roman_english_beats_other_windows_languages(tmp_path: Path) -> None:
    face = read_faces(_al_bayan(tmp_path / "al-bayan.ttf"))[0]
    assert face.family == "Al Bayan" and face.local_names == ("البيان",)
    assert face.style == "Bold" and face.full_name == "Al Bayan Bold"


def test_ui_m1_english_and_native_names_are_both_in_the_record(tmp_path: Path) -> None:
    record = face_record(read_faces(_al_bayan(tmp_path / "al-bayan.ttf"))[0])
    assert record["family"] == "Al Bayan"
    assert record["local_names"] == ["البيان"]
    assert record["full_name"] == "Al Bayan Bold"


def test_engine_m4_default_names_are_english(tmp_path: Path) -> None:
    path = build_font(
        tmp_path / "geeza.ttf",
        "Unused",
        "Unused",
        cps("ab"),
        name_records={
            1: [
                (1, 0, 0, "Geeza Pro"),
                (3, 1, 0x420, "گیزا پرو"),
                (3, 1, 0x439, "गीज़ा प्रो"),
                (3, 1, 0xC01, "جيزة"),
            ],
            2: [(1, 0, 0, "Regular"), (3, 1, 0x420, "عادي")],
        },
    )
    face = read_faces(path)[0]
    assert face.display_name == "Geeza Pro Regular"
    assert face.local_names == ("گیزا پرو", "गीज़ा प्रो", "جيزة")
    output = tmp_path / "forged.ttf"
    report = forge(ForgeSpec([MaterialSpec(face)]), output)
    assert report.materials[0].name == "Geeza Pro Regular"
    with TTFont(output) as font:
        assert font["name"].getDebugName(0) == "Forged with Font Playground from: Geeza Pro Regular"


@pytest.mark.parametrize(
    "records, expected",
    [
        ({16: [(3, 1, 0xC01, "جيزة")], 1: [(1, 0, 0, "Geeza Pro")]}, "Geeza Pro"),
        ({16: [(3, 1, 0x409, "Fixture T")], 1: [(3, 1, 0x409, "Fixture T Light")]}, "Fixture T"),
    ],
)
def test_english_typographic_and_legacy_families(tmp_path: Path, records: dict, expected: str) -> None:
    path = build_font(tmp_path / "typographic.ttf", "Unused", "Regular", cps("ab"), name_records=records)
    assert read_faces(path)[0].family == expected


@pytest.mark.parametrize(
    "mac_records, expected",
    [
        ([(1, 25, 33, "华文宋体".encode("gb2312"))], ("华文宋体",)),
        ([(1, 2, 19, "儷宋 Pro".encode("big5"))], ("儷宋 Pro",)),
        ([(1, 3, 23, "애플고딕".encode("euc_kr"))], ("애플고딕",)),
        (
            [
                (1, 3, 23, "애플고딕".encode("euc_kr")),
                (1, 1, 11, "テスト".encode("shift_jis")),
                (1, 2, 19, "儷宋 Pro".encode("big5")),
                (1, 25, 33, "华文宋体".encode("gb2312")),
            ],
            ("华文宋体", "儷宋 Pro", "テスト", "애플고딕"),
        ),
    ],
)
def test_catalog_m2_mac_chinese_korean_local_names(tmp_path: Path, mac_records: list, expected: tuple) -> None:
    path = build_font(
        tmp_path / "cjk.ttf",
        "Unused",
        "Regular",
        cps("a"),
        name_records={1: [(3, 1, 0x409, "Fixture ST"), *mac_records]},
    )
    face = read_faces(path)[0]
    assert face.family == "Fixture ST" and face.local_names == expected


@pytest.mark.parametrize(
    "local_records, expected",
    [
        ([(3, 1, 0x411, "テスト"), (1, 25, 33, "华文宋体")], ("テスト",)),
        ([(1, 0, 0, "Old Mac")], ()),
        ([(1, 25, 33, b"\xa4"), (1, 3, 23, "애플고딕".encode("euc_kr"))], ("애플고딕",)),
        ([(1, 5, 10, b"\xff")], ()),
    ],
)
def test_local_names_fallback_rules(tmp_path: Path, local_records: list, expected: tuple) -> None:
    path = build_font(
        tmp_path / "fallback.ttf",
        "Unused",
        "Regular",
        cps("ab"),
        name_records={1: [(3, 1, 0x409, "Fixture"), *local_records]},
    )
    assert read_faces(path)[0].local_names == expected


def test_name_rank_prefers_printable_ascii_only_and_keeps_equal_rank_order() -> None:
    assert _name_rank(makeName("English", 1, 1, 0, 0)) == 1
    for text in (b"bad\x1f", b"bad\x7f", "Café".encode("mac_roman")):
        assert _name_rank(makeName(text, 1, 1, 0, 0)) is None
    assert all(_name_rank(makeName("English", 1, 3, encoding, 0x409)) == 0 for encoding in (0, 1, 10))
    name = newTable("name")
    name.names = [makeName("Second", 1, 3, 1, 0x420), makeName("First", 1, 3, 1, 0x411)]
    assert _best_name(name, (1,)) == "Second"
    name.names.reverse()
    assert _best_name(name, (1,)) == "First"


def test_name_reading_preserves_unicode_and_typographic_style_preference(tmp_path: Path) -> None:
    decomposed = "Cafe\u0301"
    path = build_font(
        tmp_path / "unchanged.ttf",
        "Unused",
        "Unused",
        cps("ab"),
        name_records={
            1: [(3, 1, 0x409, decomposed)],
            17: [(3, 1, 0xC01, "عريض")],
            2: [(1, 0, 0, "Bold")],
        },
    )
    face = read_faces(path)[0]
    assert face.family == decomposed and face.style == "Bold"
    assert READER_VERSION >= 5
