# Font Playground

English · [简体中文](README.zh-Hans.md)

Font Playground combines fonts on your Mac into one font. Choose a main font for letters and numbers, add fonts for other languages, and see which font draws each character. Then install the result or save it as a `.ttf` file. For example, pair Georgia for Latin text with PingFang for Chinese, Hiragino for Japanese or Apple SD Gothic Neo for Korean.

It's for people who find FontForge too much: there are no glyphs to edit, only a recipe and a preview.

## Requirements

A Mac with Apple silicon and macOS 14 Sonoma or later.

## Install

Download `FontPlayground-<version>-arm64.dmg` from the [latest release](https://github.com/kciceblue/fontplayground-swift/releases/latest), open it, and drag Font Playground to Applications. Python and the font engine are included, so there is nothing else to install.

Releases are signed with a Developer ID and notarized by Apple. A DMG you build yourself from source is ad-hoc signed and not notarized.

## Using Font Playground

Everything happens in one window. The recipe on the left lists the fonts your font is made of, from top to bottom. The preview on the right draws your text exactly as the result will; click it and type.

1. Click **Choose Main Font…** and pick a font for letters and numbers. The main font also sets the line spacing. In the picker, search by English or native name, press ↑ or ↓ to try a font in the preview, press Return to choose it, or press Esc to go back. ⌘F also opens the picker.
2. When your text has characters the main font can't draw, the recipe offers a button such as “Choose a font for Chinese…”. To add a font for another language yourself, click “Add a font for another language…”. A font added for a language draws that language, even where a font above it could. Adjust the Size and Weight of added fonts so they sit well with the main font. **Colour by Font** tints each character by the font that draws it. Characters no font can draw are listed under the preview, with a button to find a font for them.
3. Name the result and click **Install**. Font Playground builds the font and installs it for your user account only, in your Fonts folder (`~/Library/Fonts`). The preview then switches to the built font. After you change the recipe, click **Update Installed Font**. **Save a Copy…** saves a `.ttf` file where you choose, and **Show in Finder** shows the result in Finder. Font Playground never installs over a font that's already on your Mac, and it asks before replacing a font it installed earlier.
4. To use fonts that aren't installed, choose **Add Font Folder…**. After you add or remove fonts, choose **Rescan Fonts**. **Start Over** clears the recipe after asking you. In **Settings…** (⌘,), Appearance sets Light, Dark or System, and Language switches the app between English and 简体中文 (Simplified Chinese). Font Playground offers to reopen to apply the new language.

**Show Advanced** (⌥⌘I) opens a panel where you can see and change which font draws each script, choose which font sets the line spacing, set the default weight and size, and read the last build's report. You can cancel a build while it runs. Pressing Return in the name field doesn't start a build.

## What the result contains

- One glyph for each character, taken from the font that draws it, plus the extra glyphs its OpenType features need. Unused glyphs and hinting are removed.
- Ligatures, kerning and marks, kept within each source font where possible. Legacy kerning is converted to OpenType positioning.
- New names, and the main font's vertical metrics, unless you choose another line-spacing source in Advanced.
- The copyright, trademark and licence notices of the source fonts it uses.
- The most restrictive embedding permission of its source fonts.

The build report lists licence restrictions, processing warnings, and notes on fonts bundled with macOS or Microsoft products. Apple-only ligatures, kerning and tracking can't be carried over. The report says when this happens, and the built-font preview shows the final result.

## Font licences

Font Playground doesn't include, sell or distribute any fonts. It uses only fonts already on your Mac or in folders you add, and it never uploads them.

A forged font is a modified copy of its source fonts, and it stays under their licences. Some licences allow use on your own computer only, and some don't allow modified copies at all. Check each source font's licence before you forge, and again before you share, sell or embed the result. Fonts bundled with macOS or a Microsoft product are licensed for use on your own Mac only, so never share a font forged from them. Some licences, such as the SIL Open Font License, can also forbid giving a modified font the original's name.

The report shows what Font Playground can read from each font: its embedding permission, its licence notes, and whether it came with macOS or a Microsoft product. That information can be incomplete or wrong, and it isn't legal advice. If you're unsure what a licence allows, ask the font's vendor.

## Coming from the Windows version

[Migrating from Windows](docs/user/migrating-from-windows.md) explains how to import your last recipe and which Mac fonts replace common Windows fonts.

## Not in this version

Font Playground can't build a whole family in one run, edit glyphs, kern across fonts, or keep colour emoji. It also drops per-language variants of characters shared by Chinese, Japanese and Korean (the `locl` feature), so merged fonts stay within the glyph limit.

Font Playground detects Apple AAT shaping but can't merge it. A font that relies on AAT for a complex script isn't offered for that script; choose one of the OpenType fonts the picker offers instead. Missing and unsupported characters are always counted and shown.

## Privacy

Font Playground works only on your Mac. It collects no data and makes no network requests of its own. Donate… opens a web page in your browser, and Get More Fonts… opens Font Book, which can download fonts if you ask it to.

Font Playground keeps your last recipe and the list of fonts it installed in `~/Library/Application Support/io.github.kciceblue.fontplayground/`, and your preferences in macOS's settings storage. Font scans, temporary build files and recent build outputs are in `~/Library/Caches/io.github.kciceblue.fontplayground/`. Install writes to `~/Library/Fonts`, and Save a Copy… writes only where you choose.

## Uninstall

Fonts you installed stay available to other apps after you remove Font Playground. To remove the current one first, choose File › Uninstall Font, which moves it to the Trash. You can also remove any font in Font Book at any time.

Then drag Font Playground from Applications to the Trash. To remove its data too, delete the two folders listed under Privacy and run `defaults delete io.github.kciceblue.fontplayground` in Terminal.

## Support Font Playground

Font Playground is free and open source. If you find it useful, you can support its development on [Buy Me a Coffee](https://buymeacoffee.com/kciceblue), or choose Font Playground › Donate… in the app.

To report a bug or suggest a feature, open an [issue](https://github.com/kciceblue/fontplayground-swift/issues). Name the fonts involved instead of attaching them.

## Acknowledgements and licence

Font Playground is released under the [MIT License](LICENSE). Font Playground › About Font Playground lists the bundled components and their full licence texts, including CPython, fontTools, skia-pathops, Unicode data and the runtime libraries. The outline conversion includes code adapted from Just van Rossum's `otf2ttf` snippet.

## Disclaimer

Font Playground is an independent project. It isn't affiliated with, endorsed or sponsored by Apple, Microsoft or any font vendor. Font names in the app and this document, such as Georgia, PingFang, Hiragino and Apple SD Gothic Neo, are trademarks of their owners and are used only to identify those fonts. Apple, Mac, macOS and Finder are trademarks of Apple Inc., and Microsoft is a trademark of Microsoft Corporation.

Font Playground is provided "as is", without warranty of any kind, as the [MIT License](LICENSE) says. You choose which fonts to forge and what to do with the result, and you are responsible for respecting their licences. The authors aren't liable for any claim that arises from fonts you forge, install or share with Font Playground. Nothing in the app or its documentation is legal advice.

## Development

See the [development guide](docs/development.md) to build and test the app, and [architecture](docs/architecture.md) for how it fits together.
