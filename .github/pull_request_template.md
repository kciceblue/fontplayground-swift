## WP-NNN: <title>

Spec: `docs/specs/<file>.md#wp-nnn`

### Summary
<!-- What changed and why, in a few lines. -->

### Acceptance criteria
<!-- Copy every AC from the spec. Tick each one and point to the evidence (test name, command output, screenshot). -->
- [ ] AC-NNN-1 …
- [ ] AC-NNN-2 …

### Verification output
```text
<!-- tails of: make lint / make test / WP-specific commands -->
```

### Audit findings closed
<!-- e.g. ENGINE-1 (regression test: test_engine_1_mac_unicode_cmap) -->

### Spec deviations
<!-- None, or: what, why, and the spec text updated in this PR. -->

### Checklist
- [ ] Only in-scope paths changed; no hand-edited or frozen fixtures changed
- [ ] No real user font folders or app folders touched by tests; no name-based CoreText lookups
- [ ] Protocol / fixtures regenerated if planner, naming, scripts or protocol changed
