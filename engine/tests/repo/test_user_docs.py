"""Keep shipped instructions in step with native commands and bundled dependencies."""

import json
import re
from html.parser import HTMLParser
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
GUIDE = ROOT / "App/Resources/en.lproj/UserGuide.html"
GUIDE_ZH = ROOT / "App/Resources/zh-Hans.lproj/UserGuide.html"
SYSTEM_TITLES = {"Settings…", "About Font Playground", "Quit Font Playground", "Hide Font Playground"}
HEADINGS = [
    "Font Playground",
    "Requirements",
    "Install",
    "Using Font Playground",
    "What the result contains",
    "Font licences",
    "Coming from the Windows version",
    "Not in this version",
    "Privacy",
    "Uninstall",
    "Support Font Playground",
    "Acknowledgements and licence",
    "Disclaimer",
    "Development",
]


def catalogs() -> list[Path]:
    return [p for p in ROOT.rglob("*.xcstrings") if not {"build", ".build", "reference"} & set(p.parts)]


def english_values(path: Path) -> list[str]:
    return [
        v.get("localizations", {}).get("en", {}).get("stringUnit", {}).get("value", k)
        for k, v in json.loads(path.read_text())["strings"].items()
    ]


def section(title: str) -> str:
    text = (ROOT / "README.md").read_text().split(f"## {title}\n", 1)[1]
    return text.split("\n## ", 1)[0]


def commands() -> set[str]:
    return {s.replace("...", "…") for s in re.findall(r"\*\*(.+?)\*\*", section("Using Font Playground"))}


def test_ui_12_no_windows_wording_in_user_docs() -> None:
    forbidden = [
        "Windows already has",
        "admin rights",
        "Ctrl+",
        "Ctrl-",
        "Enter uses it",
        "Open settings folder",
        "Show file",
        ".venv\\",
        "run.bat",
        "Explorer",
    ]
    texts = [(ROOT / "README.md").read_text(), GUIDE.read_text()]
    texts += [value for path in catalogs() for value in english_values(path)]
    for text in texts:
        for phrase in forbidden:
            assert phrase not in text
    readme = (ROOT / "README.md").read_text()
    remaining = re.sub(r"## Coming from the Windows version\n.*?(?=\n## )", "", readme, flags=re.S)
    assert "Windows" not in remaining
    assert re.findall(r"^#{1,2} (.+)$", readme, re.M) == HEADINGS
    assert section("Requirements").strip() == "A Mac with Apple silicon and macOS 14 Sonoma or later."
    assert "Status: planning" not in readme


def test_ui_12_readme_commands_exist_in_the_app() -> None:
    paths = [p for p in catalogs() if p.name == "Localizable.xcstrings"]
    assert paths, "String Catalog must exist; this test must not skip."
    titles = SYSTEM_TITLES | {s.replace("...", "…") for p in paths for s in english_values(p)}
    assert commands() and commands() <= titles


class StrongText(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.values: list[str] = []
        self.current: str | None = None

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag == "strong":
            self.current = ""
        assert tag != "script"
        for key, value in attrs:
            assert key not in {"src", "href"} or not value or value.startswith("#")

    def handle_data(self, data: str) -> None:
        if self.current is not None:
            self.current += data

    def handle_endtag(self, tag: str) -> None:
        if tag == "strong":
            self.values.append(self.current)
            self.current = None


def test_user_guide_matches_readme_commands() -> None:
    guide = GUIDE.read_text()
    parser = StrongText()
    parser.feed(guide)
    assert set(parser.values) == commands()
    assert "font: -apple-system-body" in guide and "prefers-color-scheme: dark" in guide
    assert not any(value in guide for value in ["http://", "https://", "<script"])
    assert re.findall(r"<h2>(.*?)</h2>", guide) == HEADINGS[2:10]


def test_crit_2_migration_note_says_do_not_copy_the_settings_folder() -> None:
    note = (ROOT / "docs/user/migrating-from-windows.md").read_text()
    for required in [
        "Don't copy the whole",
        r"%LOCALAPPDATA%\FontPlayground",
        "settings.json",
        "catalog.json",
        "forge_last.json",
        "~/Library/Application Support/FontPlayground/forge_last.json",
    ]:
        assert required in note
    assert "Imported your last recipe and settings from the earlier version of Font Playground." in note
    assert "before" in note.lower() and "first" in note and "once" in note


def test_crit_3_windows_font_licence_warning() -> None:
    note = (ROOT / "docs/user/migrating-from-windows.md").read_text()
    assert any(r"C:\Windows\Fonts" in p and "licen" in p and "Office" in p for p in note.split("\n\n"))


def test_tooling_11_static_licence_texts_exist() -> None:
    folder = ROOT / "App/Licenses"
    entries = json.loads((folder / "components.json").read_text())
    required = {
        "python-build-standalone (build scripts)",
        "OpenSSL",
        "SQLite",
        "mpdecimal (libmpdec)",
        "Expat",
        "XZ Utils (liblzma)",
        "bzip2",
        "libffi",
        "libuuid (util-linux)",
        "HACL*",
        "Unicode Character Database (in unicodedata2)",
        "otf2ttf snippet (cff_to_glyf)",
    }
    assert required <= {e["name"] for e in entries}
    assert len(entries) == len({e["name"] for e in entries})
    for entry in entries:
        assert re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9.+-]*(?: (?:AND|OR) [A-Za-z0-9.+-]+)*", entry["license"])
        assert entry["files"]
        for file in entry["files"]:
            path = folder / file
            assert path.resolve().is_relative_to(folder.resolve())
            assert path.is_file() and path.read_bytes().strip()


def test_crit_10_chinese_user_guide() -> None:
    """The Chinese guide mirrors the English one and names commands exactly as the zh-Hans catalog does."""
    assert not (ROOT / "App/Resources/UserGuide.html").exists(), "a top-level guide would hide the localized ones"
    guide, english = GUIDE_ZH.read_text(), GUIDE.read_text()
    assert '<html lang="zh-Hans">' in guide
    assert "font: -apple-system-body" in guide and "prefers-color-scheme: dark" in guide
    assert not any(value in guide for value in ["http://", "https://", "<script"])
    for tag in ["<section>", "<h2>", "<li>"]:
        assert guide.count(tag) == english.count(tag), tag
    strings = json.loads(
        (ROOT / "Packages/FontPlaygroundMacKit/Sources/FPAppUI/Resources/Localizable.xcstrings").read_text()
    )["strings"]
    parser, parser_zh = StrongText(), StrongText()
    parser.feed(english)
    parser_zh.feed(guide)
    assert len(parser_zh.values) == len(parser.values)
    for command in parser.values:
        if command in strings:
            assert strings[command]["localizations"]["zh-Hans"]["stringUnit"]["value"] in parser_zh.values, command
    for phrase in ["资源管理器", "右键", "管理员权限", "Finder", "Font Book"]:
        assert phrase not in guide


def test_chinese_readme_mirrors_readme() -> None:
    """README.zh-Hans.md keeps the English sections and names commands exactly as the zh-Hans catalog does."""
    readme, chinese = (ROOT / "README.md").read_text(), (ROOT / "README.zh-Hans.md").read_text()
    assert "[简体中文](README.zh-Hans.md)" in readme and "[English](README.md)" in chinese
    for pattern in [r"^## ", r"^\d+\. "]:
        assert len(re.findall(pattern, chinese, re.M)) == len(re.findall(pattern, readme, re.M)), pattern
    strings = json.loads(
        (ROOT / "Packages/FontPlaygroundMacKit/Sources/FPAppUI/Resources/Localizable.xcstrings").read_text()
    )["strings"]
    system = {"Settings…": "设置…"}
    bold = re.findall(r"\*\*(.+?)\*\*", chinese)
    assert len(bold) == len(commands())
    for command in commands():
        expected = strings[command]["localizations"]["zh-Hans"]["stringUnit"]["value"] if command in strings else None
        assert (expected or system[command]) in bold, command
    assert "您" not in chinese  # the glossary addresses the user as 你
