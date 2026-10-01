"""Distribution guards run without Apple tools; native scripts verify actual products on macOS."""

import importlib.util
import json
import os
import plistlib
import re
import shutil
import struct
import subprocess
import sys
import tomllib
import types
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[3]


def test_tooling_8_single_version() -> None:
    app = re.search(r"^MARKETING_VERSION\s*=\s*(\S+)", (ROOT / "App/Version.xcconfig").read_text(), re.M)[1]
    engine = tomllib.loads((ROOT / "engine/pyproject.toml").read_text())["project"]["version"]
    assert app == engine


def test_tooling_8_info_plist_release_keys() -> None:
    info = plistlib.loads((ROOT / "App/Info.plist").read_bytes())
    copyright_line = next(line for line in (ROOT / "LICENSE").read_text().splitlines() if line.startswith("Copyright"))
    expected = {
        "CFBundleName": "Font Playground",
        "CFBundleDisplayName": "Font Playground",
        "CFBundlePackageType": "APPL",
        "LSApplicationCategoryType": "public.app-category.graphics-design",
        "NSHumanReadableCopyright": copyright_line,
        "CFBundleDevelopmentRegion": "en",
        "NSHighResolutionCapable": True,
        "CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)",
        "CFBundleExecutable": "$(EXECUTABLE_NAME)",
        "CFBundleShortVersionString": "$(MARKETING_VERSION)",
        "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
        "LSMinimumSystemVersion": "$(MACOSX_DEPLOYMENT_TARGET)",
        "CFBundleIconName": "AppIcon",
        "CFBundleIconFile": "AppIcon",
    }
    for key, value in expected.items():
        assert info[key] == value
    for name in ["DocumentsFolder", "DesktopFolder", "DownloadsFolder", "RemovableVolumes", "NetworkVolumes"]:
        assert isinstance(info[f"NS{name}UsageDescription"], str) and info[f"NS{name}UsageDescription"].strip()
    assert not {"NSRequiresAquaSystemAppearance", "UIDesignRequiresCompatibility", "LSUIElement"} & info.keys()
    assert "ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon" in (ROOT / "App/project.yml").read_text()


def test_tooling_9_icon_composer_document() -> None:
    directory = ROOT / "App/Resources/AppIcon.icon"
    icon = json.loads((directory / "icon.json").read_text())
    assert icon["groups"]
    for group in icon["groups"]:
        for layer in group["layers"]:
            png = (directory / "Assets" / layer["image-name"]).read_bytes()
            assert png[:8] == b"\x89PNG\r\n\x1a\n"
            assert png[12:16] == b"IHDR"
            assert struct.unpack(">II", png[16:24]) == (1024, 1024)
            assert png[25] in {4, 6}, "The mark needs an alpha channel, not a baked-in background."
    assert not (ROOT / "App/Resources/Assets.xcassets/AppIcon.appiconset").exists()


def test_tooling_10_arm64_only_build_settings() -> None:
    assert re.search(r"^\s+ARCHS: arm64$", (ROOT / "App/project.yml").read_text(), re.M)
    assert "lipo -thin arm64" in (ROOT / "scripts/embed-helper.sh").read_text()


def test_tooling_1_release_order() -> None:
    assert "ENABLE_DEBUG_DYLIB: NO" in (ROOT / "App/project.yml").read_text()
    release = (ROOT / "scripts/release.sh").read_text()
    assert release.index('notarize.sh "$APP"') < release.index("make-dmg.sh") < release.index('notarize.sh "$DMG"')
    sign = (ROOT / "scripts/sign-app.sh").read_text()
    for line in sign.splitlines():
        if "--deep" in line and not line.lstrip().startswith("#"):
            assert "--verify" in line and "--sign" not in line
    workflow = (ROOT / ".github/workflows/release.yml").read_text()
    assert set(re.findall(r"secrets\.([A-Z0-9_]+)", workflow)) == {
        "MACOS_DEVELOPER_ID_P12_BASE64",
        "MACOS_DEVELOPER_ID_P12_PASSWORD",
        "MACOS_DEVELOPER_ID_IDENTITY",
        "NOTARY_API_KEY_P8_BASE64",
        "NOTARY_API_KEY_ID",
        "NOTARY_API_ISSUER_ID",
    }
    actions = re.findall(r"uses:\s+([^\s]+)", workflow)
    assert actions and all(re.fullmatch(r"[^@]+@[a-f0-9]{40}", action) for action in actions)
    assert (
        "github.event_name == 'pull_request' || (github.event_name == 'workflow_dispatch' && inputs.adhoc)" in workflow
    )


def test_crit_1_release_runs_sdk_check() -> None:
    for path in ["scripts/release.sh", ".github/workflows/ci.yml"]:
        assert "scripts/check-sdk.sh" in (ROOT / path).read_text()


def test_tooling_11_licence_collection_is_wired() -> None:
    project = (ROOT / "App/project.yml").read_text()
    assert project.index("Embed fpengine helper runtime") < project.index("Collect licences")
    assert "scripts/collect-licenses.sh" in project


def test_tooling_11_license_check_detects_missing_component_and_text(tmp_path: Path) -> None:
    spec = importlib.util.spec_from_file_location("collector", ROOT / "tools/release/collect_licenses.py")
    collector = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(collector)
    components = [{"name": "Example", "version": "1", "license": "MIT", "kind": "wheel", "files": ["Example/LICENSE"]}]
    index = {"format": "fp-licenses", "version": 1, "components": components}
    collector.atomic_write(tmp_path / "index.json", json.dumps(index).encode())
    assert collector.check_existing(tmp_path, components) == ["missing or empty licence file: Example/LICENSE"]
    collector.atomic_write(tmp_path / "Example/LICENSE", b"Copyright Example\nPermission granted.\n")
    assert collector.check_existing(tmp_path, components) == []
    (tmp_path / "Example/LICENSE").write_bytes(b"")
    assert collector.check_existing(tmp_path, components)
    index["components"] = []
    collector.atomic_write(tmp_path / "index.json", json.dumps(index).encode())
    assert collector.check_existing(tmp_path, components) == ["index lacks component: Example"]


def test_tooling_11_license_index_cannot_escape_bundle(tmp_path: Path) -> None:
    spec = importlib.util.spec_from_file_location("collector", ROOT / "tools/release/collect_licenses.py")
    collector = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(collector)
    index = {"format": "fp-licenses", "version": 1, "components": [{"name": "Bad", "files": ["../escape"]}]}
    (tmp_path / "index.json").write_text(json.dumps(index))
    assert collector.check_existing(tmp_path, []) == ["missing or empty licence file: ../escape"]


def _licence_bundle(tmp_path: Path, entries: list[dict]) -> tuple[Path, Path]:
    """A repo listing `entries` as static components, and an app whose embedded interpreter is this one."""
    repo, app = tmp_path / "repo", tmp_path / "Font Playground.app"
    prefix = app / "Contents/Resources/fpengine"
    (prefix / "bin").mkdir(parents=True)
    (prefix / "bin/python3").symlink_to(sys.executable)
    (prefix / "lib/python3.12").mkdir(parents=True)
    (prefix / "lib/python3.12/LICENSE.txt").write_text("Python licence fixture\n")
    (app / "Contents/Info.plist").write_bytes(plistlib.dumps({"CFBundleShortVersionString": "0.1.0"}))
    (repo / "App/Licenses").mkdir(parents=True)
    (repo / "App/Licenses/components.json").write_text(json.dumps(entries))
    (repo / "LICENSE").write_text("App licence fixture\n")
    for file in {file for entry in entries for file in entry["files"]}:
        path = repo / "App/Licenses" / file
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("Static component licence fixture\n")
    return repo, app


@pytest.mark.parametrize("name", ["XZ Utils (liblzma)", "bzip2", "libffi", "libuuid (util-linux)", "HACL*"])
def test_tooling_11_byte_detection_is_presence_not_a_version(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str], name: str
) -> None:
    """Runtime error strings identify bundled libraries, not their user-visible versions."""
    spec = importlib.util.spec_from_file_location("collector", ROOT / "tools/release/collect_licenses.py")
    collector = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(collector)
    entry = next(
        item for item in json.loads((ROOT / "App/Licenses/components.json").read_text()) if item["name"] == name
    )
    marker = entry["detect"]["bytes"]
    versioned = {**entry, "name": "Versioned static component", "detect": {"python": "print('5.6.0')"}}
    repo, app = _licence_bundle(tmp_path, [entry, versioned])
    resources = app / "Contents/Resources"
    monkeypatch.setattr(collector.importlib.metadata, "distributions", lambda: [])
    monkeypatch.setattr(collector, "REQUIRED", {"Font Playground", "CPython"})
    monkeypatch.setattr(sys, "argv", ["collect_licenses.py", "--app", str(app), "--repo", str(repo)])

    library = resources / "fpengine/lib/libpython3.12.dylib"
    library.write_bytes(b"No static-library marker here")
    assert collector.main() == 0
    assert f"collect-licenses: not present: {name}" in capsys.readouterr().out
    index = resources / "Licenses/index.json"
    assert name not in {item["name"] for item in json.loads(index.read_text())["components"]}

    library.write_bytes(b"prefix\0" + marker.encode("ascii") + b"\0suffix")
    assert collector.main() == 0
    components = json.loads(index.read_text())["components"]
    found = next(item for item in components if item["name"] == name)
    assert found["version"] == ""
    assert found["license"] == entry["license"]
    assert found["files"]
    assert all(
        (resources / "Licenses" / file).read_text() == "Static component licence fixture\n" for file in found["files"]
    )
    acknowledgements = (resources / "Acknowledgements.txt").read_text()
    assert f"== {name} ({entry['license']}) ==" in acknowledgements
    assert next(item for item in components if item["name"] == versioned["name"])["version"] == "5.6.0"
    assert f"== {versioned['name']} 5.6.0 ({entry['license']}) ==" in acknowledgements
    assert marker not in acknowledgements
    assert collector.check_existing(resources / "Licenses", components) == []


@pytest.mark.parametrize(
    ("name", "module", "attributes", "version"),
    [
        ("OpenSSL", "ssl", {"OPENSSL_VERSION": "OpenSSL 3.5.8 25 Aug 2026"}, "3.5.8"),
        ("Expat", "pyexpat", {"EXPAT_VERSION": "expat_2.8.5", "version_info": (2, 8, 5)}, "2.8.5"),
    ],
)
def test_wp701_finding_e_version_probes_print_bare_versions(
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
    name: str,
    module: str,
    attributes: dict,
    version: str,
) -> None:
    """The banners are those of the 1.0.0 (4) runtime, whose OpenSSL heading read "OpenSSL OpenSSL 3.5.8 …"."""
    entry = next(
        item for item in json.loads((ROOT / "App/Licenses/components.json").read_text()) if item["name"] == name
    )
    monkeypatch.setitem(sys.modules, module, types.SimpleNamespace(**attributes))
    exec(entry["detect"]["python"], {})
    assert capsys.readouterr().out.strip() == version


def test_wp701_finding_e_acknowledgement_headings_name_each_component_once(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Every committed probe runs in this interpreter; a banner as the version repeats the name in its heading."""
    spec = importlib.util.spec_from_file_location("collector", ROOT / "tools/release/collect_licenses.py")
    collector = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(collector)
    entries = json.loads((ROOT / "App/Licenses/components.json").read_text())
    repo, app = _licence_bundle(tmp_path, entries)
    resources = app / "Contents/Resources"
    markers = [entry["detect"]["bytes"].encode("ascii") for entry in entries if "bytes" in entry.get("detect", {})]
    (resources / "fpengine/lib/libpython3.12.dylib").write_bytes(b"\0".join(markers))
    monkeypatch.setattr(collector.importlib.metadata, "distributions", lambda: [])
    monkeypatch.setattr(collector, "REQUIRED", {"Font Playground", "CPython"})
    monkeypatch.setattr(sys, "argv", ["collect_licenses.py", "--app", str(app), "--repo", str(repo)])

    assert collector.main() == 0
    components = json.loads((resources / "Licenses/index.json").read_text())["components"]
    assert {item["name"] for item in components} >= {entry["name"] for entry in entries}
    acknowledgements = (resources / "Acknowledgements.txt").read_text()
    for item in components:
        assert item["name"].split()[0].lower() not in item["version"].lower(), item
        title = " ".join(value for value in (item["name"], item["version"]) if value)
        assert f"\n== {title} ({item['license']}) ==\n" in acknowledgements
    assert "OpenSSL OpenSSL" not in acknowledgements


def test_tooling_1_adhoc_dispatch_never_creates_a_release() -> None:
    workflow = (ROOT / ".github/workflows/release.yml").read_text()
    release_step = workflow.split("- name: Draft GitHub release\n", 1)[1].split("- name:", 1)[0]
    assert "if: github.event_name == 'push' && startsWith(github.ref, 'refs/tags/')" in release_step
    assert 'if [[ "$GITHUB_EVENT_NAME" == push && "$GITHUB_REF_TYPE" == tag ]]; then' in workflow


def test_release_checks_its_secrets_before_building() -> None:
    """A signed run with a missing secret stops before the test suite and names every missing one."""
    workflow = (ROOT / ".github/workflows/release.yml").read_text()
    check = workflow.split("- name: Check release secrets\n", 1)[1].split("- name:", 1)[0]
    assert workflow.index("- name: Check release secrets\n") < workflow.index("run: make setup")
    adhoc = "github.event_name == 'pull_request' || (github.event_name == 'workflow_dispatch' && inputs.adhoc)"
    assert f"if: ${{{{ !({adhoc}) }}}}" in check
    names = set(re.findall(r"secrets\.([A-Z0-9_]+)", workflow))
    assert set(re.findall(r"secrets\.([A-Z0-9_]+)", check)) == names
    assert all(name in check.split("run: |", 1)[1] for name in names)
    release_step = workflow.split("- name: Draft GitHub release\n", 1)[1].split("- name:", 1)[0]
    assert '--notes-file "docs/release/notes/$GITHUB_REF_NAME.md"' in release_step and "--verify-tag" in release_step


def test_release_notes_exist_for_the_current_version() -> None:
    """The draft release uses curated notes, in English and Chinese, rather than a list of WP pull requests."""
    version = re.search(r"^MARKETING_VERSION\s*=\s*(\S+)", (ROOT / "App/Version.xcconfig").read_text(), re.M)[1]
    notes = (ROOT / f"docs/release/notes/v{version}.md").read_text()
    assert f"FontPlayground-{version}-arm64.dmg" in notes and "简体中文" in notes
    assert "https://afdian.com/a/kciceblue" in notes and "https://buymeacoffee.com/kciceblue" in notes


def test_workflow_actions_are_pinned_to_commits() -> None:
    for name in ("ci.yml", "release.yml", "codex-review.yml"):
        actions = re.findall(r"uses:\s+([^\s]+)", (ROOT / ".github/workflows" / name).read_text())
        assert actions and all(re.fullmatch(r"[^@]+@[a-f0-9]{40}", action) for action in actions), name


def test_release_checksum_verifies_next_to_a_download(tmp_path: Path) -> None:
    """The .sha256 names the DMG without dist/, so `shasum -c` works in the folder a browser saved both to."""
    line = next(line for line in (ROOT / "scripts/release.sh").read_text().splitlines() if "shasum -a 256" in line)
    dmg = "FontPlayground-1.0.0-arm64.dmg"
    (tmp_path / "dist").mkdir()
    (tmp_path / "dist" / dmg).write_bytes(b"not really a disk image")
    subprocess.run(["bash", "-c", f"set -euo pipefail; DMG=dist/{dmg}; {line}"], cwd=tmp_path, check=True)
    downloads = tmp_path / "Downloads"
    downloads.mkdir()
    shutil.copy2(tmp_path / "dist" / dmg, downloads / dmg)
    shutil.copy2(tmp_path / "dist" / f"{dmg}.sha256.tmp", downloads / f"{dmg}.sha256")
    assert (downloads / f"{dmg}.sha256").read_text().split()[1] == dmg
    subprocess.run(["shasum", "-a", "256", "-c", f"{dmg}.sha256"], cwd=downloads, check=True, capture_output=True)


@pytest.mark.parametrize("signature", ["developer-id", "development", "adhoc", "no-timestamp"])
def test_tooling_1_distribution_reads_authority_without_relaxing_checks(tmp_path: Path, signature: str) -> None:
    """Run the real checker with codesign's authority hidden at its default verbosity."""
    repo = tmp_path / "repo"
    (repo / "scripts").mkdir(parents=True)
    (repo / "App").mkdir()
    for name in ("check-bundle.sh", "check-sdk.sh"):
        shutil.copy2(ROOT / "scripts" / name, repo / "scripts" / name)
    shutil.copy2(ROOT / "App/Version.xcconfig", repo / "App/Version.xcconfig")
    shutil.copy2(ROOT / "LICENSE", repo / "LICENSE")
    app = tmp_path / "Font Playground.app"
    contents = app / "Contents"
    (contents / "MacOS").mkdir(parents=True)
    (contents / "Resources").mkdir()
    for name in ("MacOS/Font Playground", "Resources/Assets.car", "Resources/AppIcon.icns"):
        (contents / name).touch()
    # CRIT-10 / WP-508: the localisations check needs both guides, both string tables and the Chinese name.
    ui = "Resources/FontPlaygroundMacKit_FPAppUI.bundle/Contents/Resources"
    for name in ("en.lproj/UserGuide.html", "zh-Hans.lproj/UserGuide.html"):
        (contents / "Resources" / name).parent.mkdir(parents=True, exist_ok=True)
        (contents / "Resources" / name).touch()
    for language in ("en", "zh-Hans"):
        (contents / ui / f"{language}.lproj").mkdir(parents=True)
        (contents / ui / f"{language}.lproj/Localizable.strings").touch()
    (contents / "Resources/zh-Hans.lproj/InfoPlist.strings").write_bytes(
        plistlib.dumps({"CFBundleDisplayName": "字体混搭", "FPDonateURL": "https://afdian.com/a/kciceblue"})
    )
    info = plistlib.loads((ROOT / "App/Info.plist").read_bytes())
    info.update(
        CFBundleIdentifier="io.github.kciceblue.fontplayground",
        CFBundleExecutable="Font Playground",
        CFBundleShortVersionString=re.search(
            r"^MARKETING_VERSION\s*=\s*(\S+)", (repo / "App/Version.xcconfig").read_text(), re.M
        )[1],
        CFBundleVersion="3",
        LSMinimumSystemVersion="14.0",
    )
    (contents / "Info.plist").write_bytes(plistlib.dumps(info))
    fake_bin = tmp_path / "bin"
    fake_bin.mkdir()
    (fake_bin / "python3").symlink_to(sys.executable)
    tool = fake_bin / "apple-tool"
    tool.write_text(
        """#!/usr/bin/env python3
import json, os, pathlib, sys
name, args = pathlib.Path(sys.argv[0]).name, sys.argv[1:]
if name == 'xcrun' and args[:2] == ['assetutil', '--info']:
    print(json.dumps([{'Name': 'AppIcon'}]))
elif name == 'lipo' and args[0] == '-archs':
    print('arm64')
elif name == 'file' and args[0] == '-b':
    print('Mach-O 64-bit executable arm64' if '/MacOS/' in args[-1] else 'data')
elif name == 'otool' and args[0] == '-l':
    print('cmd LC_BUILD_VERSION\\n  sdk 27.0')
elif name == 'codesign':
    if args[:4] == ['-d', '--entitlements', '-', '--xml'] or args[:3] == ['--verify', '--deep', '--strict']:
        pass
    elif args[0] == '-dv':
        signature = os.environ['FP_TEST_SIGNATURE']
        print('CodeDirectory v=20500 flags=0x10000(runtime)', file=sys.stderr)
        if '--verbose=4' in args:
            if signature == 'development':
                print('Authority=Apple Development: Test Signer (TESTTEAM)', file=sys.stderr)
            elif signature == 'adhoc':
                print('Signature=adhoc', file=sys.stderr)
            else:
                print('Authority=Developer ID Application: Test Signer (TESTTEAM)', file=sys.stderr)
        if signature != 'no-timestamp':
            print('Timestamp=Sep 30, 2026 at 12:00:00 PM', file=sys.stderr)
        print('TeamIdentifier=TESTTEAM', file=sys.stderr)
    else:
        raise SystemExit('unexpected codesign arguments: ' + repr(args))
else:
    raise SystemExit('unexpected tool: ' + name + ' ' + repr(args))
"""
    )
    tool.chmod(0o755)
    for name in ("xcrun", "lipo", "file", "otool", "codesign"):
        (fake_bin / name).symlink_to(tool)
    (repo / "Makefile").write_text(
        'check:\n\t@/bin/bash scripts/check-bundle.sh "$$FP_TEST_APP" --distribution\n'
        'terse:\n\t@codesign -dv "$$FP_TEST_APP"\n'
        'verbose:\n\t@codesign -dv --verbose=4 "$$FP_TEST_APP"\n'
    )
    environment = dict(
        os.environ,
        PATH=f"{fake_bin}:/usr/bin:/bin",
        FP_TEST_APP=str(app),
        FP_TEST_SIGNATURE=signature,
    )
    make = shutil.which("make")
    assert make is not None

    def invoke(target: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [make, "-C", str(repo), target], env=environment, capture_output=True, text=True, check=False
        )

    terse, verbose = invoke("terse"), invoke("verbose")
    assert terse.returncode == verbose.returncode == 0
    assert "Authority=" not in terse.stderr
    if signature == "developer-id":
        assert "Timestamp=" in terse.stderr
        assert "Authority=Developer ID Application:" in verbose.stderr
    result = invoke("check")
    if signature == "developer-id":
        assert result.returncode == 0, result.stdout + result.stderr
        assert "check-bundle: Developer ID and timestamp OK" in result.stdout
    else:
        assert result.returncode != 0
        assert "check-bundle: Developer ID and timestamp FAIL" in result.stdout
        assert "check-bundle: 1 problems" in result.stdout


def _step_script(workflow: str, name: str) -> str:
    """The `run: |` body of the workflow step called `name`, dedented."""
    step = workflow.split(f"- name: {name}\n", 1)[1].split("\n      - ", 1)[0]
    lines = step.split("run: |\n", 1)[1].splitlines()
    indent = len(lines[0]) - len(lines[0].lstrip())
    return "\n".join(line[indent:] for line in lines) + "\n"


@pytest.mark.parametrize("before", ["", '    "/Users/ci/Library/Keychains/login.keychain-db"\n'])
def test_release_keychain_steps_handle_an_empty_search_list(tmp_path: Path, before: str) -> None:
    """The v1.0.0 tag run failed here: a fleet job's fresh HOME has no user keychains, and macOS's bash 3.2 calls an
    empty "${existing[@]}" unbound under `set -u`. Both steps must restore exactly the list they found."""
    workflow = (ROOT / ".github/workflows/release.yml").read_text()
    fake_bin, temp, log = tmp_path / "bin", tmp_path / "runner", tmp_path / "security.log"
    fake_bin.mkdir()
    temp.mkdir()
    (fake_bin / "security").write_text(
        f'#!/bin/bash\n[[ "$*" == "list-keychains -d user" ]] && printf %s "$BEFORE"\necho "$*" >> "{log}"\n'
    )
    (fake_bin / "openssl").write_text("#!/bin/bash\necho not-a-real-password\n")
    for tool in fake_bin.iterdir():
        tool.chmod(0o755)
    env = {"PATH": f"{fake_bin}:/usr/bin:/bin", "RUNNER_TEMP": str(temp), "BEFORE": before}
    secrets = ["MACOS_DEVELOPER_ID_P12_BASE64", "MACOS_DEVELOPER_ID_P12_PASSWORD", "NOTARY_API_KEY_P8_BASE64"]
    env |= dict.fromkeys(secrets, "")
    found = " /Users/ci/Library/Keychains/login.keychain-db" if before else ""
    for name in ("Import Developer ID certificate and notary key", "Remove release credentials"):
        result = subprocess.run(
            ["/bin/bash", "-e", "-c", _step_script(workflow, name)], env=env, capture_output=True, text=True
        )
        assert result.returncode == 0, (name, result.stderr)
    calls = log.read_text().splitlines()
    assert f"list-keychains -d user -s {temp}/release.keychain-db{found}" in calls
    assert calls[-1] == f"list-keychains -d user -s{found}"


def test_release_signs_from_its_imported_keychain() -> None:
    """The second v1.0.0 tag run imported the identity, then codesign found none by name: a fleet job's fresh HOME
    keeps no keychain search list. The signing step names the imported keychain instead."""
    workflow = (ROOT / ".github/workflows/release.yml").read_text()
    imported = re.search(
        r'^keychain="([^"]+)"$', _step_script(workflow, "Import Developer ID certificate and notary key"), re.M
    )
    assert imported and f'export CODESIGN_KEYCHAIN="{imported[1]}"' in _step_script(workflow, "Build notarized release")
    assert 'keychain=(--keychain "$CODESIGN_KEYCHAIN")' in (ROOT / "scripts/codesign-retry.sh").read_text()
    # Public build numbers stay above the private repository's 1.0.0 candidates, builds 1-4.
    assert 'BUILD_NUMBER_OFFSET: "100"' in workflow
    assert workflow.count('--build-number "$((GITHUB_RUN_NUMBER + BUILD_NUMBER_OFFSET))"') == 2
    assert '--build-number "$GITHUB_RUN_NUMBER"' not in workflow


def test_scripts_have_no_bare_bracket_checks() -> None:
    """macOS's bash 3.2 doesn't stop for a failed `[[ ]]` under `set -e`, so a check that is a whole statement passes
    silently. release.sh's Gatekeeper and DMG checks were like that, and so were the shell tests' own assertions;
    every check must exit by itself."""
    bare = re.compile(r"^\s*\[\[ .* \]\]\s*$")
    scripts = [*(ROOT / "scripts").glob("*.sh"), *(ROOT / "scripts/tests").glob("*.sh")]
    offenders = [
        f"{path.relative_to(ROOT)}:{number}"
        for path in sorted(scripts)
        for number, line in enumerate(path.read_text().splitlines(), 1)
        if bare.match(line)
    ]
    assert not offenders
