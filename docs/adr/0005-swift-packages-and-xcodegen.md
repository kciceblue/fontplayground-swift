# ADR-0005: Two Swift packages split by platform, plus an XcodeGen app target

- **Status:** accepted (2026-09-29). The Linux requirement is superseded by [ADR-0014](0014-macos-only.md) (2026-09-30); the package split stays.

## Context
Codex cloud runs Linux with Swift 6.1/6.2 and has no Apple frameworks. Agents are bad at editing `project.pbxproj`.

## Decision
- `Packages/FontPlaygroundKit` has the targets `FPCore`, `FPEngineClient` and `fpctl`, with their tests. It uses Foundation only and must build and test on Linux.
- `Packages/FontPlaygroundMacKit` has the targets `FPMacServices` and `FPAppUI`, with their tests. It is macOS only and depends on `FontPlaygroundKit` by path.
- `App/project.yml` (XcodeGen) defines the app target, which is a thin shell over `FPAppUI`. The `.xcodeproj` is generated and git-ignored.
- `swift-tools-version: 6.1`, Swift 6 language mode. No third-party Swift packages in v1. Anything added later needs an ADR, and must not break the Linux build of `FontPlaygroundKit`.

## Consequences
- About half of the Swift work (core, client, CLI) can be dispatched to Codex cloud and verified there.
- Views live in a package, so previews and unit tests don't depend on the app target.
