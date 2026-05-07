# inspector reconcile

Reconcile an OpenSpec change's artifacts against the **current codebase state**. Detects where the codebase has moved beyond, diverged from, or already implemented what the change describes — then patches the change artifacts to match reality.

Unlike `review` (read-only audit) or `review-update` (fixes spec-internal issues), `reconcile` focuses on **codebase → spec drift**: things the code does that the specs don't reflect, things the specs claim that the code contradicts, and tasks that are already done but unchecked.

## Inputs

- **Arg form**: `/inspector reconcile <change-id>` — use the provided change ID directly.
- **No arg**: list active changes (`ls openspec/changes/` minus `archive/`) and ask the user which to reconcile.
- If the given change-id doesn't exist under `openspec/changes/`, stop and report.

## Workflow

### 1. Pre-read all change artifacts (parallel)

Read everything from `openspec/changes/<change-id>/`:
- `proposal.md`
- `design.md` (if present)
- `tasks.md`
- All delta specs under `specs/<capability>/spec.md`
- Canonical specs for each touched capability: `openspec/specs/<capability>/spec.md`

Also read:
- `openspec/changes/<change-id>/.openspec.yaml` (if present — for metadata/status)
- Recent git log for the change dir: `git log --oneline -20 -- openspec/changes/<change-id>/`

### 2. Dispatch parallel codebase analysis specialists

Launch specialists **in parallel** to analyze different dimensions of codebase alignment. Use the current runtime's subagent mechanism when available; otherwise run the briefs directly and keep outputs separate. **Inline the pre-read file contents into each specialist's brief** so they start immediately.

**Specialist A — Implementation status**
- Receives: `tasks.md` and all delta specs inlined.
- For each task and subtask in `tasks.md`, explore the codebase to determine:
  - **Done**: the implementation exists and matches what the task describes. Cite the file:line where the implementation lives.
  - **Partial**: some but not all of the task is implemented. Describe what exists and what's missing.
  - **Not started**: no evidence of implementation.
  - **Superseded**: the codebase has a different approach than what the task describes (e.g., different module name, different pattern).
- For each delta spec requirement and scenario, verify whether the codebase already satisfies it.
- Return findings as: `task-ref | status (done|partial|not-started|superseded) | file:line evidence | notes`

**Specialist B — Spec accuracy**
- Receives: `proposal.md`, `design.md`, and all delta specs inlined.
- For each concrete claim the change makes about the codebase, verify it:
  - File paths and module names mentioned in specs — do they exist? Have they been renamed?
  - Schema fields, associations, and types — do they match what the spec says?
  - Function signatures and behavior — does the code match?
  - Config keys, env vars, routes — do they exist as described?
- Also scan for **undocumented implementation**: code that clearly belongs to this feature but isn't reflected in any spec or task.
- Return findings as: `artifact:line | claim | actual-state | drift-type (stale-path|renamed|already-exists|missing-from-spec|wrong-signature) | suggested-update`

### 3. Classify and plan patches

Merge findings from both agents. Classify each into:

**Auto-patch** — changes that have a single correct answer:
- Task checkboxes: mark tasks as done (`- [ ]` → `- [x]`) when Specialist A found implementation evidence
- Stale file paths in specs: update to current path
- Stale module/function names: update to current name
- Missing implementation details in specs that the code already defines (add the actual schema fields, actual function signature, etc.)

**Needs-question** — changes that require human judgment:
- Task describes approach X but codebase uses approach Y (superseded) — ask whether to update the task or the code
- Spec requirement that the codebase contradicts — ask which is correct
- Undocumented implementation found — ask whether to add it to the spec or if it's unrelated
- Design decision in `design.md` that the codebase diverged from — ask whether to update the design doc

**Info-only** — things to note but not patch:
- Tasks correctly marked as not-started with no implementation found
- Specs that match the codebase accurately

### 4. Apply auto-patches

For each auto-patchable finding, in order:
1. Read the target artifact file
2. Apply the edit using the runtime's edit capability
3. Log what was changed

Group related patches by file. Apply task checkbox updates in `tasks.md` in a single pass when possible.

### 5. Ask about questions

For each needs-question finding, use the runtime's question mechanism to present:
- What the spec/task says vs. what the codebase shows
- The specific artifact line and the codebase file:line
- Clear options for resolution

Apply patches based on user answers. If the user says "skip", leave unpatched.

### 6. Write the report

Write to `openspec/changes/<change-id>/inspector-reconcile.md`:

```markdown
# Inspector Reconcile — <change-id>

**Reconciled:** <YYYY-MM-DD>
**Verdict:** <Fully aligned | Partially aligned | Significant drift>

## Summary

<2-4 sentences: what was found, how much drift, what was patched.>

**Counts:** Auto-patched: N · User-guided: N · Skipped: N · Already aligned: N

## Implementation Status

Summary of task completion state after reconciliation:

| Task | Status | Evidence |
|------|--------|----------|
| 1.1 Add migration | Done ✓ | `priv/repo/migrations/2026...` |
| 1.2 Create schema | Partial | Schema exists at `lib/...`, missing `foo` field |
| 2.1 Add LiveView | Not started | — |

## Patches Applied

### Auto-patched
1. **<title>** — `artifact:line` → <what changed>

### User-guided
1. **<title>** — `artifact:line` → <what changed> (user chose: <decision>)

### Skipped
1. **<title>** — `artifact:line` → <why skipped>

## Remaining Drift

Findings that were not patched and still represent misalignment between specs and codebase.

1. **<title>** — `artifact:line` vs `code:line`
   - **Spec says:** <X>
   - **Code does:** <Y>
   - **Impact:** <what breaks if not reconciled>

## What's Aligned

<Bulleted list of areas where specs accurately describe the codebase.>
```

### 7. Summarize in chat

Print to chat:
- Implementation status overview (N done, N partial, N not started)
- Patch counts (auto, user-guided, skipped)
- Any remaining drift items
- Path to the report
- Verdict

## Guardrails

- **Modifies OpenSpec artifacts only**: edits proposals, tasks, design docs, and delta specs to match the codebase. Does NOT modify source code.
- **No td issues, no git commits, no branch changes**: reconcile is a spec-alignment pass, not an implementation step.
- **Conservative auto-patching**: only auto-patch when there's a single correct answer (checkbox updates, path corrections). When there's a judgment call, ask.
- **Cite both sides**: every finding must cite the artifact location AND the codebase location so the user can verify.
- **Verify before patching**: grep/read to confirm codebase state before updating a spec. Don't trust agent findings blindly.
- **Scope to this change**: do not edit artifacts outside the change's directory.
- **Atomic questions**: ask one question at a time.
- **Preserve intent**: when updating specs to match code, preserve the original requirement's intent. If the code implements the same goal differently, update the "how" but keep the "what" and "why".
