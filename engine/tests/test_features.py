"""ENGINE-3: locale aliases inflated closure and an optional repacker could loop."""

from pathlib import Path
from types import SimpleNamespace

import pytest
from fontTools.feaLib.builder import addOpenTypeFeaturesFromString
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib import TTFont
from fontTools.ttLib.tables import otBase
from fontTools.ttLib.tables.otBase import USE_HARFBUZZ_REPACKER

from fpengine.face import read_faces
from fpengine.forge import forge
from fpengine.prepare import is_discretionary, kept_features, prepare
from fpengine.spec import ForgeSpec, MaterialSpec
from tests.fixtures import cps

FEATURES = """
languagesystem DFLT dflt; languagesystem latn dflt; languagesystem latn TRK;
lookup LOCL_A { sub uni0061 by a.locl; } LOCL_A;
lookup LOCL_B { sub uni0062 by b.locl; } LOCL_B;
feature locl { script latn; language TRK; lookup LOCL_A; lookup LOCL_B; } locl;
feature cv01 { lookup LOCL_A; } cv01;
feature clig { lookup LOCL_B; } clig;
feature salt { sub uni0062 by b.salt; } salt;
feature aalt { feature salt; sub uni0063 from [c.alt]; } aalt;
feature liga { sub uni0061 uni0062 by uni0063; } liga;
feature kern { pos uni0061 uni0062 -50; } kern;
"""


def _font(path: Path, *, features: str = FEATURES, alternates: tuple[str, ...] = ()) -> Path:
    order = [".notdef", "uni0061", "uni0062", "uni0063", "a.locl", "b.locl", "b.salt", "c.alt", *alternates]
    builder = FontBuilder(1000, isTTF=True)
    builder.setupGlyphOrder(order)
    builder.setupCharacterMap({ord(c): f"uni{ord(c):04X}" for c in "abc"})
    glyphs = {}
    for name in order:
        pen = TTGlyphPen(None)
        pen.moveTo((50, 0))
        pen.lineTo((150, 0))
        pen.lineTo((150, 700))
        pen.lineTo((50, 700))
        pen.closePath()
        glyphs[name] = pen.glyph()
    builder.setupGlyf(glyphs)
    builder.setupHorizontalMetrics({name: (200, 50) for name in order})
    builder.setupHorizontalHeader(ascent=800, descent=-200)
    builder.setupNameTable({"familyName": "Fixture F", "styleName": "Regular"})
    builder.setupOS2()
    builder.setupPost()
    addOpenTypeFeaturesFromString(builder.font, features)
    builder.save(path)
    return path


def _spec(font_dir: Path, feature_path: Path) -> ForgeSpec:
    return ForgeSpec(
        [MaterialSpec(read_faces(font_dir / "A.ttf")[0]), MaterialSpec(read_faces(feature_path)[0])],
        script_rules={"latin": 1},
    )


def test_kept_features_drops_aalt_and_discretionary_aliases(tmp_path: Path) -> None:
    with TTFont(_font(tmp_path / "F.ttf")) as font:
        assert kept_features(font) == ["clig", "kern", "liga", "salt"]


def test_engine_3_locl_alias_and_aalt_dropped(tmp_path: Path) -> None:
    """Reference kept a.locl via cv01 and c.alt via aalt; clig must retain b.locl."""
    face = read_faces(_font(tmp_path / "F.ttf"))[0]
    part = prepare(MaterialSpec(face), cps("abc"), 1000, None, 1.0, tmp_path, 0)
    with TTFont(part.path) as font:
        assert font.getGlyphOrder() == [".notdef", "uni0061", "uni0062", "uni0063", "b.locl", "b.salt"]


def test_alias_rule_is_per_table(tmp_path: Path) -> None:
    features = """
        languagesystem DFLT dflt;
        lookup SUB0 { sub uni0061 by a.ss01; } SUB0;
        lookup SUB1 { sub uni0062 by b.locl; } SUB1;
        lookup POS0 { pos uni0061 uni0062 -20; } POS0;
        lookup POS1 { pos uni0062 uni0063 -30; } POS1;
        feature locl { lookup SUB1; } locl;
        feature ss01 { lookup SUB0; } ss01;
        feature ss03 { lookup SUB1; } ss03;
        feature kern { lookup POS0; } kern;
        feature ss02 { lookup POS1; } ss02;
    """
    with TTFont(_font(tmp_path / "per-table.ttf", features=features, alternates=("a.ss01",))) as font:
        assert kept_features(font) == ["kern", "ss01", "ss02"]


def test_is_discretionary() -> None:
    for tag in "salt smpl trad nalt swsh jp78 ss01 ss20 cv01 cv99".split():
        assert is_discretionary(tag), tag
    for tag in "ccmp locl rlig liga clig calt kern mark mkmk init medi fina isol vert vrt2 ss00 ss21 cv00 aalt".split():
        assert not is_discretionary(tag), tag


def test_engine_3_hb_repacker_disabled(font_dir: Path, tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    """Reference invokes the sentinel during prepare; disabling must survive merging."""
    feature_path = _font(tmp_path / "F.ttf")
    spec = _spec(font_dir, feature_path)

    class Sentinel(Exception):
        pass

    class RepackerError(Exception):
        pass

    def rejected(*args, **kwargs):
        raise Sentinel("HarfBuzz repacker was invoked")

    monkeypatch.setattr(otBase, "have_uharfbuzz", True)
    monkeypatch.setattr(
        otBase,
        "hb",
        SimpleNamespace(
            serialize_with_tag=rejected, repack=rejected, repack_with_tag=rejected, RepackerError=RepackerError
        ),
        raising=False,
    )
    with TTFont(feature_path) as control, pytest.raises(Sentinel):
        control["GSUB"].compile(control)
    report = forge(spec, tmp_path / "forged.ttf")
    assert report.total_codepoints > 0


def test_repacker_cfg_false_on_every_saved_font(
    font_dir: Path, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    spec = _spec(font_dir, _font(tmp_path / "F.ttf"))
    original = TTFont.save
    saved = []

    def save(font, *args, **kwargs):
        saved.append(font.cfg[USE_HARFBUZZ_REPACKER])
        return original(font, *args, **kwargs)

    monkeypatch.setattr(TTFont, "save", save)
    forge(spec, tmp_path / "forged.ttf")
    assert saved == [False, False, False]
