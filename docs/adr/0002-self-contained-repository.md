# ADR-0002: Self-contained repository; the engine's canonical home moves here

- **Status:** accepted (2026-09-29)

## Context
Coding agents (Codex cloud) clone one repository and usually have no network access during the task. The engine fixes found by the audit (cmap, OS/2, PostScript names, fsType…) apply on every platform.

## Decision
- `fontplayground-swift` contains everything needed to build and test: the Python engine (`engine/`), the Swift packages, the app, the specs, and a read-only reference copy of the original app (`reference/fontplayground-py@14b6572`).
- There are no git submodules and no build steps that fetch sibling repositories.
- `engine/src/fpengine` is the canonical engine from now on. The original Windows Qt app (`kciceblue/fontplayground`) is not changed by this plan. Back-porting `fpengine` to it is out of scope, but possible because `fpengine` stays platform-neutral.
- `reference/` is deleted at cutover (WP-701), after the conformance fixtures are frozen.

## Consequences
- Every WP can be verified from a clean clone.
- Engine fixes need a separate decision to reach the Windows app.
