# ADR-0010: Developer ID + notarization + DMG; no sandbox, no App Store

- **Status:** accepted (2026-09-29)
- **Evidence:** audit `TOOLING-1`, `TOOLING-13`, `NATIVE-8`, `CRIT-1`

## Decision
- Distribute a notarized, stapled DMG signed with a **Developer ID Application** certificate and the hardened runtime, with no entitlements. A Homebrew cask is optional later.
- Not sandboxed. The App Sandbox cannot write `~/Library/Fonts`, and it needs user-selected access to read arbitrary font folders.
- The main executable must be built with the Xcode 26+ SDK. A CI check fails the release when `otool -l` reports an older `sdk`.
- Local and dev builds may be ad-hoc signed, or signed with an "Apple Development" identity (a stable identity keeps privacy-prompt grants across rebuilds).
  - Ad-hoc builds must sign the embedded helper's Mach-Os **without** the hardened runtime: library validation rejects ad-hoc extension modules ("different Team IDs").
  - Team-signed builds use the hardened runtime everywhere.
  - Debug builds may carry Xcode's `get-task-allow`. No entitlement is used in any build.

## Consequences
- The maintainer needs a paid Apple Developer Program membership and a Developer ID certificate before the first public release (M5).
