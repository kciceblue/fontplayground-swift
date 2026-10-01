from pathlib import Path

import pytest
from fontTools.ttLib import TTFont

from fpengine import prepare as prepare_module
from fpengine.face import READER_VERSION, read_faces
from fpengine.forge import forge
from fpengine.planner import plan
from fpengine.records import face_record, ranges
from fpengine.shaping import rule_errors
from fpengine.spec import ForgeError, ForgeSpec, MaterialSpec
from tests.fixtures import build_font, cps, fake_face
from tests.meta_fixtures import decorate

AAT = b"\0\2\0\0\0\0\0\0"
ARABIC = set(range(0x0627, 0x064B)) | set(range(0x0660, 0x066A)) | {0xFE8D, 0x064E}
DEVA = set(range(0x0915, 0x093A)) | {0x094D}
HEBREW = set(range(0x05D0, 0x05EB)) | {0x05B8}
HEBREW_GPOS = "languagesystem DFLT dflt; languagesystem hebr dflt; feature kern { pos uni05D0 uni05D1 -50; } kern;"
MORX_NOTE = "Apple-only (AAT) ligatures and alternates are not carried over; the forged font uses plain letter forms"
KERN_NOTE = "Apple-only (AAT) kerning is not carried over"
TRACKING_NOTE = "Apple tracking (trak) is not carried over; spacing can differ from the original at some sizes"


@pytest.fixture
def shaping_fonts(tmp_path: Path) -> dict[str, Path]:
    geeza = build_font(tmp_path / "geeza.ttf", "Fixture Geeza", "Regular", ARABIC | {97})
    decorate(geeza, tables={"morx": AAT})
    arabic_ot = build_font(tmp_path / "arabic_ot.ttf", "Fixture Arabic OT", "Regular", ARABIC)
    decorate(arabic_ot, fea="languagesystem arab dflt; feature init { sub uni0628 by uni0627; } init;")
    latin_ot = build_font(tmp_path / "latin_ot.ttf", "Fixture Latin", "Regular", cps("ab"))
    geeza_only = build_font(tmp_path / "geeza_only.ttf", "Fixture Geeza Only", "Regular", ARABIC)
    decorate(geeza_only, tables={"morx": AAT})
    return dict(geeza=geeza, arabic_ot=arabic_ot, latin_ot=latin_ot, geeza_only=geeza_only)


def spec_for(*paths: Path, rules: dict[str, int] | None = None) -> ForgeSpec:
    return ForgeSpec(materials=[MaterialSpec(read_faces(path)[0]) for path in paths], script_rules=rules or {})


def assert_issue_notes(report, code: str, index: int, note: str) -> None:
    (issue,) = [issue for issue in report.issues if issue.code == code]
    assert issue.severity == "warning" and issue.material_index == index and issue.group is None
    assert issue.message == f"{report.materials[index].name}: {note}"
    assert note in report.materials[index].warnings
    assert issue.message in report.warnings


def test_engine_2_planner_leaves_unshaped_arabic_to_an_opentype_font(shaping_fonts) -> None:
    spec = spec_for(shaping_fonts["geeza"], shaping_fonts["arabic_ot"])
    face = spec.materials[0].face
    assert face.unshaped == frozenset(ARABIC) and face.shapes_groups == ()
    assert face.group_counts == (("latin", 1),)
    p = plan(spec)
    assert p.assignments == {0: {97}, 1: ARABIC}
    assert p.source[97] == 0 and all(p.source[cp] == 1 for cp in ARABIC)
    pure = read_faces(shaping_fonts["geeza_only"])[0]
    assert pure.group_counts == () and pure.counts["arabic"] == 0
    assert not pure.scripts and not any(pure.counts.values())


@pytest.mark.parametrize("aat", [True, False])
def test_engine_2_rule_to_aat_arabic_is_refused(shaping_fonts, tmp_path: Path, aat: bool) -> None:
    geeza = shaping_fonts["geeza"]
    if not aat:
        decorate(geeza, drop=("morx",))
    spec = spec_for(shaping_fonts["latin_ot"], geeza, rules={"arabic": 1})
    with pytest.raises(ForgeError) as caught:
        forge(spec, tmp_path / "output.ttf")
    error = caught.value
    assert (error.stage, error.code, error.material_index) == ("validate", "aat_unsupported_script", 1)
    assert error.material == "Fixture Geeza Regular"
    reason = (
        "shapes Arabic with Apple-only rules (AAT) that can't be carried over"
        if aat
        else "has no OpenType shaping rules for Arabic"
    )
    assert error.message == (
        f"Fixture Geeza Regular can't draw Arabic in the forged font: it {reason}. "
        "Choose an OpenType font instead, for example Damascus, Noto Nastaliq Urdu or Arial."
    )
    assert not (tmp_path / "output.ttf").exists()
    good_spec = spec_for(shaping_fonts["latin_ot"], shaping_fonts["arabic_ot"], rules={"arabic": 1})
    forge(good_spec, tmp_path / "good.ttf")
    fake = ForgeSpec(
        materials=[MaterialSpec(fake_face(cps("ab"))), MaterialSpec(fake_face(set(range(0x0627, 0x064B))))],
        script_rules={"arabic": 1},
    )
    assert rule_errors(fake) == []


def test_partial_shaping_is_a_warning_not_an_error(tmp_path: Path) -> None:
    path = build_font(tmp_path / "indic.ttf", "Fixture Indic", "Regular", DEVA | {0x0A15})
    decorate(path, fea="languagesystem dev2 dflt; feature akhn { sub uni0915 uni094D by uni0916; } akhn;")
    report = forge(spec_for(path, rules={"indic": 0}), tmp_path / "out.ttf")
    (issue,) = [issue for issue in report.issues if issue.code == "unshaped_left_out"]
    assert issue.material_index == 0 and issue.group == "indic"
    assert issue.message == (
        "Fixture Indic Regular: Gurmukhi characters are drawn by other fonts or left out "
        "(0 drawn by other fonts, 1 left out): this font has no OpenType shaping rules for them"
    )
    with TTFont(tmp_path / "out.ttf") as font:
        assert set(font.getBestCmap()) == DEVA


def test_native_m1_unshaped_arabic_never_reaches_the_output(shaping_fonts, tmp_path: Path) -> None:
    report = forge(spec_for(shaping_fonts["latin_ot"], shaping_fonts["geeza"]), tmp_path / "out.ttf")
    with TTFont(tmp_path / "out.ttf") as font:
        assert set(font.getBestCmap()) == cps("ab")
    (issue,) = [issue for issue in report.issues if issue.code == "unshaped_left_out"]
    assert issue.material_index == 1 and issue.group == "arabic"
    assert issue.message == (
        "Fixture Geeza Regular: Arabic characters are drawn by other fonts or left out "
        "(0 drawn by other fonts, 48 left out): this font "
        "shapes them with Apple-only rules (AAT) that can't be carried over"
    )
    assert report.materials[1].warnings[-1] == "contributes no characters"
    assert issue.message in report.warnings


@pytest.mark.parametrize("source", ["format1", "kerx", "format0", "legacy"])
def test_engine_7_aat_kerning_loss_is_reported(font_dir: Path, tmp_path: Path, source: str) -> None:
    path = font_dir / ("K.ttf" if source == "legacy" else "A.ttf")
    if source != "legacy":
        path = decorate(
            path,
            out=tmp_path / "input.ttf",
            kern_v1_format={"format1": 1, "format0": 0}.get(source),
            tables={"kerx": AAT} if source == "kerx" else None,
        )
    report = forge(spec_for(path), tmp_path / "out.ttf")
    if source in {"format1", "kerx"}:
        assert_issue_notes(report, "aat_kerning_dropped", 0, KERN_NOTE)
    else:
        assert not any(issue.code == "aat_kerning_dropped" for issue in report.issues)
        with TTFont(tmp_path / "out.ttf") as font:
            assert any(record.FeatureTag == "kern" for record in font["GPOS"].table.FeatureList.FeatureRecord)


@pytest.mark.parametrize("tag,fea", [("morx", None), ("mort", None), ("morx", "arab"), ("trak", None)])
def test_ui_m2_morx_loss_is_reported(font_dir: Path, tmp_path: Path, tag: str, fea: str | None) -> None:
    path = decorate(
        font_dir / "A.ttf",
        out=tmp_path / "input.ttf",
        tables={tag: AAT},
        fea="languagesystem arab dflt; feature init { sub uni0061 by uni0062; } init;" if fea else None,
    )
    report = forge(spec_for(path), tmp_path / "out.ttf")
    if fea:
        assert not any(issue.code.startswith("aat_") for issue in report.issues)
    elif tag == "trak":
        assert_issue_notes(report, "aat_tracking_dropped", 0, TRACKING_NOTE)
    else:
        assert_issue_notes(report, "aat_morx_dropped", 0, MORX_NOTE)


def test_aat_issues_only_for_contributing_materials(font_dir: Path, tmp_path: Path) -> None:
    path = decorate(font_dir / "A.ttf", out=tmp_path / "input.ttf", tables={"morx": AAT})
    report = forge(spec_for(font_dir / "A.ttf", path), tmp_path / "out.ttf")
    assert report.materials[1].codepoints == 0
    assert not any(issue.code.startswith("aat_") for issue in report.issues)


def test_aat_issues_order_after_correctness_issues(font_dir: Path, tmp_path: Path) -> None:
    path = decorate(
        font_dir / "A.ttf", out=tmp_path / "input.ttf", tables=dict.fromkeys(("morx", "kerx", "trak", "bdat"), AAT)
    )
    report = forge(spec_for(path), tmp_path / "out.ttf")
    assert [issue.code for issue in report.issues] == [
        "bitmaps_dropped",
        "aat_morx_dropped",
        "aat_kerning_dropped",
        "aat_tracking_dropped",
        "licence_unknown",
    ]
    assert report.materials[0].warnings[-3:] == [MORX_NOTE, KERN_NOTE, TRACKING_NOTE]


def test_unshaped_rescue_counts_include_inherited_marks(shaping_fonts, tmp_path: Path) -> None:
    report = forge(spec_for(shaping_fonts["geeza"], shaping_fonts["arabic_ot"]), tmp_path / "out.ttf")
    (issue,) = [issue for issue in report.issues if issue.code == "unshaped_left_out"]
    assert issue.material_index == 0 and issue.group == "arabic"
    assert "(48 drawn by other fonts, 0 left out)" in issue.message
    with TTFont(tmp_path / "out.ttf") as font:
        assert set(font.getBestCmap()) == ARABIC | {97}
    # Raw-priority coverage already supplied by a preceding OT face is never attributed as an omission.
    report = forge(spec_for(shaping_fonts["arabic_ot"], shaping_fonts["geeza"]), tmp_path / "reversed.ttf")
    assert not any(issue.code == "unshaped_left_out" for issue in report.issues)


def test_records_carry_unshaped_and_shapes_groups(shaping_fonts) -> None:
    face = read_faces(shaping_fonts["geeza"])[0]
    record = face_record(face)
    assert record["unshaped"] == ranges(ARABIC)
    assert record["shapes_groups"] == []
    assert READER_VERSION >= 6


def test_rule_errors_follow_group_order_and_script_counts(tmp_path: Path) -> None:
    path = build_font(
        tmp_path / "mixed.ttf", "Fixture Mixed", "Regular", ARABIC | {0x05D0, 0x05B8, 0x0915, 0x0A15, 0x0A16}
    )
    spec = spec_for(path, rules={"indic": 0, "arabic": 0, "hebrew": 0})
    errors = rule_errors(spec)
    assert [group for _, group, _ in errors] == ["hebrew", "arabic", "indic"]
    assert errors[2][2] == (
        "Fixture Mixed Regular can't draw Indic in the forged font: it has no OpenType shaping rules for "
        "Gurmukhi and Devanagari. Choose an OpenType font instead, for example Gurmukhi Sangam MN or Gurmukhi MN."
    )
    with pytest.raises(ForgeError) as caught:
        forge(spec, tmp_path / "out.ttf")
    assert caught.value.material_index == 0
    assert caught.value.message == " ".join(message for _, _, message in errors)


def test_omission_groups_follow_group_order_and_script_counts(tmp_path: Path) -> None:
    latin = build_font(tmp_path / "latin.ttf", "Fixture Latin", "Regular", {97})
    path = build_font(
        tmp_path / "mixed.ttf", "Fixture Mixed", "Regular", ARABIC | {0x05D0, 0x05B8, 0x0915, 0x0A15, 0x0A16}
    )
    report = forge(spec_for(latin, path), tmp_path / "out.ttf")
    issues = [issue for issue in report.issues if issue.code == "unshaped_left_out"]
    assert [issue.group for issue in issues] == ["hebrew", "arabic", "indic"]
    assert "Gurmukhi and Devanagari characters" in issues[2].message
    assert "(0 drawn by other fonts, 3 left out)" in issues[2].message


def test_aat_kerning_loss_is_suppressed_when_opentype_kerning_survives(font_dir: Path, tmp_path: Path) -> None:
    path = decorate(
        font_dir / "A.ttf",
        out=tmp_path / "input.ttf",
        tables={"kerx": AAT},
        fea="languagesystem latn dflt; feature kern { pos uni0061 uni0062 -40; } kern;",
    )
    report = forge(spec_for(path), tmp_path / "out.ttf")
    assert not any(issue.code == "aat_kerning_dropped" for issue in report.issues)
    with TTFont(tmp_path / "out.ttf") as font:
        assert any(record.FeatureTag == "kern" for record in font["GPOS"].table.FeatureList.FeatureRecord)


def _broken_variable_gpos(monkeypatch: pytest.MonkeyPatch) -> list[bool]:
    """Fail the first instancing attempt, as fonts with broken GPOS variation indices do."""
    original = prepare_module.instance_variable
    calls: list[bool] = []

    def instance(font: TTFont, weight: int | None) -> TTFont:
        calls.append("GPOS" in font)
        if len(calls) == 1:
            raise ValueError("broken variable GPOS fixture")
        return original(font, weight)

    monkeypatch.setattr(prepare_module, "instance_variable", instance)
    return calls


def test_gpos_retry_refuses_marks_that_needed_gpos(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    path = build_font(tmp_path / "hebrew_var.ttf", "Fixture Hebrew Var", "Regular", HEBREW | {97}, variable=True)
    decorate(path, fea=HEBREW_GPOS)
    face = read_faces(path)[0]
    assert face.ot_gsub == () and face.unshaped == frozenset()
    calls = _broken_variable_gpos(monkeypatch)
    with pytest.raises(ForgeError) as caught:
        forge(ForgeSpec([MaterialSpec(face)]), tmp_path / "output.ttf")
    error = caught.value
    assert (error.stage, error.code, error.material) == ("prepare", None, "Fixture Hebrew Var Regular")
    assert error.message == (
        "Hebrew marks need this font's positioning rules, but its variable positioning data (GPOS) is broken "
        "and has to be dropped. Let another font draw Hebrew."
    )
    assert calls == [True]
    assert not (tmp_path / "output.ttf").exists()


def test_gpos_retry_keeps_the_face_when_another_font_draws_the_marks(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    path = build_font(tmp_path / "hebrew_var.ttf", "Fixture Hebrew Var", "Regular", HEBREW | {97}, variable=True)
    decorate(path, fea=HEBREW_GPOS)
    hebrew = build_font(tmp_path / "hebrew_ot.ttf", "Fixture Hebrew OT", "Regular", HEBREW)
    decorate(hebrew, fea=HEBREW_GPOS)
    spec = spec_for(path, hebrew, rules={"hebrew": 1})
    calls = _broken_variable_gpos(monkeypatch)
    report = forge(spec, tmp_path / "output.ttf")
    assert calls == [True, False]
    assert any(warning.startswith("GPOS dropped:") for warning in report.materials[0].warnings)
    with TTFont(tmp_path / "output.ttf") as font:
        assert set(font.getBestCmap()) == HEBREW | {97}
