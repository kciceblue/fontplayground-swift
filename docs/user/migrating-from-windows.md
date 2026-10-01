# Moving your recipe to the Mac

## Your last recipe

Before you first open Font Playground on the Mac, copy only `forge_last.json` from `%LOCALAPPDATA%\FontPlayground\` on the PC to `~/Library/Application Support/FontPlayground/forge_last.json` on the Mac. Create that folder if needed. The app imports it once at first launch and says “Imported your last recipe and settings from the earlier version of Font Playground.” With only the recipe file present, your Mac settings keep their defaults.

Fonts are matched to installed Mac fonts where possible. The app names missing fonts and offers Mac equivalents, such as Songti SC for SimSun. These are suggestions: choose a replacement yourself. The original recipe file is left in place. PC output paths and unsupported settings are reported rather than reused.

## Don't copy the settings folder

Don't copy the whole `%LOCALAPPDATA%\FontPlayground` folder. `settings.json` and `catalog.json` describe the PC's fonts and folders (paths like `C:\Windows\Fonts` and `D:\Fonts` mean nothing on a Mac), and Font Playground for Mac keeps its settings elsewhere.

## Windows fonts on the Mac

Microsoft's fonts (YaHei, SimSun, DengXian, Meiryo, Malgun Gothic, Calibri, Consolas and others) are not part of macOS. Microsoft Office carries private copies that other apps can't use, licensed for use with Office only. Copying `C:\Windows\Fonts` to a Mac is outside the Windows font licence. Use the Mac equivalents below; a separate font licence may grant different rights.

## Windows fonts and their Mac equivalents

| On Windows | On your Mac | Notes |
|---|---|---|
| Segoe UI | SF Pro, Helvetica Neue | SF Pro needs a separate installation |
| Microsoft YaHei, Microsoft YaHei UI, DengXian | PingFang SC | Simplified Chinese |
| Microsoft JhengHei, Microsoft JhengHei UI | PingFang TC | Traditional Chinese |
| SimSun, NSimSun | Songti SC | Simplified Chinese serif |
| MingLiU, PMingLiU, MingLiU_HKSCS | Songti TC | Traditional Chinese serif |
| SimHei | Heiti SC, STHeiti | Chinese sans serif |
| KaiTi | Kaiti SC | Chinese calligraphic |
| FangSong | STFangsong | Chinese fangsong |
| Meiryo, Yu Gothic, MS Gothic, MS UI Gothic, MS PGothic | Hiragino Sans, YuGothic | Japanese sans serif |
| MS Mincho, MS PMincho, Yu Mincho | Hiragino Mincho ProN, YuMincho | Japanese serif |
| Malgun Gothic, Gulim, GulimChe, Dotum, DotumChe | Apple SD Gothic Neo | Korean sans serif |
| Batang, BatangChe, Gungsuh, GungsuhChe | AppleMyungjo | Korean serif |
| Consolas | SF Mono, Menlo | SF Mono needs a separate installation |
| Calibri | — | no close equivalent ships with macOS |
| Arial, Georgia, Times New Roman, Verdana, Tahoma, Trebuchet MS, Courier New | the same fonts | ship with macOS |

SF Pro and SF Mono are the system fonts; they appear in the font list only if you installed them from Apple's developer site. If a Mac font in this column is missing, open Font Book: several are free downloads there.

## Fonts you forged on Windows

They keep working on the Mac. Font Playground never replaces a font it did not install itself. To build one with the same name, first remove the copy with Font Book.

## What's different on the Mac

Install puts fonts in your own `~/Library/Fonts` folder. Settings ▸ Appearance follows the system, or lets you choose Light or Dark. Show in Finder reveals saved files; ⌘ shortcuts replace Control shortcuts. The app and Python engine come together in a DMG. Public releases require Apple notarization; development DMGs are not notarized.
