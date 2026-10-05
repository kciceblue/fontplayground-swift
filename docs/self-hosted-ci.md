# Self-hosted CI and Codex review

This repository uses the shared personal-account fleet managed in
the maintainer's private `kciceblue/github-ci` repository.

- macOS and Codex review: Mac mini, one shared job slot across repositories. CI runs on macOS only (ADR-0014).
- Label: `[self-hosted, macOS, ARM64, kcice-ci, kcice-build]`.
- Python remains pinned to 3.12.

The original Make targets, PR checks, release signing, and artifacts are preserved.

The macOS job sets `SWIFT_TEST_FLAGS=--no-parallel` and leaves `FP_PERF_FACTOR`
unset, because CPU-bound timings on the Mac mini match a developer Mac. Timers in
fleet jobs are coarse, though. The WP503 scroll test's 16 ms sleeps stretched each
step to about 145 ms, which the earlier dedicated runner did not show. Tests must
not depend on sleep precision ([testing](testing.md) §3).

Release signing passes two passwords on `security` command lines, where any
local account can read them with `ps` while the command runs: the throwaway
keychain password (random per run) and `MACOS_DEVELOPER_ID_P12_PASSWORD`
(`security import -P`, which has no non-interactive way to read it from stdin
or a file). That is acceptable while this Mac mini runs only the maintainer's
jobs, one at a time. Before other people's jobs or accounts share it, move
release signing to a dedicated runner (review 2026-10-05 L6).

Codex reviews use the maintainer's existing subscription, read-only execution,
and one advisory PR comment. Automatic cloud reviews remain disabled globally.
Fork PRs cannot run on the private hosts. GitHub artifact storage and OpenAI
model usage still apply.

See the fleet repository for service paths, automatic enrollment, isolated workspaces,
logs, maintenance, and rollback. The Mac service starts at login after reboot.
The earlier dedicated fontplayground runner services are retired.
