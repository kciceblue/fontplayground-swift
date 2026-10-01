# Font Playground engine

`fpengine` is Font Playground's platform-neutral Python helper. It reads font
faces, plans character assignments and forges merged fonts with fontTools. The
native macOS app runs it in a separate process; the helper has no Qt or AppKit
dependency.

From this directory, `uv sync --frozen` installs the locked Python 3.12
environment, and `uv run --frozen pytest -q` runs the engine tests. The repository
entry points are `make setup` and `make engine-test`.

The engine and its synthetic-font tests are imported from the read-only reference
app without changing their behavior. WP-201 adds `python -m fpengine` and the
helper protocol.

| Module | Responsibility | Reference source |
|---|---|---|
| `face` | Read font faces and their metadata | `fontplayground/catalog/face.py` |
| `records` | Convert face values to and from JSON-ready dictionaries | Pure conversion helpers in `fontplayground/catalog/cache.py` |
| `scripts` | Map Unicode code points to script groups | `fontplayground/engine/scripts.py` |
| `spec` | Forge inputs, validation, plans, reports and errors | `fontplayground/engine/spec.py` |
| `planner` | Assign each character to a material | `fontplayground/engine/planner.py` |
| `prepare` | Subset, instantiate, convert and scale font parts | `fontplayground/engine/prepare.py` |
| `kern` | Convert legacy kerning to OpenType positioning | `fontplayground/engine/kern.py` |
| `synth_bold` | Embolden outlines and adjust advances | `fontplayground/engine/synth_bold.py` |
| `merge` | Merge parts, finish metadata and verify the result | `fontplayground/engine/merge.py` |
| `forge` | Orchestrate a complete forge run | `fontplayground/engine/forge.py` |

Swift owns font discovery and catalog persistence. The engine has no scanner,
platform font-folder policy or cache file I/O. Its `records` module preserves the
reference face dictionary layout, including sorted inclusive code-point ranges.

See [the architecture](../docs/architecture.md), [the helper protocol
specification](../docs/specs/helper.md) and [the test strategy](../docs/testing.md).
