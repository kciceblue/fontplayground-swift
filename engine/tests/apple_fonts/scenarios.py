"""The WP-111 matrix, including its budgets and audit-finding proof mapping."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from tests.apple_fonts.locate import FaceLocation, FontIndex
from tests.apple_fonts.runner import HelperRun


@dataclass(frozen=True)
class Scenario:
    id: str
    materials: tuple[str, ...]
    rules: tuple[tuple[str, int], ...] = ()
    default_weight: int | None = None
    style: str = "Regular"
    family: str | None = None
    expect: str = "ok"
    error_material: int | None = None
    must_issues: frozenset[tuple[str, int | None]] = frozenset()
    max_glyph_ratio: float | None = None
    max_glyphs: int | None = None
    fs_type: int | None = None
    budget_s: float = 15.0
    budget_rss_mb: int = 512
    optional: bool = False
    stale_expect: bool = False
    findings: tuple[str, ...] = ()
    reference: tuple[int, int, float, int] | None = None


CJK = (("kana", 1), ("han", 1), ("cjk_symbols", 1))
CJK_EMOJI = (*CJK, ("emoji", 1))
SCENARIOS = (
    Scenario(
        "AF-01",
        ("HelveticaNeue", "PingFangSC-Regular"),
        CJK_EMOJI,
        max_glyph_ratio=1.10,
        fs_type=4,
        budget_s=60,
        budget_rss_mb=1536,
        findings=("ENGINE-1", "ENGINE-3", "ENGINE-5"),
        reference=(39252, 37350, 17.3, 786),
    ),
    Scenario(
        "AF-02",
        ("PingFangSC-Regular",),
        max_glyph_ratio=1.10,
        budget_s=60,
        budget_rss_mb=1536,
        findings=("ENGINE-3",),
        reference=(38054, 35854, 16.6, 794),
    ),
    Scenario(
        "AF-03",
        (".SFNS-Regular", "HiraginoSans-W3"),
        CJK,
        max_glyph_ratio=1.50,
        fs_type=8,
        budget_s=60,
        budget_rss_mb=1024,
        findings=("ENGINE-3", "ENGINE-6"),
        reference=(19973, 14726, 17.2, 412),
    ),
    Scenario(
        "AF-04",
        ("AvenirNext-Regular", "AppleSDGothicNeo-Regular"),
        (("hangul", 1), *CJK),
        max_glyph_ratio=1.10,
        fs_type=4,
        budget_s=30,
        findings=("ENGINE-3",),
        reference=(18746, 18468, 6.0, 273),
    ),
    Scenario(
        "AF-05",
        ("Georgia", "PingFangHK-Regular"),
        CJK_EMOJI,
        max_glyph_ratio=1.10,
        fs_type=4,
        budget_s=60,
        budget_rss_mb=1536,
        findings=("ENGINE-3", "ENGINE-5"),
        reference=(34504, 33793, 16.4, 763),
    ),
    Scenario(
        "AF-06",
        ("Courier",),
        must_issues=frozenset({("os2_synthesized", 0)}),
        findings=("ENGINE-M1",),
        reference=(1237, 1230, 0.1, 40),
    ),
    Scenario(
        "AF-07",
        ("Courier-Bold",),
        default_weight=700,
        style="Bold",
        must_issues=frozenset({("os2_synthesized", 0)}),
        findings=("ENGINE-M1",),
    ),
    Scenario(
        "AF-08",
        ("AvenirNext-Regular", "AppleGothic"),
        (("hangul", 1),),
        must_issues=frozenset({("os2_synthesized", 1)}),
        budget_s=30,
        findings=("ENGINE-M1",),
        reference=(18417, 18267, 5.0, 204),
    ),
    Scenario(
        "AF-09",
        ("Cochin",),
        must_issues=frozenset({("bitmaps_dropped", 0)}),
        findings=("ENGINE-M2", "ENGINE-1", "ENGINE-12"),
        reference=(1079, 1084, 0.1, 40),
    ),
    Scenario(
        "AF-10",
        ("Geneva",),
        must_issues=frozenset({("bitmaps_dropped", 0)}),
        findings=("ENGINE-M2", "ENGINE-1", "ENGINE-12"),
        reference=(3254, 3249, 0.2, 46),
    ),
    Scenario(
        "AF-11",
        ("AvenirNext-Regular", "AppleMyungjo"),
        (("hangul", 1),),
        must_issues=frozenset({("os2_synthesized", 1), ("bitmaps_dropped", 1)}),
        budget_s=30,
        findings=("ENGINE-M1", "ENGINE-M2"),
        reference=(18373, 18216, 8.1, 247),
    ),
    Scenario(
        "AF-12",
        ("HelveticaNeue-Bold", "PingFangSC-Regular"),
        CJK_EMOJI,
        default_weight=700,
        style="Bold",
        must_issues=frozenset({("synthetic_bold", 1), ("bold_size_doubled", 1)}),
        budget_s=200,
        budget_rss_mb=1792,
        findings=("ENGINE-4",),
        reference=(39246, 37345, 65.2, 1063),
    ),
    Scenario(
        "AF-13",
        (".SFNS-Regular", "HiraginoSans-W6"),
        CJK,
        default_weight=700,
        style="Bold",
        must_issues=frozenset({("synthetic_bold", 1)}),
        budget_s=150,
        budget_rss_mb=1024,
        findings=("ENGINE-4",),
        reference=(19973, 14726, 41.1, 556),
    ),
    Scenario(
        "AF-14",
        ("AvenirNext-Regular", "GeezaPro"),
        (("arabic", 1),),
        expect="aat_unsupported_script",
        error_material=1,
        findings=("ENGINE-2",),
    ),
    Scenario(
        "AF-15",
        ("AvenirNext-Regular", "Damascus"),
        (("arabic", 1),),
        findings=("ENGINE-2", "ENGINE-M4"),
        reference=(2646, 2009, 0.5, 56),
    ),
    Scenario(
        "AF-16",
        ("AvenirNext-Regular", "KohinoorDevanagari-Regular"),
        (("indic", 1),),
        findings=("ENGINE-2",),
        reference=(2153, 1112, 0.6, 63),
    ),
    Scenario(
        "AF-17",
        ("AvenirNext-Regular", "DevanagariMT"),
        (("indic", 1),),
        expect="aat_unsupported_script",
        error_material=1,
        findings=("ENGINE-2",),
    ),
    Scenario(
        "AF-18",
        ("AvenirNext-Regular", "Thonburi"),
        (("southeast_asian", 1),),
        expect="aat_unsupported_script",
        error_material=1,
        findings=("ENGINE-2",),
    ),
    Scenario(
        "AF-19",
        ("AvenirNext-Regular", "PingFangSC-Regular", "HiraginoSans-W3", "AppleSDGothicNeo-Regular"),
        (("han", 1), ("cjk_symbols", 1), ("emoji", 1), ("kana", 2), ("hangul", 3)),
        max_glyph_ratio=1.15,
        max_glyphs=58000,
        fs_type=4,
        budget_s=75,
        budget_rss_mb=1536,
        findings=("ENGINE-3",),
        reference=(53217, 48610, 22.9, 865),
    ),
    Scenario(
        "AF-20",
        ("AvenirNext-Regular", "HiraginoSans-W3", "AppleSDGothicNeo-Regular"),
        (*CJK, ("hangul", 2)),
        must_issues=frozenset({("cmap_format4_partial", None)}),
        budget_s=60,
        budget_rss_mb=1024,
        findings=("N-1",),
        reference=(30915, 26348, 16.0, 482),
    ),
    Scenario(
        "AF-21",
        ("HelveticaNeue", "AppleSymbols"),
        (("symbols", 1), ("emoji", 1), ("other", 1)),
        findings=("ENGINE-1",),
        reference=(5215, 5196, 0.7, 62),
    ),
    Scenario("AF-22", ("HelveticaNeue",), findings=("ENGINE-1", "ENGINE-7"), reference=(2088, 2085, 0.2, 50)),
    Scenario(
        "AF-23",
        ("HelveticaNeue", "STSongti-SC-Regular"),
        CJK_EMOJI,
        max_glyph_ratio=1.10,
        fs_type=8,
        budget_s=45,
        budget_rss_mb=768,
        findings=("ENGINE-3",),
        reference=(34135, 34353, 9.7, 358),
    ),
    Scenario("AF-24", ("NotoSansCham-Regular",), findings=("ENGINE-3", "ENGINE-5"), reference=(132, 104, 0.0, 37)),
    Scenario(
        "AF-25",
        ("ArialUnicodeMS",),
        max_glyph_ratio=1.10,
        budget_s=30,
        budget_rss_mb=768,
        findings=("ENGINE-3",),
        reference=(41280, 38917, 5.8, 381),
    ),
    Scenario(
        "AF-26",
        ("HelveticaNeue", "AppleColorEmoji"),
        (("emoji", 1),),
        expect="unsupported_font",
        error_material=1,
        findings=("ENGINE-12",),
    ),
    Scenario("AF-27", (".SFDevanagari-Regular",), expect="unsupported_font", error_material=0, findings=("ENGINE-12",)),
    Scenario(
        "AF-28",
        ("AvenirNext-Regular", "SIL-Hei-Med-Jian"),
        (("han", 1), ("cjk_symbols", 1)),
        must_issues=frozenset({("os2_synthesized", 1), ("bitmaps_dropped", 1)}),
        optional=True,
        findings=("ENGINE-M1", "ENGINE-M2"),
        reference=(8421, 8266, 2.7, 121),
    ),
    Scenario(
        "AF-29",
        ("AvenirNext-Regular", "AppleSDGothicNeo-Regular"),
        (("hangul", 1), *CJK),
        expect="stale_material",
        error_material=1,
        stale_expect=True,
        findings=("ENGINE-8",),
    ),
    Scenario(
        "AF-30",
        ("AvenirNext-Regular", "Damascus"),
        (("arabic", 1),),
        family="Avenir Next دمشق",
        findings=("ENGINE-M3",),
    ),
    Scenario("AF-31", ("AvenirNext-Regular",), family="我的字体", findings=("ENGINE-M3",)),
)
BY_ID = {scenario.id: scenario for scenario in SCENARIOS}
FINDING_PROOFS = {
    "ENGINE-1": ("AF-01", "AF-09", "AF-10", "AF-21", "AF-22"),
    "ENGINE-2": ("AF-14", "AF-17", "AF-18", "AF-15", "AF-16"),
    "ENGINE-3": ("AF-02", "AF-05", "AF-19", "AF-24", "AF-25"),
    "ENGINE-4": ("AF-12", "AF-13"),
    "ENGINE-5": ("AF-01", "AF-03", "AF-04", "AF-05", "AF-19", "AF-23", "AF-24"),
    "ENGINE-7": ("AF-22", "AF-12"),
    "ENGINE-8": ("AF-29",),
    "ENGINE-12": ("AF-09", "AF-10", "AF-26", "AF-27"),
    "ENGINE-M1": ("AF-06", "AF-07", "AF-08", "AF-11", "AF-28"),
    "ENGINE-M2": ("AF-09", "AF-10", "AF-11", "AF-28"),
    "ENGINE-M3": ("AF-30", "AF-31"),
    "N-1": ("AF-20",),
}
TECHNICAL_ISSUES = frozenset(
    {
        "cmap_format4_partial",
        "bitmaps_dropped",
        "os2_synthesized",
        "synthetic_bold",
        "bold_glyphs_skipped",
        "bold_size_doubled",
    }
)


def forge_request(scenario: Scenario, locations: list[FaceLocation], tmpdir: Path) -> dict:
    materials = [
        {
            "path": location.path,
            "index": location.index,
            "weight": None,
            "scale": None,
            "expect": {"postscript_name": location.postscript_name, "size": location.size, "mtime": location.mtime},
        }
        for location in locations
    ]
    if scenario.stale_expect:
        materials[-1]["expect"]["postscript_name"] = "NotAppleSDGothicNeo"
    return {
        "spec": {
            "materials": materials,
            "base_index": 0,
            "script_rules": dict(scenario.rules),
            "default_weight": scenario.default_weight,
            "default_scale": 1.0,
            "family_name": scenario.family or f"FP Test {scenario.id}",
            "style_name": scenario.style,
        },
        "output_path": str(tmpdir / "out.ttf"),
    }


def check_run(
    scenario: Scenario, run: HelperRun, locations: list[FaceLocation], index: FontIndex, output: Path, factor: float
) -> None:
    import re

    from fontTools.ttLib import TTFont

    from fpengine.prepare import KEEP_TABLES
    from tests.apple_fonts.coretext import check_shaping

    detail = f"{scenario.id}: {run.stderr_tail}\n{run.events[-1:]}"
    assert not run.timed_out, detail
    assert run.wall_s <= scenario.budget_s * factor, (run.wall_s, scenario.budget_s * factor, detail)
    assert run.peak_rss_mb <= scenario.budget_rss_mb, (run.peak_rss_mb, scenario.budget_rss_mb, detail)
    terminals = [event for event in run.events if event.get("type") in {"result", "error"}]
    assert len(terminals) == 1, detail
    assert all(event["protocol"] == 1 for event in run.events), detail
    if scenario.expect != "ok":
        assert run.returncode == 3, detail
        assert run.error is not None, detail
        assert run.error["code"] == scenario.expect, detail
        assert run.error["material_index"] == scenario.error_material, detail
        assert not output.exists(), detail
        return
    assert run.returncode == 0 and run.result is not None and terminals[0]["type"] == "result", detail
    report = run.result
    observed = {(issue["code"], issue["material_index"]) for issue in report["issues"]}
    assert scenario.must_issues <= observed, (scenario.must_issues - observed, detail)
    allowed = {code for code, _ in scenario.must_issues}
    assert not ({code for code, _ in observed} & TECHNICAL_ISSUES) - allowed, detail
    assert all(issue["severity"] != "error" for issue in report["issues"]), detail
    if scenario.max_glyph_ratio is not None:
        assert report["total_glyphs"] <= scenario.max_glyph_ratio * report["total_codepoints"], detail
    if scenario.max_glyphs is not None:
        assert report["total_glyphs"] <= scenario.max_glyphs, detail
    if scenario.fs_type is not None:
        assert report["fs_type"] == scenario.fs_type, detail
    assert report["output_path"] == str(output), detail
    with TTFont(output) as font:
        assert len(font.getBestCmap()) == report["total_codepoints"], detail
        assert font["maxp"].numGlyphs == report["total_glyphs"], detail
        assert set(font.keys()) - {"GlyphOrder"} <= KEEP_TABLES, detail
        if scenario.id in {"AF-03", "AF-13"}:
            assert "fvar" not in font
        if scenario.id == "AF-20":
            assert {(3, 1, 4), (3, 10, 12)} <= {
                (table.platformID, table.platEncID, table.format) for table in font["cmap"].tables
            }
    if scenario.id == "AF-01":
        assert any(note["class"] == "apple-sla" and 1 in note["material_indexes"] for note in report["licence_notes"])
    if scenario.id == "AF-15":
        assert report["materials"][1]["name"].startswith("Damascus")
    if scenario.id in {"AF-22", "AF-24"}:
        source = locations[0]
        with TTFont(source.path, fontNumber=source.index, lazy=True) as font:
            if scenario.id == "AF-22":
                assert report["total_codepoints"] == len(font.getBestCmap())
            else:
                assert report["total_glyphs"] == font["maxp"].numGlyphs
        if scenario.id == "AF-24":
            assert all(note["class"] != "apple-sla" for note in report["licence_notes"])
    if scenario.id in {"AF-30", "AF-31"}:
        name = report["postscript_name"]
        assert re.fullmatch(r"[A-Za-z0-9-]{1,63}", name)
        assert name not in index.faces and name != "AvenirNext-Regular"
    check_shaping(scenario.id, locations, str(output))
