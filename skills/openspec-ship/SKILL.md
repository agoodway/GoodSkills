---
name: openspec-ship
description: >
  Use when the user runs /openspec-ship, says "ship these openspec changes",
  or asks to implement OpenSpec changes and take them through verify, review,
  archive, commit, and a draft pull request.
---

# Ship OpenSpec changes

You are the orchestrator. You do not rebase, implement, verify, review, archive, commit, or open the pull request yourself. Rebase the current branch onto origin/main once. Then for each change, run the seven steps below in order, revisiting affected steps when recovery invalidates their results. Each step is one subagent. Wait for it to finish before you start the next. After the last change, open one draft pull request for the commits this run made, unless the batch stopped with unfinished edits.

This skill is runtime-neutral. When a step says to start a subagent, use the current runtime's subagent mechanism. If that mechanism is unavailable, run the step in this session and label the result with the step name.

The run is already in the checkout where the work belongs. Do not create or switch branches or worktrees. Every step uses that same checkout, so later steps see earlier files.

Changes run one at a time. Finish or block a change before you start the next.

## Input

```text
/openspec-ship <change> [<change> ...]
```

Also accept a prose list, including "implement the following openspec change(s):" followed by change names.

An optional `--store <id>` applies to every OpenSpec command in the run. Pass it through. When the user names no store, tell each OpenSpec subagent that no store was named so it follows the store rules in the skill it is reading.

When no change name is given, run `openspec list --json` and ask which active changes to ship. That is the only question you ask before starting. A name that is not an active change is reported as not found, and you continue with the remaining names.

## How to start a step

Resolve each dependency before the first step and pass the resolved path to the subagent. Search the runtime's installed skills, project and user skill directories, then this repository's `skills/`. OpenSpec supplies `openspec-apply-change`, `openspec-verify-change`, `openspec-archive-change`, and `openspec-sync-specs`. GoodSkills supplies `goodreview` and `git`. Stop and name any skill you cannot find.

Start one subagent and wait for its result. Do not batch steps.

The prompt stands alone. The subagent does not ask the user. Apply the recovery contract below instead of a named skill's instruction to pause on ordinary errors or ask whether to retry. Questions that require a requirement, scope, or authorization decision remain blockers.

Tell every subagent:

- The change name, and the store id or that no store was named
- To read the named skill at the resolved path and follow it, except for the overrides in that step
- The shared recovery contract and the step's editing restrictions
- To end its final message with the status block for that step

Skills:

- Apply: `openspec-apply-change`
- Verify: `openspec-verify-change`
- Archive: `openspec-archive-change`
- Spec sync, only when the archive skill runs it: `openspec-sync-specs`
- Commit and pull request: `git` (`/git commit`, `/git pr`)
- Review: `goodreview`. If that skill is not available, block the change. Do not invent a review.

Do not advance on `STATUS: blocked` or `STATUS: unfixed`. Inspect the evidence first. If a safe, in-scope recovery remains, continue the same subagent with the missing investigation or repair. Accept a blocker only under the recovery contract.

When the runtime cannot resume a subagent, start a replacement for that same step with the prior report, attempted repairs, and current checkout state. Preserve its no-progress count; a new subagent is not a fresh retry budget.

When a genuine blocker leaves unfinished edits, stop the batch and preserve the checkout. Do not start another change, stash or discard edits, or include unfinished work in another change's commit. Otherwise record the blocker and continue with the next change. Do not open a pull request when the batch stopped with unfinished edits.

The rebase and the pull request are not among these steps. The rebase runs once, before the first change. The pull request runs once, after the last change unless the batch stopped with unfinished edits.

Before the rebase, tell the user `rebase · origin/main`. Before each step, tell the user one line: `<change> · <n>/7 <step name>`. Before the pull request, tell the user `pull request · draft`.

## Shared recovery contract

A failed command is evidence to investigate, not automatically a blocker. Continue while a safe, in-scope next action exists. The orchestrator routes recovery; subagents perform the work within their step's editing restrictions.

- Read actual diagnostics before deciding what to do next. Repair formatting, lint findings, compiler warnings, and implementation-caused test failures within the requested scope.
- Resolve implementation details from specs, code, and established patterns, choosing reasonable reversible implementations. Stop for conflicting requirements, changed product behavior, or expanded scope; never silently narrow specified behavior.
- Repair local environment problems using documented setup and existing permissions. Do not discard work, reset data, or broadly clean dependencies as a shortcut. Confirm missing credentials, permissions, or unavailable dependencies and exhaust safe alternatives before blocking.
- After a timeout or connection failure, inspect whether the operation completed before retrying, especially for archive moves, commits, pushes, and pull request creation. Do not blindly repeat an operation with an unknown outcome.
- Follow repository verification guidance. Run the required full gate at its prescribed checkpoint, then read its logs and rerun failed checks and tests covering repairs. Repeat broader checks only when the repair warrants it. Before archive, confirm the required gate and any repair validation are satisfied.
- Never bypass checks, weaken assertions, drop requirements, or claim an unexecuted check passed. Establish and report unrelated failures without silently expanding scope or claiming the gate passed.
- Continue while attempts produce meaningful new evidence or progress. After three consecutive repair attempts against the same failure without meaningful progress, return a blocker. Repeating an unchanged command is not a repair attempt; do not loop on it.

Return `STATUS: blocked` only when recovery is exhausted, required access is unavailable, or proceeding requires a requirement, scope, or authorization decision. Every blocked result, including rebase and pull request results, adds these fields to its step's status block:

```text
EVIDENCE: <failed operation and decisive diagnostics>
ATTEMPTED: <repairs and their outcomes, or why none is safe>
NEEDED: <decision, access, or other prerequisite>
```

After a repair invalidates earlier evidence, repeat the affected verification or review before advancing. Pass the repair diff and prior report to a focused follow-up of that step, then route any new findings through its fix step. Formatting-only repairs need formatter validation, not a full review. Do not repeat unaffected steps or an entire pipeline by default.

## Rebase

When at least one named change will run, start one subagent before the first change. This step runs once per ship run. When none will run, stop without rebasing.

The prompt does not name a change or a store. Include the shared recovery contract and the restrictions below. This step has no skill. Do not follow the git skill.

Rebase the current branch onto the latest `origin/main`. Check that the tree is clean, fetch `origin`, then run `git rebase origin/main`. Do not switch branches, do not create a worktree, do not stash, do not use an interactive rebase, do not push, and do not ask.

- A clean rebase, a fast-forward, or an already up-to-date branch is `STATUS: done`.
- A dirty tree, a missing `origin/main`, or a rebase conflict is `STATUS: blocked`. Abort a conflicted rebase before returning, so the checkout is back to where it started.
- When this step is blocked, stop the run. Do not start a change and do not open a pull request.

```text
STATUS: done|blocked
SUMMARY: <the commit now at HEAD, or the blocker>
```

## Steps

### 1. Apply

Follow `openspec-apply-change` for this change. Implement every remaining task.

Overrides: do not archive, do not commit, and do not ask. Ordinary implementation and validation errors use the recovery contract rather than immediately pausing. Resolve implementation details from existing artifacts and patterns; requirement conflicts, design decisions that change specified behavior, and extra scope remain blockers. `all_done` with nothing left to implement is `STATUS: done`, but is not proof that validation passed.

```text
STATUS: done|blocked
SUMMARY: <tasks completed this run, or the blocker>
```

### 2. Verify

Follow `openspec-verify-change` for this change. Do not edit files, do not archive, and do not fix issues. Issues are not a blocker. A report is `STATUS: done`. Recover operational failures within these read-only restrictions; put code and artifact defects in the report for step 3. Failure to produce the report after recovery is `STATUS: blocked`.

Paste the skill's full verification report, then:

```text
STATUS: done|blocked
```

### 3. Fix every verify issue

Pass this subagent the verify report unchanged. Do not summarize it first.

An issue is every item the report lists under CRITICAL, WARNING, and SUGGESTION. Count those items and put `Expected issue count: N` in the prompt. Zero items is a successful no-op.

The subagent fixes every item. It does not drop, defer, or re-rank any item. When the current code already matches the recommendation, it says so and counts that item as fixed. Rerun the checks that establish each item is resolved and report validation evidence. When it cannot fix an item after recovery, it returns `STATUS: unfixed`, includes the blocker evidence fields for unresolved items, and does not claim done. The orchestrator assesses this result under the recovery contract.

```text
STATUS: done|unfixed|blocked
ISSUES: <N>
FIXED:
- <issue> — <what changed, or already in place>
UNFIXED:
- <issue> — <why>
```

`ISSUES` must equal the expected count. `done` requires `UNFIXED` to be empty and one `FIXED` line per issue. When a `done` result does not satisfy this, continue the same subagent and name the missing items; use the recovery contract's no-progress limit rather than accepting an incomplete report. If a repair invalidates the original verification evidence, obtain focused verification in step 2 and resolve new findings here before advancing.

### 4. Review

Follow the `goodreview` skill on the uncommitted changes. Do not edit, commit, or create issues.

If this subagent cannot spawn its own subagents, it uses the sequential fallback already in that skill and still returns the full report.

A report is `STATUS: done` even when its verdict is not `Ship`. Recover reviewer or tool failures within this step's read-only restrictions. Failure to produce the report after recovery is `STATUS: blocked`; do not invent a completed review.

Paste the full goodreview report, then:

```text
STATUS: done|blocked
```

### 5. Fix every review issue

Same contract as step 3, for every numbered item under Findings, confirmed or plausible. Pass the goodreview report unchanged, with `Expected issue count: N`.

Obtain focused re-review in step 4 for substantive repairs and resolve new findings here. Repeat affected spec verification through steps 2 and 3 when behavior changes. This subagent must confirm required validation evidence or run missing validation before advancing to archive, even when the review has zero issues. Recover any validation failures under the shared contract.

### 6. Archive, syncing specs first

Follow `openspec-archive-change` for this change. The decisions below are already made. Do not ask, and do not offer another choice.

- When delta specs exist and sync is not blocked, sync first, in this subagent, by the archive skill's inline sync. Wait until the sync's own verification passes, then archive.
- Repair mechanical sync failures under the recovery contract. A substantive spec conflict is `STATUS: blocked`; do not move the change or silently decide new requirements.
- When there are no delta specs, archive without syncing.
- Do not archive past incomplete artifacts or tasks. Report incomplete implementation to the orchestrator, which routes it back through apply and the affected later steps. Missing planning decisions remain blockers.
- After an interrupted archive, inspect the source and destination before retrying. Report an already completed move rather than archiving it again.

Do not commit or push.

```text
STATUS: done|blocked
SUMMARY: <archive path and whether specs were synced, or the blocker>
```

### 7. Commit

Follow `/git commit` in the git skill.

Overrides: make one commit for this change and stop. The commit includes the implementation, the synced specs, and the archive move. The subject names the change. Do not push, do not open a pull request, and do not ask whether to.

Recover in-scope commit failures by reading diagnostics, repairing the cause, and rerunning affected checks before retrying. Behavioral repairs return through affected verification and review before committing. If a repair is needed after archive, use the archived artifacts as context; do not reapply the archive move. Inspect HEAD before retrying an uncertain commit result. A dirty tree you cannot commit after recovery is `STATUS: blocked`.

```text
STATUS: done|blocked
COMMITS: <sha> <subject>
```

## Pull request

After every named change has finished or blocked, start one subagent, unless the batch stopped with unfinished edits. This step runs once per ship run.

The prompt names every change in the run and the commit each one made. It does not name a store.

Follow `/git pr` in the git skill.

Overrides:

- The pull request contains every commit this run made.
- The tree must already be clean. A dirty tree is `STATUS: blocked`. Do not make another commit.
- When every change blocked before a commit, do not open a pull request. Return `STATUS: blocked` and say that this run made no commits.
- Otherwise push and open one draft pull request. Put the pull request URL on its own line.
- Use the recovery contract for operational failures. Inspect remote branch and pull request state before retrying uncertain pushes or pull request creation; reuse an already created pull request rather than opening a duplicate. Do not force-push or change authorization to recover.

```text
STATUS: done|blocked
PR_URL: <url, or none>
```

## Finish

After the pull request step, summarize in chat:

- The pull request URL, or why it was not opened
- For each change: done, or the step that blocked and the reason
- Verify issues fixed, and review issues fixed
- Validation results, any accepted unrelated failures, and any changes not started because the batch stopped

When the rebase blocked or the batch stopped with unfinished edits, summarize that blocker and the actual delivery state, including commits already made and why no pull request was opened. Do not paste the verify or goodreview reports again.
