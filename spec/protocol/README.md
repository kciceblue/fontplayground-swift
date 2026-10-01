# fpengine helper protocol, version 1

**Normative.** The JSON Schemas in this folder are the contract between the Swift app (`FPEngineClient`) and the Python engine helper (`python -m fpengine`). The prose rules are in `docs/specs/helper.md` ("Shared definitions"), and the decisions are in ADR-0003. The cross-cutting names and shapes come from `docs/specs/contracts.md` §3–§5.

Changing anything here means updating, in one PR: these schemas, `docs/specs/helper.md`, the helper (`engine/src/fpengine/`), the client (`Packages/FontPlaygroundKit/Sources/FPEngineClient/`), the Swift wire types in `FPCore`, the examples in `spec/protocol/examples/`, and the protocol tests (AGENTS.md rule 9).

## Files

| File | Describes |
|---|---|
| `defs.schema.json` | Shared building blocks: paths, group ids, script tags, code-point ranges, stages, error codes |
| `event.schema.json` | **Every stdout line**: the envelope plus the six event types (`hello`, `progress`, `face`, `file_error`, `result`, `error`) |
| `hello.schema.json` | The `hello` event |
| `face-record.schema.json` | `FaceRecord`: one face, the payload of the `face` event (contracts §3 plus `unshaped`) |
| `forge-report.schema.json` | `ForgeReport`: the payload of the forge `result` event |
| `hello-request.schema.json` | stdin of `hello` |
| `scan-request.schema.json` | stdin of `scan` |
| `forge-request.schema.json` | stdin of `forge` (`ForgeRequest`) |
| `examples/` | Example requests and event streams. WP-201 creates them. Every line must validate. The Swift tests decode them |

All schemas are JSON Schema **draft 2020-12**. Their `$id`s use the reserved `.invalid` host (`https://fontplayground.invalid/protocol/1/<file>`). They are identifiers only and are never fetched. Cross-file `$ref`s are relative to them.

## Transport in one screen

```
<python> -I -B -m fpengine <command>        command: hello | scan | forge
stdin   one JSON request object (UTF-8), then EOF
stdout  events, one JSON object per line: UTF-8, '\n'-terminated, no blank lines, flushed per line
stderr  free-form logs; never parsed
exit    0 result sent · 2 bad_request · 3 any other error · 143 cancelled by SIGTERM (no terminal event)
        (also: 130 SIGINT and 141 client closed stdout, both without a terminal event; clients never rely on them)
```

- Every event carries `"protocol": 1` and a `"type"`.
- A run ends with **exactly one** terminal event, `result` or `error`, and nothing follows it. The only exception is a run stopped by a signal.
- Non-terminal events: `hello`, `progress`, `face`, `file_error`.
- The helper writes **only** event lines to stdout. Anything else a library prints goes to stderr.
- **Output objects are strict.** The helper emits exactly the keys in the schemas (`additionalProperties: false`), so the protocol tests catch any undocumented field. Key order is the schema's `required` order, then optional keys in `properties` order; readers must not depend on it. `event.schema.json` therefore rejects unknown event types: it describes what a v1 helper writes, not what a reader must accept. **Readers are lenient.** They ignore keys and event types they don't know. Requests may carry extra keys, and the helper ignores them.
- Integers may be sent as JSON numbers with no fractional part (`700` or `700.0`). Booleans are never accepted as numbers.
- Paths are absolute, standardised POSIX strings (`contracts.md` §2). The helper echoes them unchanged.

## Event sequences

| Command | Sequence |
|---|---|
| `hello` | `hello` → `result{command:"hello"}` |
| `scan` | `progress{stage:"scan",done:0}` → for each distinct file, in request order: its `face` events (face index order) **or** one `file_error` · interleaved throttled `progress` → final `progress{done:total}` → `result{command:"scan", summary}` |
| `forge` | `progress validate` → `plan` → `prepare` ×n (`material_index` 0…n−1) → `merge` → `finish` → `verify` → `done` → `result{command:"forge", report}` |
| any failure | the events so far → `error{code, stage, material_index, message, detail}` |

Cancellation: the client sends SIGTERM. The helper stops at the next Python bytecode boundary, even in the middle of a stage. It removes its temporary files and any partial output, and exits 143 with no terminal event. The client sends SIGKILL if the helper is still running 2 s later (ADR-0003).

## Examples (abridged)

```jsonl
{"protocol":1,"type":"hello","fpengine_version":"0.1.0","python":"3.12.14","fonttools":"4.66.0","unicode_version":"18.0.0","platform":"darwin-arm64","capabilities":["hello","scan","forge","forge.expect"],"face_reader_version":4}
{"protocol":1,"type":"result","command":"hello"}
```

```jsonl
{"protocol":1,"type":"progress","stage":"scan","fraction":0.0,"done":0,"total":2}
{"protocol":1,"type":"face","face":{"path":"/fonts/FixtureSans-Regular.ttf","index":0,"size":10024,"mtime":1790684599.32,"family":"Fixture Sans","style":"Regular","full_name":"Fixture Sans Regular","postscript_name":"FixtureSans-Regular","local_names":[],"outline":"glyf","is_collection":false,"is_variable":false,"axes":[],"weight_class":400,"italic":false,"upem":1000,"glyph_count":241,"coverage":[[32,126],[160,255],[913,929],[931,937],[945,969]],"group_counts":{"latin":191,"greek":49},"embedding":"installable","fs_type":0,"has_color":false,"supported":true,"unsupported_reason":null,"hidden":false,"suspicious_coverage":false,"ot_scripts":{"gsub":[],"gpos":[]},"aat":{"morx":false,"kerx":false,"kern_v1":false,"trak":false},"shapes_groups":[],"licence":{"class":"unknown","vendor_id":null,"notice":null},"has_os2":true,"is_forged":false,"font_revision":"1.000","unshaped":[]}}
{"protocol":1,"type":"file_error","path":"/fonts/NotAFont.ttf","code":"unreadable","message":"Not a font file fontTools can read (TTLibError: Not a TrueType or OpenType font (bad sfntVersion))."}
{"protocol":1,"type":"progress","stage":"scan","fraction":1.0,"done":2,"total":2}
{"protocol":1,"type":"result","command":"scan","summary":{"files":2,"faces":1,"file_errors":1,"duplicates":0}}
```

```jsonl
{"protocol":1,"type":"progress","stage":"validate","fraction":0.0}
{"protocol":1,"type":"error","code":"stale_material","stage":"validate","material_index":1,"message":"/fonts/FixtureCJK-Regular.otf changed since it was scanned (size 81592 → 80000).","detail":null}
```

## Validating in Python (tests)

```python
import json
from pathlib import Path
from jsonschema import Draft202012Validator
from referencing import Registry, Resource
from referencing.jsonschema import DRAFT202012

schemas = [json.loads(p.read_text()) for p in Path("spec/protocol").glob("*.schema.json")]
registry = Registry().with_resources([(s["$id"], Resource(s, specification=DRAFT202012)) for s in schemas])
event_schema = next(s for s in schemas if s["$id"].endswith("/event.schema.json"))
validator = Draft202012Validator(event_schema, registry=registry)
validator.validate(json.loads(line))   # one stdout line
```

The `jsonschema` package is a **dev** dependency of `engine/` only. The helper never imports it at runtime; it validates requests with its own typed parser, which must agree with these schemas.

## Versioning

- `protocol` is an integer. v1 is the only version.
- These changes keep v1: adding an optional request key; adding an output key, event type, stage, error code or capability that readers can ignore (update the schema in the same PR).
- These changes need v2: removing or renaming a key, changing a key's type or meaning, adding a required request key, changing the exit-code meanings.
- The client refuses a helper whose `hello.protocol` differs from the version it supports (`EngineError.incompatibleHelper`).
