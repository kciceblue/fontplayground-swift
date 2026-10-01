# ADR-0006: FPCore is value types; UI state lives in an @Observable AppModel

- **Status:** accepted (2026-09-29)

## Decision
- `FPCore.Recipe` is a `struct` (Sendable, Codable, Equatable) with `mutating` operations that mirror `ForgeModel`'s public behaviour. Derived values (`sources`, `missing`, `glyphEstimate`, suggestions, names) are computed properties or pure functions.
- There are no timers, threads or observers in `FPCore`.
- `FPAppUI.AppModel` is `@MainActor @Observable final class`. It owns the `Recipe`, the catalog store, the build controller and the settings, and it calls services through protocols (`EngineRunning`, `FontInstalling`, `FontCataloging`, `FontRendering`) so tests can inject fakes.
- The original 150 ms plan debounce is not ported. Recompute synchronously. If profiling shows a need, debounce in `AppModel`, not in `FPCore`.

## Consequences
- The recipe logic is fully testable on Linux.
- Undo/redo can snapshot `Recipe` values (backlog).
