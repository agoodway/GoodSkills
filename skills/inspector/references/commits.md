# inspector commits

Analyze recent git commits to detect code changes that have drifted from — or aren't yet reflected in — the OpenSpec specs and active changes. Surfaces commits that may require spec updates, new change proposals, or delta revisions.

This is a read-only inspection. The only file written is the report at `openspec/inspector-commits.md` (project-level, not per-change).

## Inputs

- **No args**: `/inspector commits` — analyzes commits since the last run (reads the `last-run` date from an existing report, or defaults to 20 commits).
- **Count**: `/inspector commits 50` — analyzes the last N commits.
- **Range**: `/inspector commits abc123..def456` — analyzes a specific commit range.
- **Since**: `/inspector commits --since 2026-04-01` — analyzes commits since a date.

## Workflow

### 1. Gather commits

Run `git log --oneline --name-status <range>` to get the commit list with changed files. Exclude:
- Commits that only touch `openspec/` (spec-only changes don't need spec updates)
- Merge commits (analyze the individual commits instead)
- Commits with messages containing `[no-spec]` or `[trivial]` (opt-out convention)

Collect for each commit: hash, message, author, date, and list of added/modified/deleted files with their paths.

### 2. Load OpenSpec state (parallel)

In parallel, read:
- **All canonical specs**: `openspec/specs/*/spec.md` — the current contract for each capability
- **All active changes**: for each dir in `openspec/changes/` (minus `archive/`), read `proposal.md` and `tasks.md`
- **Previous report**: `openspec/inspector-commits.md` if it exists (to extract the `last-run` date and avoid re-flagging already-reviewed commits)

Build a map of: capability → files/modules it covers (derived from spec content and delta specs mentioning specific paths).

### 3. Dispatch parallel analysis specialists

Launch two specialists in parallel with commit list and spec content inlined in their briefs. Use the current runtime's subagent mechanism when available; otherwise run the briefs directly and keep the outputs separate.

**Specialist A — Spec drift detection**
- Receives: commit list with changed files, all canonical spec contents (inlined).
- For each commit, check:
  - Do the changed files fall within a capability's scope? (Match file paths against modules/schemas/contexts mentioned in specs)
  - Does the commit message suggest behavioral change (new feature, API change, schema migration, config change) vs. internal refactor?
  - Does the change contradict, extend, or modify behavior described in a canonical spec's requirements/scenarios?
- Return findings as: `commit-hash | file:path | capability | drift-type (extends|contradicts|unreflected) | summary`

**Specialist B — Active change alignment**
- Receives: commit list with changed files, all active change proposals and tasks (inlined).
- For each commit, check:
  - Is this commit implementing work described in an active change's tasks? If so, is the corresponding task checked off?
  - Does this commit introduce work that overlaps with an active change but isn't tracked in its tasks?
  - Does this commit modify files that an active change's proposal assumes are in a certain state?
- Return findings as: `commit-hash | file:path | change-id | alignment-type (untracked-work|stale-assumption|missing-task) | summary`

### 4. Synthesize

Merge findings from both agents. Group by type:

- **Spec drift** — commits that changed behavior covered by a canonical spec but the spec hasn't been updated. These need a new change proposal or a delta spec added to an existing change.
- **Untracked work** — commits implementing features/fixes not covered by any active change. These may need a retroactive change proposal.
- **Stale assumptions** — commits that invalidate assumptions in an active change's proposal or design. The active change needs revision.
- **Missing task checkoffs** — commits that implement work described in an active change's tasks, but the tasks aren't checked off. Minor housekeeping.

Assign severity:
- **Critical** — commit contradicts a canonical spec or breaks an active change's assumptions
- **Warning** — commit extends behavior without spec coverage, or significant untracked work
- **Suggestion** — missing task checkoffs, minor scope drift, refactors near spec-covered code

### 5. Write the report

Write to `openspec/inspector-commits.md`:

```markdown
# Inspector Commits Report

**Run date:** <YYYY-MM-DD>
**Range:** <commit range or "last N commits">
**Commits analyzed:** <N>
**Commits flagged:** <N>

**Counts:** Critical: N · Warning: N · Suggestion: N

## Spec Drift

Commits that changed spec-covered behavior without a corresponding spec update.

| Severity | Commit | File | Capability | Summary | Suggested action |
|----------|--------|------|------------|---------|------------------|
| Warning  | `abc123` | `lib/accounts/user.ex` | user-auth | Added email verification field | Create change or add delta to `user-auth` spec |

## Untracked Work

Commits not covered by any active change.

| Severity | Commit | Files | Summary | Suggested action |
|----------|--------|-------|---------|------------------|
| Warning  | `def456` | `lib/billing/*.ex` | New billing module | Consider retroactive change proposal |

## Stale Assumptions

Commits that invalidate assumptions in active changes.

| Severity | Commit | File | Change | Assumption broken | Suggested action |
|----------|--------|------|--------|-------------------|------------------|
| Critical | `789abc` | `lib/api/router.ex` | `add-webhooks` | Proposal assumes v1 router structure | Revise proposal to reflect v2 router |

## Missing Task Checkoffs

Commits that appear to implement active change tasks not yet checked off.

| Commit | Change | Likely task | Suggested action |
|--------|--------|-------------|------------------|
| `aaa111` | `add-search` | 2.3 Add full-text index | Check off task in `tasks.md` |

## Commits Not Flagged

<N> commits were analyzed and found to be internal refactors, test-only changes, or documentation updates with no spec impact.
```

### 6. Summarize in chat

Print to chat:
- Counts by severity
- Critical findings inline (one line each)
- Path to the full report
- One-sentence verdict: "specs are current" / "N items need attention"

## Guardrails

- **Read-only on OpenSpec**: never modify specs, proposals, tasks, or deltas. Only writes its own report file.
- **No git commits, no branch changes**: pure audit.
- **Conservative flagging**: when in doubt whether a commit affects spec-covered behavior, classify as Suggestion rather than Warning. Refactors that don't change behavior should not be flagged.
- **Respect opt-out**: commits with `[no-spec]` or `[trivial]` in the message are skipped entirely.
- **Cite commit:file for every finding** — vague findings without a specific commit and file path should be dropped.
- **Don't flag openspec-only commits**: changes to spec files themselves don't need spec updates.
