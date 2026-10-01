"""Generate the helper specification's deterministic nine-file font inventory."""

from __future__ import annotations

import argparse
import json
import tempfile
from dataclasses import asdict, dataclass
from pathlib import Path

from fpengine import __version__
from fpengine.records import expand, ranges
from fpengine.testing.fonts import atomic_write, build_collection, build_font


@dataclass(frozen=True)
class FixtureFace:
    index: int
    family: str
    style: str
    postscript_name: str
    weight_class: int
    italic: bool
    outline: str
    upem: int
    coverage: tuple[tuple[int, int], ...]
    supported: bool


@dataclass(frozen=True)
class FixtureFont:
    file: str
    faces: tuple[FixtureFace, ...]
    expect: str = "faces"


SANS = ((32, 126), (160, 255), (913, 929), (931, 937), (945, 969))
CJK = tuple(
    tuple(pair)
    for pair in ranges(
        expand(((32, 126), (0x3000, 0x303F), (0x3041, 0x3096), (0x30A1, 0x30FA), (0x4E00, 0x59FF), (0xFF01, 0xFF5E)))
        | {ord(character) for character in "这说门来"}
    )
)


def _face(
    family: str,
    style: str,
    coverage: tuple,
    *,
    index: int = 0,
    weight: int = 400,
    italic: bool = False,
    outline: str = "glyf",
    upem: int = 1000,
    supported: bool = True,
) -> FixtureFace:
    return FixtureFace(
        index, family, style, f"{family}-{style}".replace(" ", ""), weight, italic, outline, upem, coverage, supported
    )


FIXTURE_FONTS: tuple[FixtureFont, ...] = (
    FixtureFont("FixtureSans-Regular.ttf", (_face("Fixture Sans", "Regular", SANS),)),
    FixtureFont("FixtureSans-Bold.ttf", (_face("Fixture Sans", "Bold", SANS, weight=700),)),
    FixtureFont("FixtureCJK-Regular.otf", (_face("Fixture CJK", "Regular", CJK, outline="CFF"),)),
    FixtureFont(
        "FixtureHangul-Regular.ttf", (_face("Fixture Hangul", "Regular", ((48, 57), (0xAC00, 0xB3FF)), upem=2048),)
    ),
    FixtureFont(
        "FixtureSerif.ttc",
        (
            _face("Fixture Serif", "Regular", ((32, 126),)),
            _face("Fixture Serif", "Italic", ((32, 126),), index=1, italic=True),
        ),
    ),
    FixtureFont("FixtureVariable-Regular.ttf", (_face("Fixture Variable", "Regular", ((32, 126),)),)),
    FixtureFont("FixtureColor-Regular.ttf", (_face("Fixture Color", "Regular", ((65, 90),), supported=False),)),
    FixtureFont("FixtureRestricted-Regular.ttf", (_face("Fixture Restricted", "Regular", ((97, 122),)),)),
    FixtureFont("NotAFont.ttf", (), "file_error:unreadable"),
)


def _make_face(path: Path, face: FixtureFace) -> Path:
    return build_font(
        path,
        face.family,
        face.style,
        expand(face.coverage),
        upem=face.upem,
        cff=face.outline == "CFF",
        weight=face.weight_class,
        italic=face.italic,
        fs_type=2 if face.family == "Fixture Restricted" else 0,
        variable=face.family == "Fixture Variable",
        color=face.family == "Fixture Color",
    )


def make_fonts(directory: Path) -> Path:
    directory = directory.resolve()
    directory.mkdir(parents=True, exist_ok=True)
    for fixture in FIXTURE_FONTS:
        destination = directory / fixture.file
        if not fixture.faces:
            atomic_write(destination, b"This is not a font file.\n" * 3)
        elif len(fixture.faces) == 1:
            _make_face(destination, fixture.faces[0])
        else:
            with tempfile.TemporaryDirectory(prefix="fp-fixture-serif-") as work:
                members = [_make_face(Path(work) / f"{face.index}.ttf", face) for face in fixture.faces]
                build_collection(destination, members)
    manifest = directory / "fonts.json"
    payload = {
        "generator": "fpengine.testing.make_fonts",
        "version": 1,
        "fpengine_version": __version__,
        "fonts": [
            {"file": fixture.file, "expect": fixture.expect, "faces": [asdict(face) for face in fixture.faces]}
            for fixture in FIXTURE_FONTS
        ],
    }
    atomic_write(manifest, (json.dumps(payload, ensure_ascii=False, indent=2, allow_nan=False) + "\n").encode("utf-8"))
    return manifest


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    args = parser.parse_args(argv)
    print(make_fonts(args.directory))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
