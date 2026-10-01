import importlib
import importlib.metadata
import tomllib
from pathlib import Path

import fontTools

import fpengine


def test_version() -> None:
    assert fpengine.__version__ == importlib.metadata.version("fpengine")


def test_version_matches_pyproject() -> None:
    with (Path(__file__).resolve().parents[1] / "pyproject.toml").open("rb") as project_file:
        project = tomllib.load(project_file)
    assert fpengine.__version__ == project["project"]["version"]


def test_runtime_dependencies_import() -> None:
    for module in ("fontTools", "pathops", "unicodedata2"):
        importlib.import_module(module)
    assert tuple(int(part) for part in fontTools.version.split(".")[:2]) >= (4, 65)
