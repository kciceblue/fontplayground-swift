"""File discovery is deterministic, name-table-only, and independent of CoreText."""

import unicodedata

from fontTools.ttLib import TTFont

from tests.apple_fonts.locate import build_index, search_dirs
from tests.fixtures import build_collection, build_font, cps
from tests.meta_fixtures import decorate


def _named(path, postscript):
    return build_font(path, "Fixture", "Regular", cps("a"), name_records={6: [(3, 1, 0x409, postscript)]})


def test_apple_font_file_locator_order_collections_and_nfd(tmp_path):
    roots = [tmp_path / "Fonts", tmp_path / "Fonts/Supplemental"]
    asset = tmp_path / "AssetsV2/com_apple_MobileAsset_Font9/abc.asset/AssetData"
    for directory in (*roots, asset):
        directory.mkdir(parents=True, exist_ok=True)
    first = _named(roots[0] / "A.TTF", "Priority")
    _named(roots[1] / "B.ttf", "Priority")
    _named(asset / "C.ttf", "Priority")
    _named(asset / "asset.ttf", "AssetOnly")
    nfd = roots[1] / (unicodedata.normalize("NFD", "ヒラギノ W3") + ".ttf")
    _named(nfd, "HiraginoFixture")
    # Corrupt outlines and maps must not affect a locator that reads only name records.
    decorate(nfd, tables={"glyf": b"bad", "cmap": b"bad"})
    ttc_sources = [_named(tmp_path / f"source-{i}.ttf", f"Collection-{i}") for i in range(2)]
    collection = build_collection(roots[0] / "Faces.ttc", ttc_sources)
    (roots[0] / "garbage.otf").write_bytes(b"not a font")
    (roots[0] / "ignored.txt").write_text("ignored")
    (roots[0] / "nested").mkdir()
    _named(roots[0] / "nested/hidden.ttf", "Nested")
    dirs = search_dirs(roots, str(tmp_path / "AssetsV2/com_apple_MobileAsset_Font*/*/AssetData"))
    assert dirs == [*roots, asset]
    index = build_index([*dirs, tmp_path / "missing"])
    assert index.faces["Priority"].path == str(first)
    stat = first.stat()
    assert (index.faces["Priority"].size, index.faces["Priority"].mtime) == (stat.st_size, stat.st_mtime)
    assert index.faces["HiraginoFixture"].path == str(nfd)
    assert index.faces["AssetOnly"].path == str(asset / "asset.ttf")
    for number in range(2):
        face = index.faces[f"Collection-{number}"]
        assert face.path == str(collection) and face.index == number
    assert len(index.unreadable) == 1 and "garbage.otf" in index.unreadable[0]
    assert "Missing" not in index.faces and "Nested" not in index.faces
    with TTFont(first) as font:
        assert font["name"].getDebugName(6) == "Priority"


def test_apple_font_file_locator_sorts_normalized_file_names(tmp_path):
    # Unicode-normalized order chooses the ASCII-prefixed name before the CJK name.
    _named(tmp_path / "漢.ttf", "Duplicate")
    preferred = _named(tmp_path / "A.ttf", "Duplicate")
    assert build_index([tmp_path]).faces["Duplicate"].path == str(preferred)
