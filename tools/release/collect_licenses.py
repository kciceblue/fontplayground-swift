#!/usr/bin/env python3
"""Read the embedded interpreter's metadata, never the developer environment's wheels."""

from __future__ import annotations

import argparse
import importlib.metadata
import json
import os
import platform
import plistlib
import re
import subprocess
import sys
import tempfile
from pathlib import Path

REQUIRED = {"Font Playground", "CPython", "fonttools", "skia-pathops", "unicodedata2"}


def atomic_write(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
        directory = os.open(path.parent, os.O_RDONLY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
    finally:
        Path(temporary).unlink(missing_ok=True)


def component_name(name: str) -> str:
    value = re.sub(r"[^A-Za-z0-9._-]", "", name.replace(" ", "-"))
    if value in {"", ".", ".."}:
        raise ValueError(f"Invalid component name: {name}")
    return value


def wheel_license(distribution: importlib.metadata.Distribution) -> str:
    metadata = distribution.metadata
    expression = metadata.get("License-Expression", "").strip()
    if expression:
        return expression
    value = metadata.get("License", "").strip()
    known = {"MIT": "MIT", "MIT License": "MIT", "Apache 2.0": "Apache-2.0", "BSD": "BSD-3-Clause"}
    if value in known:
        return known[value]
    for classifier in metadata.get_all("Classifier", []):
        if classifier.endswith(" :: MIT License"):
            return "MIT"
        if classifier.endswith(" :: Apache Software License"):
            return "Apache-2.0"
        if classifier.endswith(" :: BSD License"):
            return "BSD-3-Clause"
    return "LicenseRef-see-file"


def collect(app: Path, repo: Path) -> tuple[list[dict], dict[str, bytes], list[str]]:
    components: list[dict] = []
    texts: dict[str, bytes] = {}
    problems: list[str] = []

    def add(name: str, version: str, license_id: str, kind: str, files: list[tuple[str, Path]]) -> None:
        directory = component_name(name)
        paths = []
        for filename, source in files:
            target = f"{directory}/{filename}"
            try:
                data = source.read_bytes()
            except OSError as error:
                problems.append(f"{name}: cannot read {source}: {error}")
                continue
            if not data.strip():
                problems.append(f"{name}: empty licence file {source}")
                continue
            if target in texts and texts[target] != data:
                problems.append(f"{name}: colliding licence path {target}")
                continue
            texts[target] = data
            paths.append(target)
        if not paths:
            problems.append(f"{name}: no licence files")
        components.append({"name": name, "version": version, "license": license_id, "kind": kind, "files": paths})

    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    add("Font Playground", info["CFBundleShortVersionString"], "MIT", "app", [("LICENSE.txt", repo / "LICENSE")])
    prefix = app / "Contents/Resources/fpengine"
    add(
        "CPython",
        platform.python_version(),
        "PSF-2.0",
        "runtime",
        [("LICENSE.txt", prefix / "lib/python3.12/LICENSE.txt")],
    )
    for distribution in sorted(importlib.metadata.distributions(), key=lambda item: item.metadata["Name"].lower()):
        name = distribution.metadata["Name"]
        if name.lower() == "fpengine":
            continue
        files = []
        for file in distribution.files or []:
            if "licenses" in file.parts or file.name.upper().startswith(("LICENSE", "COPYING", "NOTICE")):
                filename = (
                    "/".join(file.parts[file.parts.index("licenses") + 1 :]) if "licenses" in file.parts else file.name
                )
                files.append((filename, Path(distribution.locate_file(file))))
        add(name, distribution.version, wheel_license(distribution), "wheel", files)

    manifest = repo / "App/Licenses/components.json"
    if manifest.exists():
        entries = json.loads(manifest.read_text())
        if isinstance(entries, dict):
            entries = entries["components"]
        for entry in entries:
            version = ""
            detect = entry.get("detect", {})
            if "python" in detect:
                result = subprocess.run(
                    [sys.executable, "-I", "-B", "-c", detect["python"]], capture_output=True, text=True
                )
                if result.returncode:
                    print(f"collect-licenses: not present: {entry['name']}")
                    continue
                version = result.stdout.strip()
            elif "bytes" in detect:
                if detect["bytes"].encode("ascii") not in (prefix / "lib/libpython3.12.dylib").read_bytes():
                    print(f"collect-licenses: not present: {entry['name']}")
                    continue
                # TOOLING-11: a binary marker proves presence, not a library version.
            add(
                entry["name"],
                version,
                entry["license"],
                "static",
                [(Path(file).name, repo / "App/Licenses" / file) for file in entry["files"]],
            )
    missing = REQUIRED - {entry["name"] for entry in components}
    problems.extend(f"missing required component: {name}" for name in sorted(missing))
    return components, texts, problems


def check_existing(directory: Path, components: list[dict]) -> list[str]:
    problems = []
    try:
        index = json.loads((directory / "index.json").read_text())
        if index.get("format") != "fp-licenses" or index.get("version") != 1:
            return ["invalid licence index format"]
        listed = {entry["name"]: entry for entry in index["components"]}
        for expected in components:
            entry = listed.get(expected["name"])
            if entry is None:
                problems.append(f"index lacks component: {expected['name']}")
            elif entry != expected:
                problems.append(f"index metadata differs: {expected['name']}")
        for entry in listed.values():
            if not entry["files"]:
                problems.append(f"{entry['name']}: no listed licence files")
            for file in entry["files"]:
                path = directory / file
                if (
                    not path.resolve().is_relative_to(directory.resolve())
                    or not path.is_file()
                    or not path.read_bytes().strip()
                ):
                    problems.append(f"missing or empty licence file: {file}")
    except (OSError, ValueError, KeyError, TypeError) as error:
        problems.append(f"cannot read licence index: {error}")
    return problems


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, required=True)
    parser.add_argument("--repo", type=Path, required=True)
    parser.add_argument("--check", action="store_true")
    arguments = parser.parse_args()
    app, repo = arguments.app.resolve(), arguments.repo.resolve()
    python = app / "Contents/Resources/fpengine/bin/python3"
    if not python.is_file():
        parser.error(f"embedded interpreter is missing: {python}")
    if Path(sys.executable).resolve() != python.resolve():
        os.execv(python, [str(python), "-I", "-B", str(Path(__file__).resolve()), *sys.argv[1:]])
    components, texts, problems = collect(app, repo)
    directory = app / "Contents/Resources/Licenses"
    if arguments.check:
        problems.extend(check_existing(directory, components))
    if problems:
        for problem in problems:
            print(f"collect-licenses: {problem}", file=sys.stderr)
        return 1
    if not arguments.check:
        for file, data in texts.items():
            atomic_write(directory / file, data)
        atomic_write(
            directory / "index.json",
            (json.dumps({"format": "fp-licenses", "version": 1, "components": components}, indent=2) + "\n").encode(),
        )
        introduction = repo / "App/Resources/Acknowledgements.txt"
        acknowledgements = introduction.read_text() if introduction.exists() else "Font Playground\n"
        acknowledgements += "\nLicence texts\n"
        for component in components:
            title = " ".join(value for value in (component["name"], component["version"]) if value)
            acknowledgements += f"\n== {title} ({component['license']}) ==\n"
            for file in component["files"]:
                acknowledgements += texts[file].decode("utf-8", errors="replace") + "\n"
        atomic_write(app / "Contents/Resources/Acknowledgements.txt", acknowledgements.encode())
    print(f"collect-licenses: OK ({len(components)} components, {len(texts)} texts)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
