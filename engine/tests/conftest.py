import os
import sys
from pathlib import Path

import pytest

from tests.fixtures import build_collection, build_font, cps


def pytest_collection_modifyitems(config: pytest.Config, items: list[pytest.Item]) -> None:
    """Keep platform and real-font tests opt-in as specified by docs/testing.md §3."""
    on_macos = sys.platform == "darwin"
    real_fonts = on_macos and os.environ.get("FP_APPLE_FONTS") == "1"
    for item in items:
        if "macos" in item.keywords and not on_macos:
            item.add_marker(pytest.mark.skip(reason="needs macOS"))
        if "apple_fonts" in item.keywords and not real_fonts:
            item.add_marker(pytest.mark.skip(reason="needs macOS and FP_APPLE_FONTS=1 (make engine-apple-fonts)"))


@pytest.fixture(scope="session")
def font_dir(tmp_path_factory: pytest.TempPathFactory) -> Path:
    d = tmp_path_factory.mktemp("fonts")
    a = build_font(d / "A.ttf", "Fixture A", "Regular", cps("abc1,"))
    build_font(d / "B.otf", "Fixture B", "Bold", cps("ab漢，"), cff=True, weight=700)
    c = build_font(d / "C.ttf", "Fixture C", "Regular", cps("a→Ω"), upem=2048, fs_type=2)
    build_font(d / "V.ttf", "Fixture V", "Regular", cps("ab"), variable=True)
    build_collection(d / "T.ttc", [a, c])
    # K: old OS/2 (v1), a composite glyph U+00E0 built from 'a', and a legacy kern pair a/b.
    build_font(
        d / "K.ttf",
        "Fixture K",
        "Regular",
        cps("ab"),
        os2_version=1,
        composites={0xE0: ord("a")},
        kern={(ord("a"), ord("b")): -50},
    )
    return d
