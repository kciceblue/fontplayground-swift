import json
import re
from dataclasses import replace
from pathlib import Path

from fpengine.face import read_faces
from fpengine.records import (
    FACE_RECORD_KEYS,
    expand,
    face_from_dict,
    face_from_record,
    face_record,
    face_to_dict,
    ranges,
)
from fpengine.scripts import GROUP_IDS
from tests.fixtures import cps, fake_face
from tests.meta_fixtures import build_bitmap_only_font, decorate


def test_face_dict_roundtrip(font_dir):
    (v,) = read_faces(font_dir / "V.ttf")
    d = face_to_dict(v)
    assert d["codepoints"] == [[97, 98]] and d["axes"] == [["wght", 100.0, 400.0, 900.0]]
    assert face_from_dict(d) == v


def test_face_dict_roundtrip_keeps_local_names_and_group_counts(font_dir):
    (b,) = read_faces(font_dir / "B.otf")
    b = replace(b, local_names=("测试", "テスト"))
    back = face_from_dict(json.loads(json.dumps(face_to_dict(b))))
    assert back == b and back.group_counts == (("latin", 2), ("han", 1), ("cjk_symbols", 1))
    assert hash(back) == hash(b)


def _fixture_faces(font_dir: Path):
    return [face for path in sorted(font_dir.iterdir()) for face in read_faces(path)]


def _assert_ranges(value) -> None:
    assert isinstance(value, list)
    end = -1
    for pair in value:
        assert isinstance(pair, list) and len(pair) == 2
        assert all(type(cp) is int for cp in pair)
        assert end < pair[0] <= pair[1]
        end = pair[1]


def test_face_record_has_exactly_the_contract_fields(font_dir: Path) -> None:
    contracts = (Path(__file__).resolve().parents[2] / "docs/specs/contracts.md").read_text(encoding="utf-8")
    section = contracts.split("## 3. `FaceRecord`", 1)[1].split("## 4.", 1)[0]
    contract_keys = [
        key
        for line in section.splitlines()
        if line.startswith("| `")
        for key in re.findall(r"`([^`]+)`", line.split("|")[1])
    ]
    assert FACE_RECORD_KEYS == tuple(key for key in contract_keys if key != "unshaped") + ("unshaped",)
    for face in _fixture_faces(font_dir):
        record = face_record(face)
        assert tuple(record) == FACE_RECORD_KEYS and len(record) == 34
        assert json.loads(json.dumps(record, ensure_ascii=False, allow_nan=False)) == record
        for key in ("path", "family", "style", "full_name", "outline", "embedding", "font_revision"):
            assert isinstance(record[key], str)
        for key in ("index", "size", "weight_class", "upem", "glyph_count"):
            assert type(record[key]) is int
        assert type(record["mtime"]) in (int, float)
        for key in (
            "is_collection",
            "is_variable",
            "italic",
            "has_color",
            "supported",
            "hidden",
            "suspicious_coverage",
            "has_os2",
            "is_forged",
        ):
            assert type(record[key]) is bool
        for key in ("postscript_name", "unsupported_reason"):
            assert record[key] is None or isinstance(record[key], str)
        assert record["fs_type"] is None or type(record["fs_type"]) is int
        for key in ("local_names", "shapes_groups"):
            assert isinstance(record[key], list) and all(isinstance(value, str) for value in record[key])
        for key in ("coverage", "unshaped"):
            _assert_ranges(record[key])
        assert isinstance(record["axes"], list)
        for axis in record["axes"]:
            assert set(axis) == {"tag", "min", "default", "max"}
            assert isinstance(axis["tag"], str) and len(axis["tag"]) == 4
            assert all(type(axis[key]) is float for key in ("min", "default", "max"))
        assert isinstance(record["group_counts"], dict)
        assert all(group in GROUP_IDS and type(n) is int and n > 0 for group, n in record["group_counts"].items())
        assert set(record["ot_scripts"]) == {"gsub", "gpos"}
        for tags in record["ot_scripts"].values():
            assert isinstance(tags, list) and all(isinstance(tag, str) and len(tag) == 4 for tag in tags)
        assert set(record["aat"]) == {"morx", "kerx", "kern_v1", "trak"}
        assert all(type(value) is bool for value in record["aat"].values())
        assert set(record["licence"]) == {"class", "vendor_id", "notice"}
        assert record["licence"]["class"] == "unknown"
        for key in ("vendor_id", "notice"):
            assert record["licence"][key] is None or isinstance(record["licence"][key], str)


def test_face_record_round_trip(font_dir: Path, tmp_path: Path) -> None:
    bitmap = build_bitmap_only_font(tmp_path / "bitmap.ttf", "Fixture Bitmap", cps("a一"))
    decorated = decorate(
        font_dir / "A.ttf",
        out=tmp_path / "decorated.ttf",
        vendor="APPL",
        kern_v1_format=1,
        fea="languagesystem arab dflt; feature init { sub uni0061 by uni0062; } init;",
        tables={"morx": b"\0" * 8},
        name_records={13: [(3, 1, 0x409, "A notice")]},
    )
    faces = _fixture_faces(font_dir) + read_faces(bitmap) + read_faces(decorated)
    for face in faces:
        back = face_from_record(json.loads(json.dumps(face_record(face))))
        assert back == face and hash(back) == hash(face)


def test_ranges_and_forward_compatibility(font_dir: Path) -> None:
    values = {1, 2, 3, 7, 9, 10}
    assert ranges(values) == [[1, 3], [7, 7], [9, 10]]
    assert ranges([]) == []
    assert ranges([2, 1, 2, 3]) == [[1, 3]]
    assert expand(ranges(values)) == frozenset(values)
    face = read_faces(font_dir / "V.ttf")[0]
    record = face_record(face)
    record["future_field"] = {"some": "new value"}
    record["group_counts"]["future_group"] = 17
    record["ot_scripts"]["future_table"] = ["latn"]
    record["aat"]["future_flag"] = True
    record["licence"]["future_policy"] = "example"
    assert face_from_record(record) == face


def test_face_record_missing_optional_fields_take_documented_defaults(font_dir: Path) -> None:
    record = face_record(read_faces(font_dir / "A.ttf")[0])
    defaults = {
        "full_name": "",
        "postscript_name": None,
        "fs_type": None,
        "has_os2": True,
        "hidden": False,
        "suspicious_coverage": False,
        "ot_gsub": (),
        "ot_gpos": (),
        "aat_morx": False,
        "aat_kerx": False,
        "aat_kern_v1": False,
        "aat_trak": False,
        "font_revision": "1.000",
        "is_forged": False,
        "vendor_id": None,
        "licence_notice": None,
        "licence_class": "unknown",
        "unshaped": frozenset(),
        "shapes_groups": (),
    }
    for key in (
        "full_name",
        "postscript_name",
        "fs_type",
        "has_os2",
        "hidden",
        "suspicious_coverage",
        "ot_scripts",
        "aat",
        "font_revision",
        "is_forged",
        "licence",
        "unshaped",
        "shapes_groups",
    ):
        del record[key]
    face = face_from_record(record)
    for key, value in defaults.items():
        assert getattr(face, key) == value


def test_face_dict_roundtrip_preserves_new_tuple_fields(font_dir: Path) -> None:
    face = replace(
        read_faces(font_dir / "A.ttf")[0],
        ot_gsub=("arab",),
        ot_gpos=("lao ",),
        shapes_groups=("arabic",),
        unshaped=frozenset({1, 2, 3, 7}),
    )
    encoded = face_to_dict(face)
    assert encoded["unshaped"] == [[1, 3], [7, 7]]
    back = face_from_dict(json.loads(json.dumps(encoded)))
    assert back == face and hash(back) == hash(face)
    assert back.ot_gsub == ("arab",) and back.ot_gpos == ("lao ",) and back.shapes_groups == ("arabic",)


def test_face_record_derives_hand_built_names_and_counts() -> None:
    record = face_record(fake_face(cps("aΩ一")))
    assert record["full_name"] == "Fake Regular"
    assert record["group_counts"] == {"latin": 1, "greek": 1, "han": 1}
