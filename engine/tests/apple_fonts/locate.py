"""Find system faces from file name tables without asking the font service to match names."""

from __future__ import annotations

import glob
import unicodedata
from collections.abc import Sequence
from dataclasses import dataclass
from pathlib import Path

from fontTools.ttLib import TTCollection, TTFont

SEARCH_ROOTS = (Path("/System/Library/Fonts"), Path("/System/Library/Fonts/Supplemental"))
ASSET_GLOB = "/System/Library/AssetsV2/com_apple_MobileAsset_Font*/*/AssetData"
FONT_SUFFIXES = (".ttf", ".otf", ".ttc", ".otc")


@dataclass(frozen=True)
class FaceLocation:
    postscript_name: str
    path: str
    index: int
    size: int
    mtime: float


@dataclass
class FontIndex:
    faces: dict[str, FaceLocation]
    unreadable: list[str]


def search_dirs(roots: Sequence[Path] = SEARCH_ROOTS, asset_glob: str = ASSET_GLOB) -> list[Path]:
    return [*roots, *(Path(path) for path in sorted(glob.glob(asset_glob)))]


def build_index(dirs: Sequence[Path]) -> FontIndex:
    index = FontIndex({}, [])
    for directory in dirs:
        if not directory.exists():
            continue
        try:
            paths = sorted(directory.iterdir(), key=lambda path: (unicodedata.normalize("NFC", path.name), path.name))
        except OSError as error:
            index.unreadable.append(f"{directory}: {error}")
            continue
        for path in paths:
            if path.suffix.lower() not in FONT_SUFFIXES or not path.is_file():
                continue
            container = None
            try:
                stat = path.stat()
                if path.suffix.lower() in {".ttc", ".otc"}:
                    container = TTCollection(path, lazy=True)
                    fonts = container.fonts
                else:
                    container = TTFont(path, lazy=True)
                    fonts = [container]
                for number, font in enumerate(fonts):
                    name = font["name"].getDebugName(6)
                    if name:
                        index.faces.setdefault(
                            name, FaceLocation(name, str(path.absolute()), number, stat.st_size, stat.st_mtime)
                        )
            except Exception as error:
                index.unreadable.append(f"{path}: {type(error).__name__}: {error}")
            finally:
                if container is not None:
                    container.close()
    return index
