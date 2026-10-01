# Dispatching work packages to a coding agent

## 1. One-time setup

Every WP runs on the maintainer's Mac (ADR-0014). Use Codex CLI or Claude Code with Xcode 26+ selected (`xcode-select -p`), `brew install xcodegen uv`, and a clean clone of the repo. Run the agent from the repo root so it picks up `AGENTS.md`. Run `make setup` once with network; the agent's task needs no network after that.

## 2. Prompt template

Paste this as the task, filling in the WP number and spec file:

```text
Implement work package WP-{NNN} in this repository.

1. Read AGENTS.md, docs/architecture.md, docs/testing.md, and the section "WP-{NNN}" in docs/specs/{spec}.md (including the ADRs and audit findings it cites; the audit is docs/research/macos-audit.md).
2. Implement exactly that scope. Do not start other WPs. If something in the spec is ambiguous or wrong, choose the option most consistent with docs/architecture.md, update the spec text, and list the deviation in the PR description.
3. Satisfy every acceptance criterion. Run the verification commands listed in the WP and `make lint test`, and include the output tails in the PR description.
4. Open one PR titled "WP-{NNN}: {title}" from branch wp/{NNN}-{slug}, using .github/pull_request_template.md, with the AC checklist ticked.
```

When the WP touches the app, add: `Also run make app and make self-test.`

## 3. Order and parallelism

The specs are long: they are written for agents, and each WP section is self-contained. Point the agent at its WP section and the spec's "Shared definitions". `docs/specs/README.md` lists every WP with its line range.


Follow the waves in `docs/plan.md` §4. Within a wave, dispatch every WP at once. Before dispatching a WP, check that all of its dependencies are merged into `main`. Codex works from `main`.

## 4. Reviewing a Codex PR (maintainer checklist)

- [ ] Only files in the WP's scope changed (the spec lists the touched paths). No hand-edited fixtures; nothing listed in `spec/fixtures/FROZEN.sha256` changed.
- [ ] Every AC is ticked **and** backed by evidence (test name, command output, or screenshot for manual ACs).
- [ ] CI green (the `macOS` job).
- [ ] No weakened tests (skips, xfails, loosened asserts) without a reason in the PR.
- [ ] Audit regression tests exist for each finding ID the WP closes.
- [ ] For protocol, planner or naming changes: schemas and fixtures regenerated, and both sides updated.
- [ ] Spec deviations are reasonable and reflected in `docs/specs/`.

If the PR misses ACs, reply on the PR with the unmet AC IDs and ask Codex to continue on the same branch. Don't merge partial WPs.

## 5. Status tracking

Optionally open one GitHub issue per WP from `.github/ISSUE_TEMPLATE/work-package.md` and link the PR with `Closes #n`. `docs/plan.md` stays the source of truth for scope and dependencies.
