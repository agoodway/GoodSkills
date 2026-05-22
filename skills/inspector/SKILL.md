---
name: inspector
description: Inspect OpenSpec artifacts for gaps, correctness, consistency, and alignment with other specs/changes and the current codebase. Dispatches subcommands via `/inspector [subcommand] [args]`. Use when the user says "/inspector review", "inspector review", "inspect change", "review the openspec change", "audit the spec", "/inspector review-update", "review and fix", "review and patch", "inspect and fix", "/inspector sync-linear", "sync change to linear", "create linear issue for change", "/inspector commits", "check commits against specs", "are specs up to date", "/inspector reconcile", "reconcile change", "update change from codebase", "sync specs to code", "reconcile specs", "/inspector explain", "explain change", "explain the change", "what does this change do", "/inspector mockups", "mock up the UI", "generate mockups", "ascii mockups", "wireframe the change", "/inspector flows", "diagram the flows", "generate flow diagrams", "process diagrams", "workflow diagrams", "/inspector review-work", "verify and review", "verify and fix", "review work and fix", or asks to sanity-check, critique, find gaps, sync with Linear, detect spec drift from recent commits, update a change to match what's actually implemented, explain/visualize a change, generate UI mockups or process flow diagrams, or verify implementation and fix review findings.
---

# Inspector

Multi-subcommand skill for inspecting OpenSpec artifacts. Dispatch to the correct subcommand based on the user's invocation.

This skill is runtime-neutral and works in Claude Code, OpenCode, and Codex. When a referenced workflow says to use an Agent, Task, Explore agent, AskUserQuestion, Read, Edit, or Write tool, use the equivalent capability in the current runtime. If a named subagent is unavailable, run that specialist prompt directly and label the result with the intended role.

## Runtime Compatibility

| Concept | Claude Code | OpenCode | Codex |
|---|---|---|---|
| Parallel specialists | Task/Agent subagents | Task subagents from `agents/opencode/` when available | Spawn custom agents from `agents/codex/` when available |
| Codebase exploration | Explore/finder-style agent when available | `explore` subagent or direct Glob/Grep/Read | `explorer` or direct search/read |
| User questions | `AskUserQuestion` | question tool | Ask directly in the conversation |
| File edits | Edit/Write | apply_patch/edit/write | apply_patch/edit/write |

Prefer direct Glob/Grep/Read over broad shell scans when the runtime provides those tools.

## Subcommands

| Subcommand | Purpose | Reference |
|------------|---------|-----------|
| `review`   | Audit an OpenSpec change for gaps, correctness, consistency, and codebase alignment | [references/review.md](references/review.md) |
| `review-update` | Quick review then auto-patch fixable findings, ask user about the rest | [references/review-update.md](references/review-update.md) |
| `sync-linear` | Sync an OpenSpec change to a Linear issue (create or update) | [references/sync-linear.md](references/sync-linear.md) |
| `commits` | Detect recent commits that require OpenSpec spec/change updates | [references/commits.md](references/commits.md) |
| `reconcile` | Update a change's artifacts to match the current codebase state | [references/reconcile.md](references/reconcile.md) |
| `explain`  | Explain a change with prose, ASCII diagrams, and ASCII mockups | [references/explain.md](references/explain.md) |
| `mockups`  | Generate detailed ASCII mockups of all UI proposed in a change | [references/mockups.md](references/mockups.md) |
| `flows`    | Generate ASCII diagrams of all process workflows in a change | [references/flows.md](references/flows.md) |
| `review-work` | Verify implementation, run code review, and fix all findings | [references/review-work.md](references/review-work.md) |

### `/inspector help`

Display a list of all available subcommands. Output the following exactly:

```
/inspector subcommands:

  review [change-id]        — Audit a change for gaps, correctness, consistency, and codebase alignment
  review-update [change-id] — Quick review then auto-patch fixable findings
  sync-linear [change-id]   — Sync a change to a Linear issue (create or update)
  commits                   — Detect recent commits that require spec/change updates
  reconcile [change-id]     — Update a change's artifacts to match the current codebase
  explain [change-id]       — Explain a change with prose, ASCII diagrams, and mockups
  mockups [change-id]       — Generate detailed ASCII mockups of all UI in a change
  flows [change-id]         — Generate ASCII diagrams of all process workflows
  review-work [change-id]   — Verify implementation, review code, and fix all findings
  help                      — Show this help message
```

More subcommands will be added over time. If `/inspector` is invoked without a subcommand, show the help output above and ask which to run.

## Dispatch

1. Parse the subcommand and args from the user's invocation. Examples:
   - `/inspector review` → subcommand `review`, no args
   - `/inspector review buyer-outbound-frequency-caps` → subcommand `review`, arg `buyer-outbound-frequency-caps`
2. If the subcommand is unknown, list available subcommands from the table above and stop.
3. Read the matching reference file from `references/` and follow its workflow exactly.
4. Pass any remaining arguments through to the subcommand.

## Conventions shared across subcommands

- **OpenSpec layout**: changes live in `openspec/changes/<change-id>/` with `proposal.md`, `tasks.md`, optional `design.md`, and delta specs at `specs/<capability>/spec.md`. Canonical specs live in `openspec/specs/<capability>/spec.md`.
- **Read-only on OpenSpec files**: never modify proposals, deltas, or tasks during inspection. Inspector only writes its own report artifacts. Exception: `review-update` and `reconcile` explicitly modify change artifacts as part of their workflow. `review-work` modifies codebase files (not OpenSpec files) to fix review findings.
- **Report location**: write reports to `openspec/changes/<change-id>/inspector-<subcommand>.md` so they travel with the change and get archived with it.
- **Cite file:line** for every concrete finding so the reader can jump to the source.
- **Severity tiers**: Critical (blocks implementation/archiving), Warning (should fix before landing), Suggestion (nice-to-have).
