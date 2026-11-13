---
name: openspec-ship-tickets
description: Ship the tickets openspec-to-tickets created, one pipeline per ticket (apply, verify, fix, review, fix, commit), serially with subagents or in parallel child threads/orbs, then archive finished changes and open one draft pull request.
disable-model-invocation: true
---

# Ship OpenSpec tickets

You are the orchestrator. You ship the **tickets** that `openspec-to-tickets` published for one or more OpenSpec changes. Each ticket runs through the **ticket pipeline** below and lands as one commit on the **run branch** (the branch checked out when the run starts). When a change's last ticket lands, you close the change out: full verify, archive, commit. After the last ticket, you open one draft pull request.

You do not rebase, implement, verify, review, archive, commit, or open the pull request yourself. Each of those is one subagent (or, in thread mode, one child). You schedule tickets, route recovery, and own every tracker write.

This skill is runtime-neutral. When a step says to start a subagent, use the current runtime's subagent mechanism. If that mechanism is unavailable, run the step in this session and label the result with the step name.

Do not create or switch branches or worktrees in default mode. Every step uses the same checkout, so later steps see earlier files.

## Input

```text
/openspec-ship-tickets <change|ticket> [...] [--threads] [--parallel <n>] [--store <id>]
```

- A **change** name means every open ticket listed in `openspec/changes/<change>/tickets.md`.
- A **ticket** reference (`#12`, `ENG-123`, `PROJ-7`, `<change>#03`) means that ticket alone. Find its change by searching the `tickets.md` files.
- With no argument, list active changes that have a `tickets.md` (`openspec list --json`, then check each change directory) and ask which to ship. That is the only question you ask before starting.
- A name with no `tickets.md`, or a reference no index lists, is reported as not found; continue with the rest. Point the user at `/openspec-to-tickets` for an unticketed change.
- `--store <id>` applies to every OpenSpec command in the run. Pass it through. When no store is named, tell each OpenSpec subagent so, so it follows the store rules in the skill it reads.
- `--threads` selects thread mode; `--parallel <n>` caps its concurrent children (default 3). See **Modes**.
- `--worker <ticket> --base <branch>` is the internal entry point for thread-mode children. See **Worker mode**.

## Modes

- **Default (serial)**: one ticket at a time, in this checkout, with one subagent per pipeline step.
- **Thread mode (`--threads`)**: each ticket runs in a child, in parallel, on its own ticket branch. Read [thread-mode.md](thread-mode.md) before the rebase; it replaces the scheduling and adds integration. The ticket pipeline, tracker writes, close-out, and pull request below still apply.

## Setup

Do this before the rebase.

1. **Resolve skills.** Search the runtime's installed skills, project and user skill directories, then this repository's `skills/`. OpenSpec supplies `openspec-apply-change`, `openspec-verify-change`, `openspec-archive-change`, and `openspec-sync-specs`. GoodSkills supplies `goodreview` and `git`. Stop and name any skill you cannot find. Pass each subagent the resolved path.
2. **Resolve the tracker** from `openspec/changes/<change>/tickets.md` (its `Tracker:` line), then `AGENTS.md` / `CLAUDE.md` and the docs they point at. Read [tracker-ops.md](tracker-ops.md) for that tracker's commands. Stop when the tracker's CLI or MCP is unavailable.
3. **Load tickets.** For every ticket in the run, fetch from the tracker: body, state, labels, and blockers. The tracker is the source of truth for whether a ticket is **done**; `tickets.md` maps tickets to changes, blockers, and covered scenarios. When the tracker body differs from what `openspec-to-tickets` wrote, the tracker body wins.
4. **Plan the order.** Drop done tickets. A `ready-for-human` ticket is never shipped; it stays an unfinished blocker for its dependents. The **frontier** is every open, non-human ticket whose blockers are all done or landed this run.

Done when every ticket in the run is classified as done, frontier, waiting on a blocker, or waiting on a human.

## Scheduling (default mode)

Take the frontier one ticket at a time, in `tickets.md` order. Before a ticket's first step, move it to in progress on the tracker. Run its six pipeline steps. When it commits, comment the commit on the ticket, mark it landed, and recompute the frontier. Continue until the frontier is empty.

When a change has no open tickets left other than those landed this run, run **Close out a change** for it before taking the next ticket.

When a ticket blocks:

- Comment the blocker fields (EVIDENCE, ATTEMPTED, NEEDED) on the ticket and add the `needs-info` label (or its mapping in `docs/agents/triage-labels.md`).
- Every ticket that depends on it, directly or transitively, is skipped this run.
- If the blocker leaves unfinished edits, stop the batch and preserve the checkout. Do not start another ticket, stash or discard edits, or include unfinished work in another commit. Do not open a pull request.
- Otherwise continue with the frontier.

Do not advance on `STATUS: blocked` or `STATUS: unfixed`. Inspect the evidence first. If a safe, in-scope recovery remains, continue the same subagent with the missing investigation or repair. Accept a blocker only under the recovery contract. When the runtime cannot resume a subagent, start a replacement for that same step with the prior report, attempted repairs, and current checkout state; it keeps the no-progress count.

## Progress lines

Tell the user one line before each:

- Rebase: `rebase · origin/main`
- Pipeline step: `<ticket> · <n>/6 <step name>`
- Close-out: `<change> · close-out`
- Pull request: `pull request · draft`

## How to start a step

Start one subagent and wait for its result. Do not batch steps.

The prompt stands alone. The subagent does not ask the user. Apply the recovery contract below instead of a named skill's instruction to pause on ordinary errors or ask whether to retry. Questions that require a requirement, scope, or authorization decision remain blockers.

Tell every pipeline subagent:

- The **ticket brief**: the ticket reference and title, the tracker body verbatim (what to build, acceptance criteria), the scenarios it covers from `tickets.md`, and the change name with its directory path. The ticket sets the scope; the change's proposal, design, spec deltas, and `tasks.md` supply context.
- The store id, or that no store was named
- To read the named skill at the resolved path and follow it, except for the overrides in that step
- The shared recovery contract and the step's editing restrictions
- To end its final message with the status block for that step

Subagents never write to the tracker. You do.

## Shared recovery contract

A failed command is evidence to investigate, not automatically a blocker. Continue while a safe, in-scope next action exists. The orchestrator routes recovery; subagents perform the work within their step's editing restrictions.

- Read actual diagnostics before deciding what to do next. Repair formatting, lint findings, compiler warnings, and implementation-caused test failures within the requested scope.
- Resolve implementation details from specs, code, and established patterns, choosing reasonable reversible implementations. Stop for conflicting requirements, changed product behavior, or expanded scope; never silently narrow specified behavior.
- Repair local environment problems using documented setup and existing permissions. Do not discard work, reset data, or broadly clean dependencies as a shortcut. Confirm missing credentials, permissions, or unavailable dependencies and exhaust safe alternatives before blocking.
- After a timeout or connection failure, inspect whether the operation completed before retrying, especially for archive moves, commits, pushes, cherry-picks, and pull request creation. Do not blindly repeat an operation with an unknown outcome.
- Follow repository verification guidance. Run the required full gate at its prescribed checkpoint, then read its logs and rerun failed checks and tests covering repairs. Repeat broader checks only when the repair warrants it.
- Never bypass checks, weaken assertions, drop requirements, or claim an unexecuted check passed. Establish and report unrelated failures without silently expanding scope or claiming the gate passed.
- Continue while attempts produce meaningful new evidence or progress. After three consecutive repair attempts against the same failure without meaningful progress, return a blocker. Repeating an unchanged command is not a repair attempt; do not loop on it.

Return `STATUS: blocked` only when recovery is exhausted, required access is unavailable, or proceeding requires a requirement, scope, or authorization decision. Every blocked result adds these fields to its step's status block:

```text
EVIDENCE: <failed operation and decisive diagnostics>
ATTEMPTED: <repairs and their outcomes, or why none is safe>
NEEDED: <decision, access, or other prerequisite>
```

After a repair invalidates earlier evidence, repeat the affected verification or review before advancing. Pass the repair diff and prior report to a focused follow-up of that step, then route any new findings through its fix step. Formatting-only repairs need formatter validation, not a full review. Do not repeat unaffected steps or a whole pipeline by default.

## Rebase

When at least one ticket is on the frontier, start one subagent before the first ticket. It runs once per run. When none is, stop without rebasing and report the classification from setup.

The prompt names no ticket or store. Include the shared recovery contract and these restrictions. This step has no skill; do not follow the git skill.

Rebase the run branch onto the latest `origin/main`. Check that the tree is clean, fetch `origin`, then run `git rebase origin/main`. Do not switch branches, create a worktree, stash, use an interactive rebase, push, or ask.

- A clean rebase, a fast-forward, or an already up-to-date branch is `STATUS: done`.
- A dirty tree, a missing `origin/main`, or a rebase conflict is `STATUS: blocked`. Abort a conflicted rebase before returning.
- When this step blocks, stop the run. Start no ticket and open no pull request.

```text
STATUS: done|blocked
SUMMARY: <the commit now at HEAD, or the blocker>
```

## Ticket pipeline

Six steps per ticket, in order, one subagent each.

### 1. Apply

Follow `openspec-apply-change` for the ticket's change, scoped to the ticket: implement exactly what the ticket brief asks for, so its acceptance criteria hold. Tick a `tasks.md` item only when this ticket completes it in full. Work belonging to other tickets stays undone, even when it is a remaining task in `tasks.md`.

Overrides: do not archive, do not commit, and do not ask. Ordinary implementation and validation errors use the recovery contract. Resolve implementation details from the ticket, the change's artifacts, and existing patterns; requirement conflicts, design decisions that change specified behavior, and scope beyond the ticket remain blockers. A ticket whose behavior already exists is `STATUS: done` with that stated, but is not proof that validation passed.

```text
STATUS: done|blocked
SUMMARY: <what this ticket now delivers, tasks ticked, or the blocker>
```

### 2. Verify the ticket

Read-only. Check the uncommitted changes against the ticket brief: every acceptance criterion, and every covered scenario's WHEN/THEN, is implemented and exercised by a test. Also flag code that strays outside the ticket's scope, and violations of the change's design. Use `openspec-verify-change`'s report format and its CRITICAL / WARNING / SUGGESTION levels, applied to the ticket rather than the whole change.

Do not edit files, archive, or fix issues. Issues are not a blocker; a report is `STATUS: done`. Failure to produce the report after recovery is `STATUS: blocked`.

Paste the full verification report, then:

```text
STATUS: done|blocked
```

### 3. Fix every verify issue

Pass this subagent the verify report unchanged. Do not summarize it first.

An issue is every item the report lists under CRITICAL, WARNING, and SUGGESTION. Count those items and put `Expected issue count: N` in the prompt. Zero items is a successful no-op.

The subagent fixes every item. It does not drop, defer, or re-rank any item. When the current code already matches the recommendation, it says so and counts that item as fixed. It reruns the checks that establish each item is resolved and reports validation evidence. When it cannot fix an item after recovery, it returns `STATUS: unfixed` with the blocker fields for unresolved items.

```text
STATUS: done|unfixed|blocked
ISSUES: <N>
FIXED:
- <issue> — <what changed, or already in place>
UNFIXED:
- <issue> — <why>
```

`ISSUES` must equal the expected count. `done` requires `UNFIXED` to be empty and one `FIXED` line per issue. When a `done` result falls short, continue the same subagent and name the missing items. If a repair invalidates the verification evidence, get focused verification in step 2 and resolve new findings here before advancing.

### 4. Review

Follow the `goodreview` skill on the uncommitted changes. Do not edit, commit, or create issues. If this subagent cannot spawn its own subagents, it uses that skill's sequential fallback and still returns the full report.

A report is `STATUS: done` even when its verdict is not `Ship`. Failure to produce the report after recovery is `STATUS: blocked`; do not invent a review.

Paste the full goodreview report, then:

```text
STATUS: done|blocked
```

### 5. Fix every review issue

Same contract as step 3, for every numbered item under Findings, confirmed or plausible. Pass the goodreview report unchanged, with `Expected issue count: N`.

Get focused re-review in step 4 for substantive repairs and resolve new findings here. Repeat ticket verification through steps 2 and 3 when behavior changes. This subagent confirms required validation evidence, or runs missing validation, before advancing to commit, even when the review has zero issues.

### 6. Commit

Follow `/git commit` in the git skill.

Overrides: make one commit for this ticket and stop. The subject names the ticket's title, and the body ends with the ticket reference (`Refs #12`, `Refs ENG-123`, `Refs PROJ-7`, or the local ticket path). Do not push, open a pull request, or ask.

Recover in-scope commit failures by reading diagnostics, repairing the cause, and rerunning affected checks. Behavioral repairs return through affected verification and review before committing. Inspect HEAD before retrying an uncertain commit. A dirty tree you cannot commit after recovery is `STATUS: blocked`.

```text
STATUS: done|blocked
COMMITS: <sha> <subject>
```

## Close out a change

Run once per change, after its last open ticket lands, on the run branch. A change with any ticket still open, blocked, skipped, or waiting on a human is not closed out this run.

Three subagents, in order:

1. **Verify the change**: follow `openspec-verify-change` for the whole change, read-only, as in `openspec-ship`. This is the gate for cross-ticket gaps that per-ticket verification cannot see.
2. **Fix every issue**: the step 3 contract, against that report. Behavioral repairs get a focused goodreview through steps 4 and 5 before archive.
3. **Archive and commit**: follow `openspec-archive-change`, then `/git commit`. Decisions already made, do not ask:
   - When delta specs exist and sync is not blocked, sync first by the archive skill's inline sync, wait for its verification to pass, then archive. A substantive spec conflict is `STATUS: blocked`; do not move the change.
   - With no delta specs, archive without syncing.
   - After an interrupted archive, inspect source and destination before retrying.
   - One commit holds any close-out fixes, the synced specs, and the archive move. Its subject names the change. Do not push.

```text
STATUS: done|blocked
SUMMARY: <archive path, whether specs were synced, and the commit, or the blocker>
```

A blocked close-out leaves every ticket landed; report the change as not archived.

## Pull request

After the frontier is empty, start one subagent, unless the batch stopped with unfinished edits. It runs once per run. The prompt names every ticket landed this run with its commit, and every change closed out.

Follow `/git pr` in the git skill. Overrides:

- The pull request contains every commit this run made. The tree must already be clean; a dirty tree is `STATUS: blocked`. Do not make another commit.
- When the run made no commits, return `STATUS: blocked` and say so.
- The body lists each landed ticket as a closing reference per [tracker-ops.md](tracker-ops.md), grouped by change, and names each archived change.
- Push and open one draft pull request. Put its URL on its own line.
- Inspect remote branch and pull request state before retrying an uncertain push or creation; reuse an existing pull request rather than opening a duplicate. Do not force-push or change authorization to recover.

```text
STATUS: done|blocked
PR_URL: <url, or none>
```

Then comment the pull request URL on every ticket landed this run. Close nothing: tickets close when the pull request merges.

## Finish

Summarize in chat:

- The pull request URL, or why it was not opened
- Per ticket: landed (with commit), blocked at which step and why, skipped behind which blocker, or waiting on a human
- Per change: archived, or which tickets keep it open
- Verify and review issues fixed, validation results, and any accepted unrelated failures

Do not paste the verify or goodreview reports again.

## Worker mode

`--worker <ticket> --base <branch>` is how a thread-mode child runs. The child is the orchestrator for one ticket:

- Check out `<base>` from `origin`, then create `<base>--<ticket-slug>` from it. Skip the rebase.
- Read the ticket brief from the prompt; do not refetch or write the tracker.
- Run the six pipeline steps, one subagent each, under the recovery contract.
- On `done`, push `<base>--<ticket-slug>` to `origin`. Skip close-out, the pull request, and every tracker write.

End the final message with:

```text
STATUS: done|blocked
TICKET: <ticket>
BRANCH: <pushed branch, or none>
COMMITS: <sha> <subject>
```

On `blocked`, add the EVIDENCE / ATTEMPTED / NEEDED fields, and push nothing.
