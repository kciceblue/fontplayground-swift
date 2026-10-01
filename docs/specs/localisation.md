# Localisation: Simplified Chinese and the language setting

> Scope: WP-508 · Env: macos · Architecture refs: docs/architecture.md §8 (cross-cutting rules: user-visible strings) · Related specs: ui-shell.md §S8 (String Catalog, lint), §S6 (menus), WP-507; foundation-release.md WP-602 (user guide), §S6 (self-test) · Decisions: D28–D32

## Context

### Where v1.0 leaves off

- Every FPAppUI string is in `Packages/FontPlaygroundMacKit/Sources/FPAppUI/Resources/Localizable.xcstrings` (WP-507): 355 keys, about 1,800 English words, `en` only. The English text is the key, and the string id is the comment (ui-shell.md §S8). Lint rules L1, L2 and L9 keep it that way.
- FPCore values reach the UI through `ModelText`, which is catalog-backed. Engine data is shown as it comes (ui-shell.md §S8).
- The app target has `CFBundleDevelopmentRegion = en` and `CFBundleAllowMixedLocalizations = true` (AC-501-2). `App/Resources/InfoPlist.xcstrings` has 7 `en` entries.
- The user guide is one file, `App/Resources/UserGuide.html` (WP-602). `helpURL` finds it with `bundle.url(forResource: "UserGuide", withExtension: "html")`.
- CRIT-10 is closed in part. The rest was backlog B-8.

### Maintainer decisions (2026-09-30)

- Ship Simplified Chinese in **v1.1**, after v1.0.0 (WP-701).
- Scope: **the app and the user guide**. Engine data stays English (D32).
- Keep English for terms that read oddly when translated (§L3).
- The Chinese name should be one the maintainer would try from the App Store; "字体合并 or something similar". This spec picks **字体混搭** (D28).

### Verified behaviour

These facts were measured on macOS 27.0, Xcode 27.0 and Swift 6.4 with a probe package: a library with an `en` + `zh-Hans` `.xcstrings` resource, a Swift Testing target and an executable. The design depends on them.

| # | Fact | Consequence |
|---|---|---|
| F1 | `String(localized:bundle:locale:comment:)` ignores `locale` when it chooses the translation. A `LocalizedStringResource` whose `locale` is set does choose it when passed to `String(localized:)` | Tests read Chinese values through `LocalizedStringResource` (§L7). Production code keeps `String(localized:…, bundle: .module)` |
| F2 | Without `CFBundleAllowMixedLocalizations` in the main bundle, a package resource bundle follows the main bundle's language. Under `-AppleLanguages "(zh-Hans)"`, an English-only tool still got `en` | `swift test` runs in an English-only host, so it resolves FPAppUI strings in English on any Mac. The English assertions of the existing suites stay valid. A guard test pins this (AC-508-7) |
| F3 | With `CFBundleAllowMixedLocalizations = true` (the app has it), the package bundle follows the user's languages even when the main bundle has no `zh-Hans` | FPAppUI's text would turn Chinese without the app bundle's help. But the app name, the Info.plist strings, the menu items AppKit builds from the app name, and System Settings' per-app language list all need the main bundle to declare `zh-Hans` (D3) |
| F4 | A translation may reorder placeholders. The key `%@ can't shape %@` with the `zh-Hans` value `%2$@ 无法由 %1$@ 塑形` formats correctly | Word order needs no key changes (§L5) |
| F5 | `Bundle.preferredLocalizations(from: ["en", "zh-Hans"], forPreferences:)` gives `zh-Hans` for `[zh-Hans-CN, en]`, `[zh-CN]`, `[zh-SG]`, `[ja-JP, zh-Hans]` and `[zh-Hant-TW, zh-Hans-CN]`. It gives `en` for `[zh-Hant-TW]`, `[zh-HK]`, `[ja-JP]`, `[en-JP]` and `[en-GB, zh-Hans]` | Traditional Chinese systems get English (D31). The resolver in D5 is this call |
| F7 | In an **interpolated** `String(localized:)` literal, a literal `%` is looked up as `%%` (`"\(v) %"` has the runtime key `%lld %%`). A plain literal keeps its single `%`. Two v1.0 catalog keys had a single `%` (`%lld %` and `%@: scale %@% is too large…`), so they never matched: English showed only through the fallback, and Chinese would never have appeared. WP-507's key check missed this because its normalisation collapsed both forms | WP-508 renames the two keys to `%%` and models the escaping in `LocalizationSource.runtimeKey` (AC-508-6) |
| F6 | `-AppleLanguages "(zh-Hans)"` on the command line selects the language at launch (measured). The `AppleLanguages` key in the app's own defaults domain does the same; it is what System Settings › General › Language & Region › Applications writes (documented behaviour; AC-508-M2 checks it) | The language setting writes that key (D5). Manual QA can launch in Chinese without changing the system language |

---

## Shared definitions

### L1. Languages

- `en` is the source (development) language. `zh-Hans` is the only translation. `InterfaceLanguage` (D5) lists what the app offers.
- Every entry in these three catalogs has a `zh-Hans` string unit with state `translated`:
  - FPAppUI's `Localizable.xcstrings`;
  - `App/Resources/InfoPlist.xcstrings`;
  - `App/Resources/Localizable.xcstrings`.

### L2. Keys

- The English text stays the key (ui-shell.md §S8).
- **Context keys** are the one exception. When one English word needs two different translations, the second meaning gets a dotted key with the English as `defaultValue`:

  ```swift
  String(localized: "weight.light", defaultValue: "Light", bundle: .module, comment: "shell.weightLight")
  ```

  The catalog entry `weight.light` has `en` = "Light".

| Context key | English | Meaning | Its twin |
|---|---|---|---|
| `weight.light` | Light | weight 300 in the weight menu (kept English, §L3) | "Light", the Appearance choice (浅色) |

- A new context key needs a row in this table and in AC-508-5.
- Some English keys are used under more than one string id. Such a key must mean the same thing everywhere it is used. AC-508-5 holds the reviewed list.

### L3. Glossary

**Table 1: macOS and app commands (exact).** These follow Apple's Simplified Chinese. AC-508-3 checks each value exactly.

| Key (en) | zh-Hans |
|---|---|
| Show in Finder | 在访达中显示 |
| Show Settings Folder in Finder | 在访达中显示设置文件夹 |
| Open in Font Book | 在字体册中打开 |
| Get More Fonts… | 获取更多字体… |
| Save a Copy… | 存储副本… |
| Install | 安装 |
| Update Installed Font | 更新已安装的字体 |
| Replace | 替换 |
| Remove | 移除 |
| Cancel | 取消 |
| Quit | 退出 |
| Keep Building | 继续生成 |
| Undo | 撤销 |
| Rescan Fonts | 重新扫描字体 |
| Add Font Folder… | 添加字体文件夹… |
| Add Font Folder | 添加字体文件夹 |
| Start Over | 重新开始 |
| Show Advanced | 显示高级选项 |
| Hide Advanced | 隐藏高级选项 |
| Appearance | 外观 |
| System | 跟随系统 |
| Light | 浅色 |
| Dark | 深色 |
| Preview | 预览 |
| Sample Text | 示例文本 |
| Colour by Font | 按字体着色 |

Finder, Font Book and Trash are always 访达, 字体册 and 废纸篓 in Chinese text.

**Table 2: app terms (guidance).** The translator follows these; the tests don't check them exactly.

| English | zh-Hans | Note |
|---|---|---|
| Font Playground | 字体混搭 | D28; in every value that names the app |
| recipe | 方案 | the list of fonts the user combines |
| main font | 主字体 | |
| glyph | 字形 | |
| script (writing system) | 文字 | for example 拉丁文字; language names follow `ModelText.languageLabel` |
| build (a font) | 生成 | "Building your font" → 正在生成你的字体 |
| licence | 许可 | |
| missing characters | 缺失字符 | |
| As is (weight) | 保持原样 | |
| you, your | 你, 你的 | not 您 |

**Table 3: kept in English.** AC-508-4 checks these.

- **Weight and style names:** Light (`weight.light`), Regular, Medium, Semibold, Bold, Heavy, and the "Regular" style-name placeholder. These are what the forged font's style name and Font Book show for Latin fonts. Chinese names vary by foundry (常规体, 标准, 中黑…). "Heavy" or "Black" would become 黑, which Chinese readers take for 黑体 (Heiti, the sans-serif category).
- **Data:** font family, style and PostScript names come from the fonts and are never translated.
- **Format and technology names:** OpenType, TrueType, PostScript, AAT, Unicode, cmap, GPOS, kern, morx, fsType, fontTools, Python, fpengine, `.fontrecipe`, `.ttf`.
- **Key names and modifier symbols:** Return, Esc, Tab and fn, written as in Apple's Chinese guides ("按 Return 键"), and ⌘ ⌥ ⇧ ⌃.

### L4. Chinese style

- Use full-width punctuation inside Chinese sentences: ，。：；？！（）.
- Keep the curly quotes “ ”; they are also the Chinese ones.
- Keep the single-character ellipsis … after command names (存储副本…).
- Put one space between Chinese and Latin letters or digits ("PingFang SC 无法绘制 12 个字符"), but none next to full-width punctuation. This is Apple's Simplified Chinese convention.
- Enumerations use 、 (the list separator, §L6), and "and" becomes 和.
- Address the user as 你. Keep sentences short and plain, like the English.
- Upper-case role titles (ADDS NOTHING) become plain Chinese; Chinese has no case.
- The language setting shows each language name in its own language (English, 简体中文), whatever the UI language.

### L5. Placeholders

- A `zh-Hans` value has the same placeholders as its `en` value: the same count and the same types (`%@`, `%lld`, …).
- It may reorder them with positional specifiers (`%1$@`, F4). A value that reorders must use positions for every placeholder, numbered 1…n with each number used once.
- Code must not concatenate translated fragments into a sentence. Add a whole-sentence key instead.

### L6. List separators

- `ModelText.listSeparator` is `String(localized: ", ", bundle: .module, comment: "model.listSeparator")`, with zh-Hans "、".
- The existing joiner keys " and " (`ModelText.labelJoiner`) and " & " (role titles) both get zh-Hans "和".
- Every join of a user-visible enumeration uses `listSeparator`.
- `ListFormatter` is not used: its English output ("A, B, and C") would break the English parity that AC-507-9 checks ("A, B and C").

### L7. Reading Chinese in tests

- FPAppUI adds an internal `enum LocalizationSupport { static var bundleURL: URL { Bundle.module.bundleURL } }`. Tests can't name FPAppUI's `Bundle.module` unambiguously.
- Tests that need a resolved Chinese value build `LocalizedStringResource(String.LocalizationValue(key), bundle: .atURL(LocalizationSupport.bundleURL))`, set its `locale` to `Locale(identifier: "zh-Hans")`, and call `String(localized:)` (F1).
- Tests that check catalog content read the `.xcstrings` JSON, as `LocalizationSource` already does.

---

## WP-508: Simplified Chinese localisation and the language setting

**Goal:** A Chinese-speaking user can run Font Playground entirely in Simplified Chinese, including its name, menus, Settings and user guide, and can switch between English and Chinese in Settings.
**Depends on:** WP-507, WP-602; scheduled after WP-701 (release v1.1) · **Env:** macos · **Size:** L · **Closes findings:** CRIT-10 (the Simplified Chinese part; Traditional Chinese, Japanese and Korean stay in B-8)

### Scope

- **In:**
  - `zh-Hans` for every entry of the three catalogs (§L1), following §L3–§L5;
  - the `weight.light` context key (§L2);
  - list separators through the catalog (§L6);
  - the app bundle declares `zh-Hans`: the Info.plist keys, `InfoPlist.xcstrings` and the Chinese name (D28);
  - Settings › Language with Quit and Reopen (D5);
  - the user guide in `en.lproj` and `zh-Hans.lproj`;
  - catalog, glossary, placeholder and language-flow tests, and the bundle check;
  - the doc updates listed under Touched paths.
- **Out:**
  - **Engine data stays English (D32; backlog B-14).** This covers `ForgeReport.warnings`, `licenceNotes[].text`, `MaterialReport.warnings`, `HelperFailure.message`/`detail`, `FaceRecord.unsupportedReason`, and the `InstallError` text shown after a catalog prefix such as "Couldn't install the font: ".
  - FPCore's `EnglishText` and FPMacServices' `englishText` stay unchanged. ModelTextTests keeps comparing against them.
  - Traditional Chinese, Japanese and Korean (B-8).
  - Showing a family's Chinese name first in the picker (B-13).
  - `Acknowledgements.txt` and licence texts stay English, because licence texts must not be paraphrased. `README.md` has a Chinese translation, `README.zh-Hans.md` (added after v1.1), which defers to the English README and `LICENSE`.
  - These names stay as they are: the bundle file name (`Font Playground.app`), the DMG name, the bundle identifier, and the forged-font marker "Forged with Font Playground" (font metadata, WP-109).
  - Switching language without reopening.

### Touched paths

- `Packages/FontPlaygroundMacKit/Sources/FPAppUI/Resources/Localizable.xcstrings` (edit: `zh-Hans`, `weight.light`, the D5 strings, ", ")
- `…/FPAppUI/Shared/ShellText.swift` (edit: `weightLight`, the D5 strings, `quoted`), `Shared/ModelText.swift`, `Shared/ReportText.swift`, `Editing/Preview/PreviewText.swift`, `Editing/Picker/PickerText.swift` (edit: separators), `Shared/LocalizationSupport.swift` (new, §L7)
- `…/FPAppUI/Model/InterfaceLanguage.swift` (new), `Model/SystemActions.swift`, `Model/AppModel.swift`, `Model/AppModel+Actions.swift`, `Model/Launch.swift` (edit: separators, `prepareForTermination`), `App/QuitCoordinator.swift`, `App/FPAppDelegate.swift`, `Views/Settings/SettingsView.swift` (edit)
- `…/Tests/FPAppUITests/LocalizationCatalogTests.swift`, `SourceLintTests.swift` (L10), `AppBundleTests.swift`, `QuitCoordinatorTests.swift`, `Support/ShellFakes.swift` (edit); `InterfaceLanguageTests.swift` (new)
- `App/Info.plist`, `App/Resources/InfoPlist.xcstrings`, `App/Resources/Localizable.xcstrings` (edit)
- `App/Resources/UserGuide.html` → `App/Resources/en.lproj/UserGuide.html` (move, plus one sentence on Settings ▸ Language), `App/Resources/zh-Hans.lproj/UserGuide.html` (new), `README.md` (edit: the same sentence)
- `engine/tests/repo/test_user_docs.py` (edit)
- `scripts/check-bundle.sh` (edit), `scripts/tests/test_crit_10_bundle_localisations.sh` (new)
- `docs/specs/foundation-release.md` (edit: the guide's path in the bundle layout, in WP-602's touched paths and in AC-602-7, each marked "moved to `en.lproj` by WP-508"), `docs/specs/traceability.md` (edit: the CRIT-10 row), `docs/plan.md` (edit: status, if the maintainer asks)

### Design

**D1. Translations.**

- Fill in `zh-Hans` for every entry in the three catalogs, following §L3–§L5.
- Translate from the call site, not from the key alone. The `comment` holds the string id; grep for it. For example, "Size" is both the preview size and a font's scale, and both are 大小.
- Every value that names the app uses 字体混搭 (D28).
- Set each `zh-Hans` unit's state to `translated`.
- Keep each file's current JSON formatting, so the diff shows only additions.
- A native speaker (the maintainer) reviews every value before merge (AC-508-M3).

**D2. The context key and the separators.**

- `ShellText.weightLight` becomes `String(localized: "weight.light", defaultValue: "Light", bundle: .module, comment: "shell.weightLight")`.
  - The catalog gains `weight.light`, with `en` "Light" and `zh-Hans` "Light".
  - "Light" keeps the comment `shell.light`, and its `zh-Hans` value is 浅色.
  - `LocalizationSource.keys(in:)` captures the first literal after `localized:`, so AC-507-1 counts `weight.light` as used.
- Add `ModelText.listSeparator` (§L6) and use it in these places:
  - `ModelText.joinAnd` (the leading parts);
  - `ModelText.unresolvedSummary` (the names);
  - `ReportText.render` (the groups and the licence-note names);
  - `ShellText.quoted`;
  - `PreviewText.missingText`;
  - `PickerText.rowAccessibilityLabel`;
  - the restoration warnings in `Model/Launch.swift`.
- English output doesn't change (", "). AC-507-9 and the existing text tests confirm it.
- Machine-readable joins stay as they are: self-test output, logs, the " · " in the Advanced counts, and the family-and-style name join.
- **Escaped percent keys (F7).** Rename `%lld %` to `%lld %%` and `%@: scale %@% is too large for a %@-unit base (maximum %@%).` to the same text with `%%`, in both the key and the `en` value. `LocalizationSource.normalized` treats `%%` as a literal, and the source side goes through `runtimeKey`, so AC-507-1 now catches a single `%` in an interpolated key.
- New lint rule **L10**: `joined(separator: ", ")` is forbidden in `Sources/FPAppUI`, except in `SelfTest/SelfTestRunner.swift` (machine output). Like the other rules, it has a positive and a negative snippet.

**D3. The Info.plist and the app bundle.**

- `App/Info.plist` adds `CFBundleLocalizations` = `[en, zh-Hans]` and `LSHasLocalizedDisplayName` = `true`, so Finder shows the localized name. `CFBundleDevelopmentRegion` stays `en`, and `CFBundleAllowMixedLocalizations` stays `true` (F3).
- `InfoPlist.xcstrings` gets these `zh-Hans` values:
  - `CFBundleName` and `CFBundleDisplayName`: 字体混搭;
  - the five usage descriptions: 字体混搭会读取你添加的文件夹中的字体，并将字体存储到你选择的位置。
- `App/Resources/Localizable.xcstrings` has one entry, "Font Playground"; its `zh-Hans` value is 字体混搭.
- `App/project.yml` should not need a change: XcodeGen turns `*.lproj` folders under `Resources` into variant groups and adds their regions to `knownRegions`. If `make app` misses a file that AC-508-12 checks, fix `project.yml` and record it under "Spec deviations".
- `scripts/check-bundle.sh` gains a `localisations` check. The app must have:
  - `Contents/Resources/en.lproj/UserGuide.html` and `Contents/Resources/zh-Hans.lproj/UserGuide.html`;
  - `Contents/Resources/zh-Hans.lproj/InfoPlist.strings`, whose `CFBundleDisplayName` is 字体混搭 and whose `FPDonateURL` is `https://afdian.com/a/kciceblue` (decisions.md D33). Read it in Python, not with `plutil`, which Linux lacks (the `test_release_config.py` fake bundle runs there). Xcode writes it as a UTF-16 XML plist whose declaration says UTF-8, so decode by BOM and re-declare before `plistlib`;
  - `Contents/Resources/FontPlaygroundMacKit_FPAppUI.bundle/Contents/Resources/en.lproj/Localizable.strings` and the same file under `zh-Hans.lproj`;
  - **no** `Contents/Resources/UserGuide.html`. `Bundle.url(forResource:withExtension:)` returns a non-localized resource before any `.lproj` one, so a leftover top-level copy would hide the Chinese guide.

**D4. The user guide.**

- Move the English guide to `App/Resources/en.lproj/UserGuide.html` with `git mv`. Its content is unchanged.
- Add `App/Resources/zh-Hans.lproj/UserGuide.html`, a translation of the English guide:
  - the same sections, `id` attributes and order;
  - the same WP-602 constraints: self-contained, inline CSS, `-apple-system-body`, a dark-mode block, no scripts, no external resources;
  - `<html lang="zh-Hans">`;
  - command names in `<strong>` exactly as the `zh-Hans` catalog shows them.
- The Chinese guide adds one sentence to its build-report section: some notes in the report come from the font engine and are in English (D32).
- `helpURL`'s code doesn't change. `Bundle.url(forResource:withExtension:)` picks the `.lproj` copy for the app's language.

**D5. The language setting.**

The `InterfaceLanguage` type, in `Model/InterfaceLanguage.swift` (new):

```swift
public enum InterfaceLanguage: String, CaseIterable, Sendable {
    case system, english = "en", simplifiedChinese = "zh-Hans"
    public static let supported = ["en", "zh-Hans"]
    /// The language this choice gives at the next launch (F5).
    public func resolved(systemLanguages: [String]) -> String
    /// What a stored `AppleLanguages` override means.
    public init(override: [String]?)
    /// The value to store: nil (remove the key), ["en"] or ["zh-Hans"].
    public var override: [String]? { get }
    /// .system: ShellText.system. The others are their own names, never translated: "English", "简体中文".
    public var title: String { get }
}
```

- `resolved`:
  - `.english` gives "en" and `.simplifiedChinese` gives "zh-Hans", whatever the system languages;
  - `.system` gives `Bundle.preferredLocalizations(from: supported, forPreferences: systemLanguages).first ?? "en"`.
- `init(override:)` looks at the first element only:
  - nil or empty → `.system`;
  - "en" or a prefix "en-" → `.english`;
  - "zh-Hans", a prefix "zh-Hans-", "zh-CN" or "zh-SG" → `.simplifiedChinese`;
  - anything else → `.system`.

`SystemActions` gains six members. `LiveSystemActions` gets an initializer, `init(defaults: UserDefaults = .standard, domain: String = Bundle.main.bundleIdentifier ?? "")`, so tests can use a temporary suite.

| Member | Live behaviour |
|---|---|
| `var runningLanguage: String { get }` | `Bundle.module.preferredLocalizations.first ?? "en"`: FPAppUI's bundle, which is what the UI shows |
| `var systemLanguages: [String] { get }` | the global `AppleLanguages` (`persistentDomain(forName: UserDefaults.globalDomain)`), else `Locale.preferredLanguages` |
| `var languageOverride: [String]? { get }` | `defaults.persistentDomain(forName: domain)?["AppleLanguages"]`. Only the app's own domain, never the global value |
| `func setLanguageOverride(_ languages: [String]?)` | `defaults.set(languages, forKey: "AppleLanguages")`, or `removeObject(forKey:)` for nil |
| `func terminate()` | `NSApp.terminate(nil)` |
| `func relaunchAfterExit()` | starts `/bin/sh` with `relaunchArguments(pid: getpid(), bundlePath: Bundle.main.bundlePath)` and does not wait for it |

`static func relaunchArguments(pid: Int32, bundlePath: String) -> [String]` returns exactly:

```
["-c", "while /bin/kill -0 \"$1\" 2>/dev/null; do /bin/sleep 0.2; done; exec /usr/bin/open \"$2\"", "fp-relaunch", "<pid>", "<bundlePath>"]
```

The waiter outlives the app, waits until the old process has gone, then opens the bundle. It passes the path as an argument, so spaces ("Font Playground.app") need no quoting.

`AppModel` changes:

- `public private(set) var interfaceLanguage: InterfaceLanguage`, initialised from `InterfaceLanguage(override: services.system.languageOverride)`.
- `var relaunchRequested = false`.
- `public func setInterfaceLanguage(_ choice: InterfaceLanguage)`:
  1. Call `services.system.setLanguageOverride(choice.override)` and set `interfaceLanguage = choice`.
  2. Let `next = choice.resolved(systemLanguages: services.system.systemLanguages)`. If `next == services.system.runningLanguage`, stop.
  3. Otherwise set `languagePrompt` (new, next to `alert`) to an `AlertContent`. `SettingsView` presents it, because the choice is made in the Settings window; `alert` is presented only by the main window, which may be hidden or minimized. Both use one shared `contentAlert(_:)` view modifier. The content is:
     - title `ShellText.reopenTitle(language:)`, filled with the title of `next`'s case ("English" or "简体中文");
     - message `ShellText.reopenMessage`;
     - buttons: "Quit and Reopen" (default), which calls `requestRelaunch()`, and "Later" (cancel role).
- `func requestRelaunch()` sets `relaunchRequested = true` and calls `services.system.terminate()`. The normal quit path then runs: QuitCoordinator flushes autosave and stops the catalog, and while a build is running it asks first (AC-501-22).
- `prepareForTermination()`: after its existing work, if `relaunchRequested`, clear the flag and call `services.system.relaunchAfterExit()`.
- `QuitCoordinator` gets a `cancelled: () -> Void` closure, called where the user keeps building (the `reply(false)` path). `FPAppDelegate` passes `{ model.relaunchRequested = false }`, so a later ⌘Q doesn't reopen the app.

Settings:

- The first `Section` of `SettingsView` holds the Language picker (`.pickerStyle(.menu)`, one item per `InterfaceLanguage.allCases`, each `Text(choice.title)`), then the existing Appearance picker.
- Its footer is `ShellText.languageFooter`.
- The Language picker's binding reads `model.interfaceLanguage` and writes through `model.setInterfaceLanguage`.

New strings. The `zh-Hans` column is part of the spec, so the maintainer reviews it together with the design.

| String id | English | zh-Hans |
|---|---|---|
| `shell.language` | Language | 语言 |
| `shell.languageFooter` | Font Playground uses a new language after it reopens. | 字体混搭会在重新打开后使用新的语言。 |
| `shell.reopenTitle` | Reopen Font Playground in %@? | 要以“%@”重新打开字体混搭吗？ (the quotes avoid §L4's spacing question, since %@ is "English" or "简体中文") |
| `shell.reopenMessage` | Your recipe is saved first. | 你的方案会先被存储。 |
| `shell.quitAndReopen` | Quit and Reopen | 退出并重新打开 |
| `shell.later` | Later | 稍后 |

"System" (`ShellText.system`) is reused for the first item, so it reads the same as in Appearance.

**D6. Tests run in English.**

- `LocalizationCatalogTests.testsResolveEnglish` asserts `Bundle(url: LocalizationSupport.bundleURL)!.preferredLocalizations.first == "en"`.
- If it fails, its message says: "FPAppUI tests assert English text. Run them with `make mac-test`, whose host has no Chinese localisation (localisation.md F2)."
- `make mac-test` needs no `-AppleLanguages` argument (F2).

### Acceptance criteria

- **AC-508-1** `LocalizationCatalogTests.everyEntryHasSimplifiedChinese`:
  - Every entry of the three catalogs of §L1 has a `zh-Hans` string unit with state `translated` and a non-empty value.
  - A `zh-Hans` value may equal its `en` value only when the entry is one of the kept names of §L3 table 3, or when the `en` value has no Latin letters outside its placeholders (for example "%" or "%@ · %@").
- **AC-508-2** `LocalizationCatalogTests.placeholdersMatchAcrossLanguages` checks §L5 for every entry, using WP-507's specifier regex:
  - The `zh-Hans` value has the same sequence of specifier types as the `en` value, **or**
  - every `zh-Hans` specifier is positional, positions 1…n each appear once, and position *k* has the type of the *k*-th `en` specifier.
  - Built-in samples: `en` "%@ can't shape %@" with `zh-Hans` "%2$@ 无法由 %1$@ 塑形" passes; `en` "%@ and %lld more" with `zh-Hans` "%lld 个以及 %@" fails.
- **AC-508-3** `LocalizationCatalogTests.zhUsesMacTerms`:
  - Every key of §L3 table 1 exists in FPAppUI's catalog, and its `zh-Hans` value is exactly the one listed.
  - No `zh-Hans` value contains "Finder", "Font Book" or "Trash", or matches `Ctrl|\bAlt\b|Enter|Windows|资源管理器|右键|右击|管理员|回车|控制面板|注册表|您`.
- **AC-508-4** `LocalizationCatalogTests.keptTermsStayEnglish`:
  - The `zh-Hans` values of `weight.light`, "Regular", "Medium", "Semibold", "Bold" and "Heavy" equal their English.
  - When an `en` value contains one of OpenType, TrueType, PostScript, AAT, Unicode, fontTools, Python, fpengine, `.fontrecipe`, `.ttf`, Return, Esc, ⌘, ⌥, ⇧ or ⌃, its `zh-Hans` value contains that token too.
- **AC-508-5** `LocalizationCatalogTests.sharedKeysAreReviewed`:
  - **Shared keys.** The keys used under more than one comment id, normalised as in AC-507-1, are exactly: "Cancel", "Style", "Latin", "%@ isn't on this Mac. Use %@ instead?", "Main font", "%", "Undo", "Install", "Save a Copy…", "Show in Finder", "Open in Font Book", "Regular", "Colour by Font", "Sample Text", "Use %@", "Size" and "%@: %@" (a name and a detail, in recipe problems and catalog issues).
  - **Context keys.** The only catalog keys matching `^[a-z]+(\.[A-Za-z]+)+$` are those of §L2 (`weight.light`).
  - **Resolution** (§L7). With locale `zh-Hans`, "Light" resolves to 浅色 and `weight.light` to "Light". With locale `en`, both are "Light", and `ShellText.weightLight == "Light"`.
- **AC-508-6** `LocalizationCatalogTests.listSeparatorsAreLocalized`:
  - The `zh-Hans` values of ", ", " and " and " & " are "、", "和" and "和".
  - F7: through §L7, `"\(80) %"` resolves to "80%" in `zh-Hans` and "80 %" in `en`. `runtimeKey` maps `"\(value) %"` to `%lld %%` and leaves the plain literal "100 % keeps" alone. The plain help string with "100 %" resolves to its Chinese value unchanged.
  - `SourceLintTests` passes L10 (D2) and detects its positive snippet but not its negative one.
  - The existing English text tests pass unchanged: ModelTextTests, ReportTextTests, RecipeColumnTextTests, PreviewPaneTests and AccessibilityTextTests.
- **AC-508-7** `LocalizationCatalogTests.testsResolveEnglish` (D6).
- **AC-508-8** `InterfaceLanguageTests`, the pure mappings:
  - `resolvesLikeTheSystem`: `.system.resolved(systemLanguages:)` gives F5's table exactly. `.english` and `.simplifiedChinese` ignore the system languages.
  - `readsStoredOverrides`:
    - nil and `[]` give `.system`;
    - `["en"]` and `["en-GB"]` give `.english`;
    - `["zh-Hans"]`, `["zh-Hans-CN"]` and `["zh-CN"]` give `.simplifiedChinese`;
    - `["zh-Hant-TW"]` and `["ja"]` give `.system`;
    - `.override` round-trips nil, `["en"]` and `["zh-Hans"]`.
  - `titles`: `InterfaceLanguage.allCases.map(\.title) == ["System", "English", "简体中文"]` in the test process.
- **AC-508-9** `InterfaceLanguageTests` flows, with `ShellFakeSystemActions`. The fake has `runningLanguage` "en" and configurable `systemLanguages`, and it records overrides, `terminate()` calls and `relaunchAfterExit()` calls.
  - `choosingTheRunningLanguageDoesNotAsk`: choosing `.english` stores `["en"]` and sets no `languagePrompt`.
  - `choosingAnotherLanguageAsksToReopen`: choosing `.simplifiedChinese` stores `["zh-Hans"]` and leaves `alert` nil. The `languagePrompt` title is `ShellText.reopenTitle(language: "简体中文")`, and its buttons are "Quit and Reopen" (default) and "Later" (cancel role).
  - `laterKeepsRunning`: "Later" records no `terminate()`, and `interfaceLanguage` stays `.simplifiedChinese`.
  - `quitAndReopenRelaunchesOnce`: "Quit and Reopen" records one `terminate()`. Then `prepareForTermination()` records one `relaunchAfterExit()`, and a second call records none.
  - `systemChoiceFollowsTheSystem`: with `systemLanguages` `["zh-Hans-CN"]`, choosing `.system` removes the override (records nil) and sets `languagePrompt`.
  - `cancelledQuitForgetsTheRelaunch`: while `isBuilding`, press "Quit and Reopen", then call the `QuitCoordinator`'s `shouldTerminate()` as AppKit would. The quit alert appears (AC-501-22). "Keep Building" leaves `relaunchRequested == false`, and a later `prepareForTermination()` records no relaunch.
- **AC-508-10** `InterfaceLanguageTests.liveOverrideUsesTheAppDomain` uses `LiveSystemActions(defaults:domain:)` with a `ShellTempDirectory` suite, which is removed afterwards:
  - `setLanguageOverride(["zh-Hans"])` gives `persistentDomain(forName: suite)?["AppleLanguages"] == ["zh-Hans"]` and `languageOverride == ["zh-Hans"]`.
  - `setLanguageOverride(nil)` removes the key, and `languageOverride == nil`.
  - `relaunchArguments(pid: 42, bundlePath: "/Applications/Font Playground.app")` equals D5's argument list exactly.
  - No test runs the waiter or terminates the process.
- **AC-508-11** `AppBundleTests.ui3InfoPlistNamesTheApp` is extended:
  - `Info.plist` has `CFBundleLocalizations == ["en", "zh-Hans"]` and `LSHasLocalizedDisplayName == true`.
  - In `InfoPlist.xcstrings`, the `zh-Hans` values of `CFBundleName` and `CFBundleDisplayName` are 字体混搭, and the five usage descriptions equal D3's sentence.
- **AC-508-12** `scripts/check-bundle.sh "build/DerivedData/Build/Products/Debug/Font Playground.app"` passes after `make app`, including the `localisations` check of D3. `scripts/tests/test_crit_10_bundle_localisations.sh` copies the app to a temporary folder, removes `zh-Hans.lproj/InfoPlist.strings`, and asserts that the check then fails and names `localisations`.
- **AC-508-13** `engine/tests/repo/test_user_docs.py`:
  - The existing tests read `App/Resources/en.lproj/UserGuide.html`, and no `App/Resources/UserGuide.html` exists.
  - `test_crit_10_chinese_user_guide`: the Chinese guide exists and has `lang="zh-Hans"`. It has no `http://`, `https://` or `<script`, and it has as many `<section>`, `<h2>`, `<li>` and `<strong>` elements as the English guide (the guides have no `id` attributes). For every `<strong>` text in the English guide that is a key of FPAppUI's catalog, the Chinese guide has a `<strong>` equal to that key's `zh-Hans` value. It contains none of 资源管理器, 右键 or 管理员权限.
- **AC-508-14** `make lint`, `make test` (on Linux and on macOS) and `make app` pass.
- **AC-508-M1** (manual, macos) Chinese walkthrough on a Debug build, launched with `open -n "build/DerivedData/Build/Products/Debug/Font Playground.app" --args -AppleLanguages "(zh-Hans)"`.
  1. Take light and dark screenshots, at the minimum window size and at a normal size, of:
     - the recipe column with a main font, a Chinese font and a missing character;
     - the picker for 中文（简体）;
     - the Advanced inspector with a report;
     - Settings;
     - the build status after Install;
     - the app menu, showing 关于字体混搭 and 退出字体混搭;
     - Help, opening the Chinese guide.
  2. No text is clipped or truncated.
  3. No English remains, except §L3 table 3 and engine data (D32).
- **AC-508-M2** (manual, macos) Switching.
  1. From English, choose Settings › Language › 简体中文, then "Quit and Reopen". The app quits and reopens within 5 s in Chinese, with the same recipe and window frame.
  2. On a Mac whose system language is English, choose 设置 › 语言 › 跟随系统, then 稍后. The app keeps running in Chinese; the next manual launch is English.
  3. System Settings › General › Language & Region › Applications lists the app with English and 简体中文. A choice made there shows in the app's Language picker after reopening.
  4. With a build running, "Quit and Reopen" first asks "Your font is still being built. Quit anyway?". "Keep Building" leaves the app running, and a later ⌘Q quits without reopening.
- **AC-508-M3** (manual) Review.
  1. A native speaker reviews every `zh-Hans` value and the Chinese guide. The PR names the reviewer and lists the strings the review changed.
  2. On a Mac or user account whose system language is 简体中文, Finder, Launchpad and the Dock show 字体混搭.
- **AC-508-M4** (manual, macos) VoiceOver in Chinese. The card "more" button, the preview size slider and a picker row are announced in Chinese (WP-507 D1). Attach screenshots of the VoiceOver caption panel.

### Verification

```bash
make lint
make test
make app
scripts/check-bundle.sh "build/DerivedData/Build/Products/Debug/Font Playground.app"
scripts/tests/test_crit_10_bundle_localisations.sh
open -n "build/DerivedData/Build/Products/Debug/Font Playground.app" --args -AppleLanguages "(zh-Hans)"
```

### Notes for the implementer

- **Start with the tests.** Write AC-508-1 to AC-508-6 first: they list every missing or inconsistent value mechanically. Then translate.
- **Don't choose the language with the wrong tools.** `String(localized:locale:)` doesn't choose the translation (F1). SwiftUI's `.environment(\.locale)` doesn't either, because the UI passes `String` values, not `LocalizedStringKey`. Don't add `-AppleLanguages` to `make mac-test` (F2). If AC-508-7 fails, investigate the test host.
- **The Chinese name lives only in catalog values.** The bundle's file name stays `Font Playground.app`; the release pipeline, notarization, the DMG and `check-bundle.sh` use it.
- **Check width-sensitive places in Chinese:**
  - the action bar;
  - the card role titles;
  - the picker row's native-name column (capped at 40 %);
  - the Advanced inspector columns;
  - the segmented Appearance control.
- **Spot missing keys quickly.** After `make app`, run `plutil -p` on the compiled `zh-Hans.lproj/Localizable.strings`.
