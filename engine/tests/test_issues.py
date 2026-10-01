"""Report issues stay ordered and retain the complete human-readable warning text."""

import dataclasses
from importlib import import_module

from fpengine.face import read_faces
from fpengine.forge import _report, forge
from fpengine.prepare import PreparedFont, _note
from fpengine.spec import ForgeReport, ForgeSpec, Issue, MaterialSpec, Plan
from tests.fixtures import cps, fake_face


def test_issue_to_dict():
    issue = Issue("x", "warning", 1, None, "m")
    assert list(issue.to_dict()) == ["code", "severity", "material_index", "group", "message"]
    assert issue.to_dict() == dataclasses.asdict(issue)


def test_report_issues_default_empty(font_dir, tmp_path):
    face = read_faces(font_dir / "A.ttf")[0]
    report = forge(ForgeSpec([MaterialSpec(face)]), tmp_path / "out.ttf")
    assert [issue for issue in report.issues if not issue.code.startswith("licence_")] == []
    first, second = ForgeReport([], 0, 0, [], "x"), ForgeReport([], 0, 0, [], "y")
    assert first.issues == second.issues == []
    first.issues.append(Issue("x", "warning", None, None, "note"))
    assert second.issues == []


def test_report_issue_plumbing(font_dir, tmp_path, monkeypatch):
    module = import_module("fpengine.forge")
    real_prepare = module.prepare

    def prepare_with_note(material, codepoints, target_upem, weight, scale, workdir, index):
        part = real_prepare(material, codepoints, target_upem, weight, scale, workdir, index)
        if index == 1:
            _note(part.warnings, part.issues, "test_code", "a note", index, material.face.display_name)
        return part

    monkeypatch.setattr(module, "prepare", prepare_with_note)
    faces = [read_faces(font_dir / filename)[0] for filename in ("A.ttf", "B.otf")]
    report = forge(ForgeSpec([MaterialSpec(face) for face in faces]), tmp_path / "out.ttf")
    message = f"{report.materials[1].name}: a note"
    assert [issue for issue in report.issues if not issue.code.startswith("licence_")] == [
        Issue("test_code", "warning", 1, None, message)
    ]
    assert "a note" in report.materials[1].warnings
    assert message in report.warnings
    assert message in report.as_text()


def test_report_issue_order():
    faces = [fake_face(cps("a"), family="A"), fake_face(cps("b"), family="B")]
    spec = ForgeSpec([MaterialSpec(face) for face in faces])
    plan = Plan({0: {0x61}, 1: {0x62}}, {0x61: 0, 0x62: 1})
    name0, name1 = (face.display_name for face in faces)
    issue0 = Issue("first", "warning", 0, None, f"{name0}: prepared zero")
    issue1 = Issue("second", "warning", 1, None, f"{name1}: prepared one")
    # Deliberately reversed issue indexes ensure _report sorts rather than relying on input order.
    prepared = [
        PreparedFont("0.ttf", 1000, ["prepared one"], [issue1]),
        PreparedFont("1.ttf", 1000, ["prepared zero"], [issue0]),
    ]
    report_issue = Issue("r", "warning", None, None, "report level")
    late_issue = Issue("s", "warning", 0, None, f"{name0}: late")
    report = _report(spec, plan, prepared, 2, 3, "out.ttf", [report_issue, late_issue])
    assert [issue for issue in report.issues if not issue.code.startswith("licence_")] == [
        issue0,
        late_issue,
        issue1,
        report_issue,
    ]
    assert report.materials[0].warnings == ["prepared one", "late"]
    assert report.materials[1].warnings == ["prepared zero"]
    assert report.warnings == [f"{name0}: prepared one", f"{name0}: late", f"{name1}: prepared zero", "report level"]
    assert prepared[0].warnings == ["prepared one"]
    assert prepared[0].issues == [issue1]


def test_report_issue_order_across_shaping_and_licensing():
    face = dataclasses.replace(
        fake_face({0x61, 0x627}, family="A"),
        unshaped=frozenset({0x627}),
        aat_morx=True,
        fs_type=4,
        licence_class="apple-sla",
    )
    spec = ForgeSpec([MaterialSpec(face)])
    plan = Plan({0: {0x61}}, {0x61: 0})
    notes = ["embedded bitmaps are not kept", "synthetic bold (+300)"]
    prepared = [
        PreparedFont(
            "0.ttf",
            1000,
            notes,
            [
                Issue("bitmaps_dropped", "warning", 0, None, f"A Regular: {notes[0]}"),
                Issue("synthetic_bold", "warning", 0, None, f"A Regular: {notes[1]}"),
            ],
            aat_losses=frozenset({"morx", "kerning", "tracking"}),
        )
    ]
    report = _report(
        spec,
        plan,
        prepared,
        1,
        2,
        "out.ttf",
        [
            Issue("cmap_format4_partial", "warning", None, None, "basic character map is partial"),
            Issue("bold_size_doubled", "warning", 0, None, "A Regular: bold doubled the file size"),
        ],
    )
    assert [issue.code for issue in report.issues] == [
        "bitmaps_dropped",
        "synthetic_bold",
        "bold_size_doubled",
        "aat_morx_dropped",
        "aat_kerning_dropped",
        "aat_tracking_dropped",
        "unshaped_left_out",
        "embedding_preview_print",
        "licence_apple_sla",
        "cmap_format4_partial",
        "output_fs_type",
    ]
    assert report.warnings == [issue.message for issue in report.issues if not issue.code.startswith("licence_")]
    assert report.fs_type == 4 and report.licence_notes[0].licence_class == "apple-sla"
    assert prepared[0].warnings == notes
