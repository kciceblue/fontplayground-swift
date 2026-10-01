# Conformance generator

Run `make conformance` from the repository root, then review and commit both
`spec/fixtures/` and `Packages/FontPlaygroundKit/Sources/FPCore/Generated/`.
`make conformance-check` regenerates and rejects changed or untracked output.

For an isolated run, start from a copy of the committed fixtures, because the
frozen files below cannot be regenerated:

```sh
cp -R spec/fixtures /tmp/fp-conformance
uv run --project engine --frozen python tools/conformance/generate.py \
  --out /tmp/fp-conformance --swift-out /tmp/fp-swift-table
```

No network is used.

`--only scripts|planner|naming|shaping` limits regeneration to that
category and the scripts prerequisite. The Swift table always reads script JSON
written by the same run. Stale JSON is deleted only in selected owned folders.
The shaping folder is owned by WP-107; this generator calls its writer when
available and prints an explicit skip before that module exists.

Output uses deterministic ordering, seed 20260929, scalar arrays on one line,
and atomic replacement. Identical bytes preserve mtimes. Headers capture actual
runtime versions, using only Python's major.minor version.

The language, text and family-name fixtures were generated from the original
app's Qt-free UI modules until WP-701 removed `reference/` at v1.0.0. They are now
frozen: `spec/fixtures/FROZEN.sha256` lists exactly those six files, and every run
checks them before writing anything. A missing manifest, a missing or dropped
entry, or a changed byte fails with `conformance: frozen fixture changed: <path>`.
The generator never writes or deletes a frozen file. If a frozen fixture is wrong,
fix the Swift port in a bug WP; don't regenerate or hand-edit it.

`uv run --project engine --frozen python -m fpengine.testing.make_fonts <directory>`
creates the nine synthetic fonts and `fonts.json` consumed by helper and Swift
tests. Its only stdout line is the absolute manifest path. Font files are made
at runtime and must never be committed.
