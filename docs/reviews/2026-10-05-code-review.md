# Whole-codebase review — 2026-10-05

Reviewed at `679751b` (branch `main`, clean tree) on Apple silicon, macOS 27.0.1 (26A434), Xcode 27.0 (27A266a).
Lenses requested: **AGENTS.md hard-rule compliance**, **correctness / edge cases**, **security / safety**.
Risk-prioritized: helper process boundary, catalog/discovery, persistence, release signing, then UI state.

This file is a review record, not a work package. Nothing here has been implemented.

---

## 1. Verification run (evidence)

| Command | Result |
| --- | --- |
| `make lint` | PASS — `ruff check`: All checks passed!; `ruff format --check`: 109 files already formatted; `swift format lint --strict`: clean |
| `make engine-test` | PASS — **457 passed, 50 skipped** in 23.48 s (all skips are `apple_fonts`, need `FP_APPLE_FONTS=1`) |
| `make kit-test` | PASS — **223 tests** across 3 runs, exit 0 |
| `make mac-test` | **259/260** — 1 failure, see finding M3 |
| `make conformance-check` | PASS — `frozen: 6 files verified`, every fixture `unchanged`, `git diff --exit-code` clean, no untracked fixtures |
| isolated rerun of the failing test | PASS — `WP503 scroll: p95 10.239 ms, max 18.862667 ms, 84 half-viewport steps / 420 families` (limits 16.7 / 33) |

Reproduce the isolated rerun:

```sh
FP_ENGINE_PYTHON=$PWD/engine/.venv/bin/python \
  swift test --package-path Packages/FontPlaygroundMacKit --no-parallel \
  --filter scrollWithoutDroppedFrames
```

Environment note: a global `ruff` is not on `PATH` on this machine; the Makefile invokes
`uv run --project engine --frozen ruff`, so this is not a repo problem.

---

## 2. Findings

Severity is about user-visible impact and blast radius, not how hard the fix is.

### M1 — Pressing Stop can block the main actor for the full termination grace

**Where**
`Packages/FontPlaygroundKit/Sources/FPEngineClient/HelperRun.swift:103-104`

```swift
// NATIVE-7: onTermination must not release the caller before the child and leftovers are gone.
finished.wait()
```

**Chain**
1. `EngineClient.stream(...)` installs `continuation.onTermination = { if case .cancelled = $0 { control.cancel() } }`
   (`Packages/FontPlaygroundKit/Sources/FPEngineClient/EngineClient.swift:98`).
2. The only cancellation paths into `HelperRun.cancel()` are that handler and `EngineClient.swift:46` (hello gate) —
   confirmed by grep; there is no other caller.
3. `BuildController` consumes the forge stream inside `task = Task { @MainActor in … }`
   (`Packages/FontPlaygroundMacKit/Sources/FPAppUI/Model/BuildController.swift`), and `cancel()` calls `task?.cancel()`
   from the main actor.
4. If `AsyncThrowingStream` delivers `onTermination` on the consuming thread, `finished.wait()` executes on the main
   actor: SIGTERM → wait `configuration.timeouts.terminationGrace` (2 s,
   `Packages/FontPlaygroundKit/Sources/FPEngineClient/EngineConfiguration.swift:49-50`) → SIGKILL → reap →
   reader EOFs → `finishIfReady` → `finished.leave()`. The UI is frozen for the whole window.

**Why the existing safety net does not cover it**
`BuildController.cancelAndWait()` races `await task.value` against `Task.sleep(for: .milliseconds(2800))` with the
comment about leaving headroom inside the three-second quit deadline. Both racing `Task { … }` blocks are created
inside a `@MainActor` function, so they inherit the main actor. If the main actor is parked in `finished.wait()`,
neither the sleep nor the `task.value` resume can be scheduled — the race cannot fire.

**Test gap**
`Packages/FontPlaygroundKit/Tests/FPEngineClientTests/ProcessTests.swift:99,123,229,278` cancel a background `Task`
and assert the child dies. Nothing asserts how long cancellation takes when the cancelling thread is the main actor.

**Confidence**: the code chain is verified by reading; the exact thread on which `onTermination` runs is **not** proven.
Measure before changing anything.

**Suggested next step**
Instrument: timestamp the main actor before/after `task?.cancel()` in a UI-driving test (or a `FPMacHarness` run with
a real forge in flight) and log the stall. If confirmed, either hop to `Task.detached` before waiting, or have
`onTermination` signal a continuation that a non-main thread waits on, keeping NATIVE-7's guarantee (child and
leftovers gone before the *stream* completes) without blocking whoever terminates it. Make `cancelAndWait`'s deadline
`Task.detached` regardless, so the escape hatch cannot be starved.

### M2 — An unreadable font is reported as "unsupported format"

**Where**
`Packages/FontPlaygroundMacKit/Sources/FPMacServices/Catalog/FontDiscovery.swift:77-82`, used at
`Packages/FontPlaygroundMacKit/Sources/FPMacServices/Catalog/CatalogStore.swift:159`

```swift
static func isSFNT(_ path: String) -> Bool {
    guard let file = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)) else { return false }
    defer { try? file.close() }
    guard let bytes = try? file.read(upToCount: 4), bytes.count == 4 else { return false }
    return MacServicesConstants.sfntMagics.contains(bytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) })
}
```

```swift
} else if FontDiscovery.isSFNT(file.path) {
    working.files.append(file); misses.append(file)
} else {
    … working.skipped.append((file.path, .unsupportedFormat))
}
```

**Problem**
`try?` collapses three different outcomes into `false`: magic mismatch (genuinely unsupported), open failure
(`EACCES`, sandbox denial, volume asleep), and short read (truncated or racing file). All three land in
`.unsupportedFormat`. A permission-denied `.ttf` therefore disappears from the catalog with a message that tells the
user their font is the wrong *type*, which is wrong and unactionable.

AGENTS.md rule 7 ("No silent drops. Anything filtered, skipped, **unresolved or failed** is counted and surfaced")
is satisfied in the letter — the file is counted — but the reason is a misdiagnosis, which is the failure mode the
rule exists to prevent.

**Fix**
Make the probe tri-state, e.g. `enum FormatProbe { case sfnt, other, unreadable(Int32) }`, and route `.unreadable` to
`CatalogIssue.unreadable(path:code:"io_error", …)` (the shape `FontDiscovery.discoveryFailure` already produces)
instead of a skip.

### M3 — `scrollWithoutDroppedFrames` is a flaky gate

**Where**
`Packages/FontPlaygroundMacKit/Tests/FPAppUITests/PickerPerformanceTests.swift:100`

```swift
#expect(p95 <= 16.7 * factor && maximum <= 33 * factor)
```

**Observed**
Red under load (machine busy with five subagents plus concurrent `swift build`), green in isolation at roughly 40 % of
the p95 budget. The threshold is fine; the *scheduling* is not.

**Why it is a repo issue and not just my machine**
`docs/testing.md` states that Mac CI and release checks set `SWIFT_TEST_FLAGS=--no-parallel` for MacKit, while local
`make mac-test` keeps its normal (parallel) defaults. So the frame-time assertion runs concurrently with the rest of
the 260-test suite locally, where a developer's laptop is also doing other things. A gate that goes red on a busy
laptop trains everyone to ignore it when it goes red for real.

**Fix options**
Run the performance target serially in `make mac-test` as CI does, or split frame-time tests into their own serial
suite, or gate them behind an explicit opt-in env var the way the apple-fonts suite gates on `FP_APPLE_FONTS=1`.
Keep the "do not sleep between samples" rule from `docs/testing.md` — the p95 numbers there (9.8 ms at 16 ms gaps vs
20.6 ms at 130 ms gaps, M5 Pro) show why the sampling shape must stay as it is.

### L1 — `release.yml` grants `contents: write` to the pull-request run

**Where** `.github/workflows/release.yml` (top-level `permissions`), triggers include `pull_request` on paths
`.github/workflows/release.yml`, `scripts/**`, `App/project.yml`, `tools/release/**`.

The step that creates the release is correctly gated
(`if: github.event_name == 'push' && startsWith(github.ref, 'refs/tags/')`), but the write permission is declared at
workflow level, so the PR-triggered job — which checks out and executes PR-modified scripts and receives
`GH_TOKEN: github.token` — also holds it. Mitigations already in place: same-repo-PR-only guard, so fork PRs never run
on the self-hosted Mac.

**Fix**: move `permissions: contents: write` onto the release jobs only; leave the workflow at `contents: read`.

### L2 — A cancelled queued refresh still runs

**Where** `Packages/FontPlaygroundMacKit/Sources/FPMacServices/Catalog/CatalogStore.swift`, `cancelWaiter(_:)` and
`finish(_:)`.

`cancelWaiter` resumes and removes the waiter from `queuedWaiters` but never clears `queuedMode`. `finish` then sees
`if let mode = queuedMode` and calls `start(mode)` with an empty waiter set — a full discovery plus helper scans for
work nobody is waiting for. Cheap to fix: clear `queuedMode` when `queuedWaiters` becomes empty.

### L3 — Depth truncation and failed directory stats are silent in discovery

**Where** `Packages/FontPlaygroundMacKit/Sources/FPMacServices/Catalog/FolderWalker.swift`, `descend(_:depth:)`.

```swift
guard depth <= maxDepth, let stamp = DiscoveredFileStamp(directory.path),
    !excludedIDs.contains(stamp.identity),
    !excluded.contains(where: { … }),
    visited.insert(stamp.identity).inserted
else { return }
```

One guard covers four different reasons to stop. Exceeding `maxDepth` (32) and a failing `stat` both return with no
issue and no skip entry, so fonts below the cap vanish without a count. The other exclusions are deliberate and the
rest of the walker is careful about counting (`._` AppleDouble → `.appleDouble`, dot files with a font extension →
`.hiddenFile`, known-bad extensions → `.unsupportedFormat`).

**Fix**: separate the guards; on depth overflow append one `CatalogIssue` naming the truncated subtree.

### L4 — Stale per-path entries after `noteInstalled`

**Where** `CatalogStore.noteInstalled(_:)`.

It removes the previous `DiscoveredFile` matching the identity or path and appends the new one, but leaves the old
path's `working.faces` / `working.errors` entries behind. Harmless in the snapshot (`CatalogBuilder` iterates files),
reclaimed by the next full refresh's prune, but it grows across renames within one session.

### L5 — `AtomicFile` does not fsync the parent directory

**Where** `Packages/FontPlaygroundKit/Sources/FPCore/Persistence/AtomicFile.swift`.

The implementation matches AGENTS.md rule 8 exactly — temp file in the same folder, `handle.synchronize()`, then a
POSIX `rename()` with the documented TOOLING-2 rationale for not using `replaceItem`. It makes the write
non-torn, but not durable across power loss, because the directory entry is not synced. Foundation offers no
directory fsync; this is acceptable for a font cache and recipe drafts. Recorded so the trade-off is explicit, not
accidental.

### L6 — Signing passphrases are visible in `ps`

**Where** `.github/workflows/release.yml:85-90`.

`security create-keychain -p`, `unlock-keychain -p`, `import -P` and `set-key-partition-list -k` all take their
secret as an argument, which is visible in the process list to other users of the runner. There is no stdin
alternative for these subcommands, so this is a standard macOS CI limitation.

Already well mitigated: `umask 077`, a fresh random `password=$(openssl rand -base64 32)` per run (so the throwaway
keychain password is not the P12 password), `-T /usr/bin/codesign` plus
`set-key-partition-list -S apple-tool:,apple:,codesign:` to stop other binaries using the key, `rm -f` of
`release.p12` immediately after import, and an `if: always()` cleanup step that restores the keychain search list from
`keychains-before.txt`, deletes the keychain and removes `notary.p8`, `release.p12`, `keychains-before.txt`. The
residual is that `MACOS_DEVELOPER_ID_P12_PASSWORD` appears in ARGV at `:89`. Acceptable on a single-tenant runner;
worth a line in `docs/self-hosted-ci.md` if the runner is ever shared.

---

## 3. Things done well (worth keeping)

- **Engine stdout purity** — `engine/src/fpengine/cli.py` captures `out_stream = sys.stdout.buffer`, then sets
  `sys.stdout = sys.stderr` for the whole run and restores it in `finally`. A stray `print()` anywhere in the engine
  cannot corrupt the JSON Lines stream. `_silence_closed_stdout()` dup2's `/dev/null` on `ClientGone`; exit codes are
  distinct (2 bad request, 3 internal, 130 SIGINT, 143 SIGTERM); a terminal `error` event is emitted only
  `if not out.terminal_sent`; `watchdog.start_parent_watchdog()` runs only when stdin and stdout are both `None`, so
  in-process tests do not kill themselves.
- **`HelperRun` pipe discipline** — reader threads keep draining and discarding after completion, so a full pipe can
  never deadlock a finished run; `LineFramer` caps a line at 32 MiB → `protocolViolation`; the launch-failure path
  sets `exited` plus both EOF flags so the `DispatchGroup` stays balanced; `finishIfReady(force:)` fires 1 s after
  exit to cover a stuck reader; `finished.leave()` is deliberately ordered before `onFinish(…)`.
- **`NameLookupSafetyTests` is a real gate**, not a rubber stamp: token list covers `CTFontCreateWithName(`,
  `CTFontDescriptorCreateWithNameAndSize(`, `CTFontDescriptorCreateMatchingFontDescriptors(`, `NSFont(name:`,
  `Font.custom(` and more; the allow-list is per file with **exact occurrence counts**; a meta-test proves the scanner
  catches a planted violation, ignores comments, and fails if an allow-listed file grows a second occurrence.
- **`CatalogStore.scan` resilience** — on a non-fatal batch failure it binary-splits the unresolved files and retries
  each half, so one poison font cannot take down a batch; single-file failures become a `helper_failed` error record;
  and any file left with neither faces nor an error gets a synthesised `no_faces`. Fatal helper errors
  (`helperNotFound`, `launchFailed`, `incompatibleHelper`) propagate as `CatalogError.engineUnavailable` instead of
  being recorded per file.
- **Cancellation semantics in the catalog** — `runRefresh` keeps the previous catalog visible, re-adds only fully
  completed batches, and still reports current menu visibility, disabled faces, skips and folder issues. The generic
  error path restores both `working` and the cache.
- **Forward compatibility is counted** — `EngineClient.Diagnostics` tracks stderr bytes and unknown event types
  skipped, so a newer helper does not silently confuse an older app.
- **`FolderWalker` cycle safety** — a `(st_dev, st_ino)` visited set kills symlink cycles and aliased-root double
  walks; `~/Library/Containers` and `~/Library/Group Containers` are excluded by identity as well as by path;
  `__MACOSX`, bundles/frameworks/kexts and `isPackage` directories are skipped; `readdir` results are collected before
  iteration and `errno` is checked after the loop.
- **Supply chain** — `scripts/build-helper-runtime.sh` uses
  `curl --fail --location --proto '=https' --tlsv1.2 --retry 3`, downloads to `.part`, and compares
  `shasum -a 256` against `scripts/python-runtime.pin` **before** unpacking (line 66-68).
- **CI hygiene** — `.github/workflows/ci.yml` pins every action to a full commit SHA, sets
  `persist-credentials: false`, `permissions: contents: read`, `UV_OFFLINE=1` after `make setup`, and keeps fork PRs
  off the self-hosted Mac.
- **Re-entrancy in `BuildController`** — every state write is guarded by a minted `UUID` run token
  (`current(id) = id == runID`), including inside the `for try await` forge loop, and `BuildOutputs` is deleted on the
  `!kept` path via `defer`.
- **`SelfTestRunner` cannot pass vacuously** — distinct exit codes (3 setup, 4 timeout, 1 otherwise), and steps throw
  on missing prerequisites (`font engine not found`, `an embedded font engine is required`, `recipe missing`,
  `scan stopped without a result`) rather than skipping.

---

## 4. Hard-rule scorecard

| # | Rule | Result | Evidence |
| --- | --- | --- | --- |
| 1 | Never hand-edit `spec/fixtures/` | PASS | `make conformance-check` → `frozen: 6 files verified`, all `unchanged`, clean `git diff` |
| 2 | `FontPlaygroundKit` imports no UI/font frameworks | PASS | grep for AppKit/SwiftUI/CoreText/CoreGraphics under `Packages/FontPlaygroundKit/Sources` → no hits |
| 3 | Tests never touch real user font folders | NOT FULLY VERIFIED | the apple-fonts suite is opt-in via `FP_APPLE_FONTS=1` and `SelfTestRunner` uses temporary roots, but no systematic sweep of every test's directory arguments was done |
| 4 | Never look up a font by name in CoreText | PASS | exactly one hit, `FPMacServices/Rendering/LastResort.swift:17`, allow-listed with count 1; `LastResort.make` prefers `CTFontManagerCreateFontDescriptorsFromURL` and only falls back for the SIP-protected LastResort (ADR-0011) |
| 5 | Never commit font files | PASS | no font binaries tracked outside the allow-list in `engine/tests/data/README.md` |
| 6 | No network in tests or build | PASS | no `URLSession` anywhere; no `urllib`/`requests`/`httpx` in `engine/src` or `engine/tests`; only the documented exceptions (`make setup`, `build-helper-runtime.sh`, release scripts) |
| 7 | No silent drops | 2 GAPS | M2 (unreadable → "unsupported"), L3 (depth truncation / failed dir stat unreported). Everything else counted: skipped, unknown events, stderr bytes, folder issues |
| 8 | Atomic file writes | PASS | `AtomicFile.swift` (temp + fsync + `rename`), `CatalogCache.swift:105`, `InstallFileSystem.swift:28,58`; every `try?` in Swift sources is a cleanup/defer path |
| 9 | Protocol changes in one PR | n/a | no protocol change in the reviewed range |
| 10 | Behaviour changes regenerate fixtures | PASS | see rule 1 |
| 11 | No new third-party deps without ADR | PASS | zero SwiftPM package dependencies; engine runtime deps unchanged |
| 12 | No committed generated artefacts | PASS | no `*.xcodeproj`, `build/`, `.venv/`, `.build/`, `dist/` tracked |
| 13 | Bump `READER_VERSION` when scan output changes | PASS | `engine/src/fpengine/face.py:23` = 8, exported by `commands/hello.py:33` as `face_reader_version`, persisted by `CatalogCache.swift:95,108` so a stale cache cannot be read as current |
| 14 | Follow `docs/decisions.md` defaults | not assessed | product-decision conformance needs per-WP reading, out of scope for this pass |

---

## 5. Not covered by this pass

Deliberately out of scope, not "checked and clean":

- Engine module internals beyond what the 457 tests assert: `planner.py`, `prepare.py`, `forge.py`, `kern.py`,
  `merge.py`, `shaping.py`, `synth_bold.py`, `scripts.py`, `naming.py`.
- String Catalog coverage across `FPAppUI` (rule: all user-facing text through the catalog; engine text is the
  documented v1 exception).
- `scripts/sign-app.sh`, `notarize.sh`, `make-dmg.sh`, `codesign-retry.sh`, `check-bundle.sh`, `embed-helper.sh`
  internals (the keychain block in `release.yml` and the pin in `build-helper-runtime.sh` were reviewed).
- `LegacyImport.swift`, `WindowsFonts.swift`, `AppSettings.swift`.
- `FontRenderer` axis pinning and the CoreText run assembly.
- `codex-review.yml` depends on an out-of-repo helper (`CI_CODEX_REVIEW`, "Managed by kciceblue/github-ci") that is
  not reviewable from this checkout — noted, not assessed.

---

## 6. Suggested order of work

1. M1 — measure the Stop stall, then fix the wait's thread and make `cancelAndWait`'s deadline detached.
2. M2 — tri-state format probe, surface `io_error` instead of `.unsupportedFormat`.
3. M3 — serialise the frame-time test locally, or make it opt-in.
4. L1 — scope `contents: write` to the release jobs.
5. L2, L3, L4 — small, self-contained catalog fixes.
6. L5, L6 — document the trade-offs; no code change needed now.

---

## 7. Follow-up (branch `fix/review-2026-10-05`)

Each finding was checked against the code before fixing. Corrections to the text above:

- **M1** is confirmed, not just plausible. Cancelling a main-actor task that iterates an engine stream blocked the main
  thread for 2.17 s with a helper that ignores SIGTERM and for 2 ms with one that exits. The block happens inside
  `cancel()` before the `cancelAndWait` race starts, so detaching the deadline would not have helped. Returning early
  from `onTermination` would end the stream before the child is dead, which breaks AC-204-9/10.
- **M3**: an unloaded parallel `make mac-test` passed, but the scroll p95 was 15.5 of 16.7 ms.
- **L1**: `release.yml` had a single job, so the fix splits out a tag-only `publish` job. The PR run never received
  `GH_TOKEN`; its token was still minted with write scope.
- **L3**: the failed-stat case can only happen if a folder vanishes between two stats.
- **L4**: any refresh, not only a full one, rebuilt `working`.
- **L5**: a folder fsync is possible from Swift with POSIX calls; true power-loss durability on macOS needs
  `F_FULLFSYNC`, deliberately not used.

| Finding | Fix | Regression test |
| --- | --- | --- |
| M1 | `BuildController` cancels its task from a global queue; a superseded run drains its stream instead of dropping it | `BuildControllerTests.reviewM1StopDoesNotWaitOnTheMainThread`, `BuildQuitDeadlineTests.reviewM1QuitDeadlineHoldsWhileTheHelperStops` |
| M2 | `FontDiscovery.probeFormat` returns `.unreadable(errno:)`; reported as `.unreadable` (`io_error` / `not_found`) | `CatalogStoreTests.reviewM2UnreadableFontIsNotUnsupported` |
| M3 | `make mac-test` runs `*PerformanceTests` in a second, serial pass | run of `make mac-test` |
| L1 | workflow `contents: read`; `publish` job (tag pushes, `contents: write`, no repo scripts) drafts the release | `test_review_l1_only_the_tag_job_can_write` |
| L2 | `cancelWaiter` clears `queuedMode` when no queued waiter remains | `CatalogStoreTests.reviewL2CancelledQueuedRefreshDoesNotRun` |
| L3 | depth overflow and failed folder stats become folder issues | `FolderWalkerTests.reviewL3DepthLimitIsReported` |
| L4 | `noteInstalled` drops faces/errors of a replaced path | `CatalogStoreTests.reviewL4NoteInstalledDropsTheReplacedPath` |
| L5 | `AtomicFile` fsyncs the parent folder after the rename | none (not observable in a test) |
| L6 | documented in `docs/self-hosted-ci.md` | none (documentation) |
