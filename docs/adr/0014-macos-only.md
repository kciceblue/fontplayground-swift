# ADR-0014: Build, test and run CI on macOS only

- **Status:** accepted (2026-09-30)
- **Supersedes:** the Linux requirement of ADR-0005

## Context
- `FontPlaygroundKit` was kept buildable on Linux so that `linux` work packages could run in Codex cloud, which has no Apple frameworks (ADR-0005). That work (engine, protocol, Swift core) is done and merged.
- Font Playground is a Mac app. Supporting Linux had its own costs:
  - a second CI job with a Swift 6.1/6.2 matrix, and a setup script for the cloud environment;
  - `#if canImport(Glibc)` imports;
  - workarounds for swift-corelibs-foundation's `Process`, which on macOS resets the child's signal mask and does not leak descriptors (checked on macOS 27).
- Less is more: one platform is enough work.

## Decision
- Development, tests and CI run on macOS only. The Makefile stops with one clear error on any other system.
- CI has one job, `macos`. After `make setup` it runs `make lint` and `make test` with `UV_OFFLINE=1`, which keeps the offline check the Linux job used to make (AGENTS.md rule 6).
- Remove `scripts/codex-setup.sh`, the Glibc conditionals, `HelperRun`'s spawn lock and `Signals.withUnblockedSignals`.
- Keep the two Swift packages. `FontPlaygroundKit` (FPCore, FPEngineClient, fpctl) still imports no AppKit, SwiftUI, CoreText or CoreGraphics. This is now for layering, not for portability: the recipe logic and helper client stay testable without UI, and CoreText calls stay in `FontPlaygroundMacKit`, where `NameLookupSafetyTests` watch them (AGENTS.md rule 4).
- The engine stays plain Python. Nothing in it is removed, but it is built and tested only on macOS.

## Consequences
- Agents work on the Mac (Codex CLI or Claude Code), not in Codex cloud (docs/dispatch.md).
- Specs written before this ADR keep their text. There, `Env: linux` means "needs no Apple frameworks". Acceptance criteria that name the Linux CI job, Swift 6.1 on Linux or `scripts/codex-setup.sh` are retired. `docs/plan.md` §3 says the same.
