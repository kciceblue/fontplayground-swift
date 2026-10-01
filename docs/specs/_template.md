# <Spec title>

> Scope: WP-NNN, WP-NNN… · Architecture refs: docs/architecture.md §x · ADRs: 000x

## Context
Why this area exists, what the original app did (with `reference/fontplayground-py/...:line` pointers), and what the audit found (finding IDs).

## Shared definitions
Types, names, file formats and constants that more than one WP in this spec uses. Normative.

---

## WP-NNN: <title>

**Goal:** one sentence.
**Depends on:** WP-… · **Size:** S|M|L · **Closes findings:** ENGINE-1, …

### Scope
- In: …
- Out: … (and where it is handled instead)

### Touched paths
- `engine/src/fpengine/...` (new|edit)
- `engine/tests/...` (new)

### Design
Interfaces (signatures), data shapes, algorithms, edge cases, error handling, user-facing strings. Enough detail that an agent can implement without guessing. Non-normative reference code, if any, is marked as such.

### Acceptance criteria
Each AC is independently verifiable, with a stable ID.
- **AC-NNN-1** Given …, when …, then … (verified by `test_…` in `…`)
- **AC-NNN-2** `make engine-test` passes, including the new tests …
- **AC-NNN-M1** (manual, macos) … screenshot attached to the PR

### Verification
```bash
make engine-test
```

### Notes for the implementer
Pitfalls, audit evidence to reread, things not to do.
