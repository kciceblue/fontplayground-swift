"""ENGINE-5 / CRIT-3: forging preserves contributing source permissions and notices."""

import os
import shutil

import pytest
from fontTools.ttLib import TTFont

from fpengine import licence, merge, naming
from fpengine.face import read_faces, source_notices
from fpengine.forge import forge
from fpengine.licence import LICENCE_NOTES, OPEN_NOTE, classify_licence, output_fs_type
from fpengine.naming import FORGED_NOTICE
from fpengine.spec import ForgeError, ForgeSpec, LicenceNote, MaterialSpec
from tests.fixtures import build_font, cps
from tests.meta_fixtures import decorate

OFL = "This Font Software is licensed under the SIL Open Font License, Version 1.1."
OFL_URL = "https://openfontlicense.org"
COPYRIGHT_A = "Copyright 2020 The Alpha Project Authors (https://example.org/alpha)"
COPYRIGHT_B = "© 2021 Beta Type Foundry. All rights reserved."


@pytest.mark.parametrize(
    "values,expected",
    [
        ([0, 8], 8),
        ([4, 8], 4),
        ([2, 4], 2),
        ([6], 2),
        ([12], 4),
        ([0, 0], 0),
        ([None, 8], 8),
        ([0x0108, 0], 0x0108),
        ([0x0200, 4], 0x0204),
    ],
)
def test_engine_5_output_fstype_is_most_restrictive(values, expected):
    assert output_fs_type(iter(values)) == expected


def run_forge(paths, output):
    faces = [read_faces(path)[0] for path in paths]
    return forge(ForgeSpec([MaterialSpec(face) for face in faces]), output)


def test_engine_5_fstype_propagates_from_contributing_materials(font_dir, tmp_path):
    extra = tmp_path / "P.ttf"
    build_font(extra, "Fixture P", "Regular", cps("x"), fs_type=4)
    output = tmp_path / "out.ttf"
    report = run_forge([font_dir / "A.ttf", extra], output)
    with TTFont(output) as font:
        assert font["OS/2"].fsType == report.fs_type == 4
    issue = next(issue for issue in report.issues if issue.code == "embedding_preview_print")
    assert issue.material_index == 1
    assert "“Preview & Print” (fsType 4)" in next(i.message for i in report.issues if i.code == "output_fs_type")
    build_font(extra, "Fixture P", "Regular", cps("a"), fs_type=4)
    report = run_forge([font_dir / "A.ttf", extra], output)
    assert report.fs_type == 0
    assert not any(i.code.startswith("embedding_") for i in report.issues)
    assert not any(i.code.startswith("licence_") and i.material_index == 1 for i in report.issues)
    assert report.materials[1].warnings == ["contributes no characters"]
    report = run_forge([font_dir / "C.ttf"], output)
    assert report.fs_type == 2
    assert licence.EMBEDDING_NOTES[2] in report.materials[0].warnings


@pytest.mark.parametrize(
    "texts,copyrights,vendor,path,forged,expected",
    [
        ([OFL], [], None, "/System/Library/Fonts/Supplemental/NotoSansX.ttf", False, "open"),
        (["https://www.apache.org/licenses/LICENSE-2.0"], [], None, "/tmp/x.ttf", False, "open"),
        ([OFL], ["© 2020 Apple Inc."], "APPL", "/System/Library/Fonts/x.ttf", False, "open"),
        (["Microsoft supplied font. You may use this font…"], [], None, "/tmp/x.ttf", False, "microsoft-product"),
        (
            [],
            [],
            None,
            "/Applications/Microsoft Word.app/Contents/Resources/DFonts/msyh.ttc",
            False,
            "microsoft-product",
        ),
        ([], [], "APPL", "/tmp/x.ttf", False, "apple-sla"),
        ([], ["Copyright © 2015 Apple Inc. All rights reserved."], None, "/tmp/x.ttf", False, "apple-sla"),
        (
            [],
            [],
            "DYNA",
            "/System/Library/AssetsV2/com_apple_MobileAsset_Font8/x.asset/AssetData/PingFang.ttc",
            False,
            "apple-sla",
        ),
        ([], [], None, "/Users/example/Library/Fonts/x.ttf", False, "unknown"),
        ([LICENCE_NOTES["apple-sla"]], [], None, "/Users/example/Library/Fonts/f.ttf", True, "apple-sla"),
        ([OPEN_NOTE], [], None, "/System/Library/Fonts/f.ttf", True, "open"),
        ([LICENCE_NOTES["apple-sla"]], [], None, "/tmp/x.ttf", False, "unknown"),
        ([OPEN_NOTE + " " + LICENCE_NOTES["unknown"]], [], None, "/tmp/x.ttf", True, "unknown"),
        (
            [LICENCE_NOTES["apple-sla"] + " " + LICENCE_NOTES["microsoft-product"]],
            [],
            None,
            "/tmp/x.ttf",
            True,
            "microsoft-product",
        ),
    ],
)
def test_engine_5_licence_classes(texts, copyrights, vendor, path, forged, expected):
    assert (
        classify_licence(licence_texts=texts, copyright_texts=copyrights, vendor_id=vendor, path=path, forged=forged)
        == expected
    )


def test_licence_class_is_read_with_the_face(font_dir, tmp_path, monkeypatch):
    system = tmp_path / "System/Library"
    destination = system / "Fonts/A.ttf"
    destination.parent.mkdir(parents=True)
    shutil.copyfile(font_dir / "A.ttf", destination)
    monkeypatch.setattr(licence, "SYSTEM_ROOTS", (os.path.realpath(system) + "/",))
    assert read_faces(destination)[0].licence_class == "apple-sla"
    link = tmp_path / "user/link.ttf"
    link.parent.mkdir()
    link.symlink_to(destination)
    face = read_faces(link)[0]
    assert face.licence_class == "apple-sla" and face.path == str(link)
    decorate(destination, name_records={13: [(3, 1, 0x409, OFL)]})
    assert read_faces(destination)[0].licence_class == read_faces(link)[0].licence_class == "open"


def test_crit_3_office_bundle_font_is_microsoft_product(font_dir, tmp_path):
    destination = tmp_path / "Microsoft Word.app/Contents/Resources/DFonts/x.ttf"
    destination.parent.mkdir(parents=True)
    shutil.copyfile(font_dir / "A.ttf", destination)
    assert read_faces(destination)[0].licence_class == "microsoft-product"
    report = run_forge([destination], tmp_path / "result.ttf")
    assert any(i.code == "licence_microsoft_product" for i in report.issues)
    assert report.licence_notes == [LicenceNote("microsoft-product", (0,), LICENCE_NOTES["microsoft-product"])]
    assert report.warnings == report.materials[0].warnings == []


def test_licence_notes_and_name_id_13(tmp_path):
    paths = []
    for character in "abcd":
        path = tmp_path / f"{character}.ttf"
        build_font(path, f"Fixture {character}", "Regular", cps(character))
        paths.append(path)
    decorate(paths[0], vendor="APPL")
    decorate(paths[1], name_records={0: [(3, 1, 0x409, "Copyright © 2015 Apple Inc.")]})
    decorate(paths[3], name_records={13: [(3, 1, 0x409, OFL)]})
    output = tmp_path / "out.ttf"
    report = run_forge(paths, output)
    expected = [
        LicenceNote("apple-sla", (0, 1), LICENCE_NOTES["apple-sla"]),
        LicenceNote("unknown", (2,), LICENCE_NOTES["unknown"]),
    ]
    assert report.licence_notes == expected
    with TTFont(output) as font:
        # The class notes come first; the open material's own licence description follows on its own line.
        assert font["name"].getDebugName(13) == LICENCE_NOTES["apple-sla"] + " " + LICENCE_NOTES["unknown"] + "\n" + OFL
        assert font["name"].getName(13, 1, 0, 0) is not None
    assert "\nLicence:\n" in report.as_text()
    for note in expected:
        names = ", ".join(report.materials[i].name for i in note.material_indexes)
        assert f"  - {note.text} ({names})" in report.as_text()
    assert report.warnings == []
    report = run_forge([paths[3]], output)
    assert report.licence_notes == []
    with TTFont(output) as font:
        assert font["name"].getDebugName(13) == OPEN_NOTE + "\n" + OFL


def test_forged_font_keeps_its_licence_class(font_dir, tmp_path):
    source = decorate(font_dir / "A.ttf", out=tmp_path / "apple.ttf", vendor="APPL")
    output = tmp_path / "out.ttf"
    run_forge([source], output)
    face = read_faces(output)[0]
    assert face.is_forged and naming.is_forged(output) and face.licence_class == "apple-sla"
    second = tmp_path / "second.ttf"
    run_forge([output], second)
    assert read_faces(second)[0].licence_class == "apple-sla"


def test_licence_texts_keep_all_decodable_languages(font_dir, tmp_path):
    path = decorate(
        font_dir / "A.ttf",
        out=tmp_path / "notices.ttf",
        name_records={
            13: [(3, 1, 0x409, "ordinary notice"), (3, 1, 0x411, OFL), (1, 25, 33, b"\xa4")],
            7: [(3, 1, 0x409, "Apple Computer")],
        },
    )
    with TTFont(path) as font:
        texts, copyrights = licence.licence_texts(font["name"])
    assert set(texts) == {"ordinary notice", OFL} and copyrights == ["Apple Computer"]
    assert read_faces(path)[0].licence_class == "open"


def test_reforging_keeps_every_licence_class(tmp_path):
    paths = []
    for character in "abc":
        path = tmp_path / f"{character}.ttf"
        build_font(path, f"Fixture {character}", "Regular", cps(character))
        paths.append(path)
    decorate(paths[0], vendor="APPL")
    decorate(paths[2], name_records={13: [(3, 1, 0x409, "Microsoft supplied font.")]})
    classes = ("apple-sla", "microsoft-product", "unknown")
    first = tmp_path / "first.ttf"
    run_forge(paths, first)
    face = read_faces(first)[0]
    assert face.licence_class == "microsoft-product" and face.licence_classes == classes
    second = tmp_path / "second.ttf"
    report = run_forge([first], second)
    assert report.licence_notes == [LicenceNote(c, (0,), LICENCE_NOTES[c]) for c in classes]
    codes = [issue.code for issue in report.issues if issue.code.startswith("licence_")]
    assert codes == ["licence_apple_sla", "licence_microsoft_product", "licence_unknown"]
    with TTFont(second) as font:
        notes = " ".join(LICENCE_NOTES[c] for c in classes)
        assert font["name"].getDebugName(13) == notes + "\nMicrosoft supplied font."  # carried from the first forge
    assert read_faces(second)[0].licence_classes == classes


def notice_sources(tmp_path, notices_by_character):
    """One fixture per character, "Fixture <character> Regular", with {name_id: text} as Windows English records."""
    return [
        build_font(
            tmp_path / f"{ord(character):04X}.ttf",
            f"Fixture {character}",
            "Regular",
            cps(character),
            name_records={name_id: [(3, 1, 0x409, text)] for name_id, text in notices.items()},
        )
        for character, notices in notices_by_character.items()
    ]


def test_forge_keeps_source_copyright_notices(tmp_path):
    alpha = {0: COPYRIGHT_A, 7: "Alpha is a trademark of The Alpha Project.", 13: OFL, 14: OFL_URL}
    paths = notice_sources(tmp_path, {"a": alpha, "b": {0: COPYRIGHT_B}})
    output = tmp_path / "out.ttf"
    run_forge(paths, output)
    with TTFont(output) as font:
        name = font["name"]
        expected = f"{FORGED_NOTICE} from: Fixture a Regular, Fixture b Regular\n{COPYRIGHT_A}\n{COPYRIGHT_B}"
        for platform, encoding, language in ((3, 1, 0x409), (1, 0, 0)):  # © is Mac Roman, so both records exist
            assert name.getName(0, platform, encoding, language).toUnicode() == expected
        assert name.getDebugName(7) == alpha[7]
        assert name.getDebugName(14) == OFL_URL
        assert name.getDebugName(13) == LICENCE_NOTES["unknown"] + "\n" + OFL
    face = read_faces(output)[0]
    assert face.is_forged and naming.is_forged(output)
    assert face.licence_class == "unknown"


def test_forge_keeps_each_contributing_notice_once(tmp_path):
    cjk = "© 2022 示例字体公司"
    a, b, d = notice_sources(
        tmp_path,
        {
            "a": {0: COPYRIGHT_A},
            "b": {0: COPYRIGHT_A.replace(" The ", "\r\n  The ") + "\n"},  # the same notice, other whitespace
            "d": {0: cjk},
        },
    )
    # Fixture c has only "a", which Fixture a draws first: it contributes nothing, so its notice stays out.
    c = build_font(tmp_path / "c.ttf", "Fixture c", "Regular", cps("a"), name_records={0: [(3, 1, 0x409, "Gamma")]})
    output = tmp_path / "out.ttf"
    report = run_forge([a, b, c, d], output)
    assert report.materials[2].warnings == ["contributes no characters"]
    with TTFont(output) as font:
        name = font["name"]
        assert name.getDebugName(0).split("\n") == [
            f"{FORGED_NOTICE} from: Fixture a Regular, Fixture b Regular, Fixture c Regular, Fixture d Regular",
            COPYRIGHT_A,
            cjk,
        ]
        assert name.getName(0, 1, 0, 0) is None  # Mac Roman can't hold the Chinese notice; Windows is enough
    assert naming.is_forged(output) and read_faces(output)[0].is_forged


def test_reforging_carries_source_notices_without_nesting_the_marker(tmp_path):
    paths = notice_sources(tmp_path, {"a": {0: COPYRIGHT_A, 13: OFL, 14: OFL_URL}, "b": {0: COPYRIGHT_B}})
    first = tmp_path / "first.ttf"
    run_forge(paths, first)
    with TTFont(first) as font:
        assert source_notices(font["name"]) == ((0, COPYRIGHT_A), (0, COPYRIGHT_B), (14, OFL_URL), (13, OFL))
    [gamma] = notice_sources(tmp_path, {"c": {0: "Copyright 2019 Gamma"}})
    second = tmp_path / "second.ttf"
    report = run_forge([first, gamma], second)
    with TTFont(second) as font:
        name = font["name"]
        notice = name.getDebugName(0)
        assert notice.split("\n") == [
            f"{FORGED_NOTICE} from: {report.materials[0].name}, Fixture c Regular",
            COPYRIGHT_A,
            COPYRIGHT_B,
            "Copyright 2019 Gamma",
        ]
        assert notice.count(FORGED_NOTICE) == 1
        assert name.getDebugName(14) == OFL_URL
        assert name.getDebugName(13) == LICENCE_NOTES["unknown"] + "\n" + OFL
    assert read_faces(second)[0].is_forged


def test_source_notices_read_one_line_per_notice(font_dir, tmp_path):
    windows_app = decorate(
        font_dir / "A.ttf",
        out=tmp_path / "windows.ttf",
        name_records={0: [(3, 1, 0x409, f"{FORGED_NOTICE} from: Fixture A Regular")], 13: [(3, 1, 0x409, OFL)]},
    )
    with TTFont(windows_app) as font:  # a Windows-app forged font carries no notices of its own sources
        assert source_notices(font["name"]) == ()
    plain = decorate(
        font_dir / "A.ttf",
        out=tmp_path / "plain.ttf",
        name_records={
            0: [(1, 0, 0, "Copyright 2010 Foo."), (3, 1, 0x409, "Copyright 2010 Foo.\r\nCopyright 2015 Bar.\n")],
            7: [(3, 1, 0x409, "   ")],
        },
    )
    with TTFont(plain) as font:
        assert source_notices(font["name"]) == ((0, "Copyright 2010 Foo. Copyright 2015 Bar."),)
    with TTFont(font_dir / "A.ttf") as font:
        assert source_notices(font["name"]) == ()


def test_notices_too_long_for_the_name_table_are_left_out_and_reported(tmp_path, monkeypatch):
    long_a, long_b, short_c = "x" * 20_000, "y" * 15_000, "z" * 1_000
    paths = notice_sources(tmp_path, {"a": {0: COPYRIGHT_A, 13: long_a}, "b": {13: long_b}, "c": {13: short_c}})
    output = tmp_path / "out.ttf"
    report = run_forge(paths, output)
    with TTFont(output) as font:
        assert font["name"].getDebugName(0).endswith("\n" + COPYRIGHT_A)  # copyright notices are kept first
        # b's text no longer fits after a's; c's shorter one still does.
        assert font["name"].getDebugName(13) == "\n".join([LICENCE_NOTES["unknown"], long_a, short_c])
    left_out = [issue for issue in report.issues if issue.code == "notices_left_out"]
    assert [issue.material_index for issue in left_out] == [1]
    assert "(1 left out)" in left_out[0].message and left_out[0].message in report.warnings
    codes = [issue.code for issue in report.issues if issue.material_index == 1]
    assert codes == ["licence_unknown", "notices_left_out"]
    monkeypatch.setattr(merge, "notice_budget", lambda *args: 10**9)  # without the budget the name table overflows
    with pytest.raises(ForgeError) as error:
        run_forge(paths, tmp_path / "unbounded.ttf")
    assert error.value.stage == "finish"


def test_notice_budget_leaves_room_for_long_generated_names(tmp_path, monkeypatch):
    """A long family name alone fits; the notice budget must not let a long copyright push it over 64 KB."""
    [source] = notice_sources(tmp_path, {"a": {0: "c" * 15_900}})
    spec = ForgeSpec([MaterialSpec(read_faces(source)[0])], family_name="F" * 2_200)
    output = tmp_path / "out.ttf"
    report = forge(spec, output)
    with TTFont(output) as font:
        assert font["name"].getDebugName(0) == f"{FORGED_NOTICE} from: Fixture a Regular"
    assert [issue.code for issue in report.issues] == ["licence_unknown", "notices_left_out"]
    monkeypatch.setattr(merge, "notice_budget", lambda *args: 48_000)  # a fixed share ignores the long names
    with pytest.raises(ForgeError) as error:
        forge(spec, tmp_path / "fixed.ttf")
    assert error.value.stage == "finish"
