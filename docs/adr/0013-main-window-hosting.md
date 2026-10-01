# ADR-0013: Main window is an AppKit NSWindow hosting SwiftUI; one `@main` launcher

- **Status:** accepted (2026-09-29)
- **Evidence:** ui-shell.md WP-501 and foundation-release.md WP-001/WP-601 review findings; audit `UI-10`, `TOOLING-14`

## Context
- The app must ask before closing its window while a build runs (UI-10). SwiftUI on macOS 14 cannot veto a window close. A single SwiftUI `Window` scene also quits the app when it closes.
- `--self-test` (WP-601) must run headless, before `NSApplication` exists. Otherwise it creates a Dock icon and activates the app.

## Decision
- `App/Sources/Launcher.swift` is the **only** `@main`. WP-001 creates it.
  - With `--self-test`, it runs the self-test and exits, and AppKit never starts.
  - Otherwise it calls `FontPlaygroundApp.main()`.
- `FontPlaygroundApp` (SwiftUI `App`, **not** `@main`) declares only a `Settings` scene and `.commands`. `NSApplicationDelegateAdaptor` forwards `applicationShouldTerminate`, `applicationShouldTerminateAfterLastWindowClosed` and `applicationShouldHandleReopen`.
- The main window is an `NSWindow` hosting the SwiftUI root through `NSHostingController` (with `sceneBridgingOptions`). It is owned by a window controller that implements `windowShouldClose` for the build-in-progress prompt.
- The version numbers `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` live in `App/Version.xcconfig`.

## Consequences
- Menu commands read the `@Observable` `AppModel` directly; they refresh when a menu opens (verified headless).
- Window restoration and frame autosave are handled by the window controller rather than by SwiftUI scene storage.
