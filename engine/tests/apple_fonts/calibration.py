"""The fixed glyph estimate shared with the future FPCore planner (WP-303)."""

from collections.abc import Sequence

VARIANT_FACTOR = 0.8
GLYPH_WARN = 55_000
MAX_GLYPHS = 65_535
CALIBRATION = ("AF-01", "AF-02", "AF-03", "AF-04", "AF-05", "AF-19", "AF-20", "AF-23")


def estimate(glyph_counts: Sequence[int], cmap_sizes: Sequence[int], assigned: Sequence[int]) -> int:
    return 1 + sum(round(g * a / max(c, 1) * VARIANT_FACTOR) for g, c, a in zip(glyph_counts, cmap_sizes, assigned))
