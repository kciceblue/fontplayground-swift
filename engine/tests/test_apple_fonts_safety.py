"""Checks of the real-font suite's opt-in and file-only boundary that need no real fonts."""

import os
import re
import subprocess
import sys
import time
from pathlib import Path

from tests.apple_fonts import locate

SUITE = Path(__file__).parent / "apple_fonts"


def test_no_name_lookups_or_installs():
    forbidden = (
        "CTFontCreateWithName",
        "CTFontDescriptorCreateWithNameAndSize",
        "CTFontDescriptorCreateMatchingFontDescriptor",
        "CTFontDescriptorCreateWithAttributes",
        "CTFontManagerRegister",
        "CTFontManagerActivate",
        "NSFont",
        "AppKit",
        "shutil.copy",
        "shutil.move",
        "copyfile",
    )
    for path in SUITE.rglob("*.py"):
        text = path.read_text()
        assert not any(name in text for name in forbidden), path
        if path.name != "conftest.py":
            assert "Path.home" not in text and "expanduser" not in text, path
    assert all(str(root).startswith("/System/Library/") for root in locate.SEARCH_ROOTS)
    assert locate.ASSET_GLOB.startswith("/System/Library/")


def test_apple_fonts_gated_without_env():
    env = dict(os.environ)
    env.pop("FP_APPLE_FONTS", None)
    started = time.monotonic()
    run = subprocess.run(
        [sys.executable, "-m", "pytest", "-q", "-p", "no:cacheprovider", str(SUITE)],
        env=env,
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert run.returncode == 0, run.stdout + run.stderr
    summary = run.stdout.splitlines()[-1]
    assert re.search(r"\b\d+ skipped\b", summary) and not re.search(r"\b(passed|failed|error)\b", summary), summary
    assert time.monotonic() - started < 30


def test_interim_report_fields_are_gone():
    from fpengine.protocol.report import INTERIM_REPORT_FIELDS

    assert INTERIM_REPORT_FIELDS == {}
