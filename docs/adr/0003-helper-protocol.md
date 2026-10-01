# ADR-0003: Helper protocol: JSON Lines over stdio, one process per request

- **Status:** accepted (2026-09-29)
- **Evidence:** audit `NATIVE-3` (Swift ↔ Python JSON Lines prototype worked end to end), `ENGINE-9`, `NATIVE-7`

## Decision
- `python -m fpengine <command>` reads **one** request JSON object from stdin and writes **events** to stdout, one JSON object per line (UTF-8, `\n`). Logs go to stderr and are never parsed.
- Every event carries `"protocol": 1` and a `"type"`. Each run ends with exactly one terminal event, `result` or `error`, unless the process is killed.
- Commands in v1: `hello`, `scan`, `forge`. The schemas in `spec/protocol/` are normative.
- Cancel: the client sends SIGTERM. The helper stops at the next checkpoint, removes its temporary files and exits with 143, without a terminal event. The client sends SIGKILL after 2 s.
- There is one process per request. There is no long-lived helper in v1.

## Consequences
- Forge memory (0.7–0.95 GB) is isolated, and cancel is prompt.
- Startup cost (about 150–400 ms including fontTools import) is paid for each request. That is acceptable for scan and forge, and the preview never needs the helper.
