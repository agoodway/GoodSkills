---
name: implement-openspec-changes
description: Use when the user invokes "/implement-openspec-changes" or asks to implement and commit one or more OpenSpec changes end-to-end.
---

# Implement OpenSpec Changes

Run apply → verify → fix → goodreview → fix → commit for each change, sequentially.

## Setup

Usage: `/implement-openspec-changes [change-id ...]`

- Without IDs, list active changes (`openspec list --json`, or inspect `openspec/changes/` excluding `archive/`) and ask which to implement. Validate all supplied IDs before starting; stop on missing changes.
- Locate `openspec-apply-change`, `openspec-verify-change`, `goodreview`, and `git` in the runtime's installed skills, project/user skill directories, or this repository's `skills/`. Stop and name missing dependencies. OpenSpec supplies the first two; GoodSkills supplies the others.
- Before each change, record HEAD, staged/unstaged diffs, and untracked files. Track this change's files and hunks against that baseline; preserve unrelated work and its staging state. If ownership overlaps ambiguously, ask before modifying or committing those hunks.

## Execution

The host orchestrates. Announce `<change-id> · N/6 · <step>` **before** launching one generic subagent per step in the shared workspace. Wait for completion before advancing; no isolated worktrees or named custom agents. If subagents are unavailable, execute locally with the same gates and label the fallback.

Give each child the repository path, change ID, scope/baseline, these execution/repair gates, relevant dependency skill paths, and preceding reports needed for its step. Require it to read the skill and referenced resources. Only apply/fix children may edit; only the commit child may stage or commit. Each returns status, findings/dispositions, changed files, checks/results, and blockers as applicable. Missing or failed reports are blockers, not clean results.

| Step | Instructions |
|---|---|
| 1. Apply | Follow `openspec-apply-change`. Return task progress (`N/M`). Stop if paused, blocked, or required tasks remain incomplete; already-complete tasks proceed to verification. |
| 2. Verify | Follow `openspec-verify-change` and run relevant project checks. Return the full scorecard and every Critical, Warning, and Suggestion. |
| 3. Fix verification | Skip if no findings. Otherwise resolve findings under the repair rules below and rerun `openspec-verify-change`. |
| 4. Review | Follow `goodreview`, including its specialist briefs, scoped to this change's uncommitted work. Return the full report and commit readiness. |
| 5. Fix review | Skip if no findings. Otherwise resolve findings under the repair rules. Run relevant tests/checks after edits and rerun OpenSpec verification if behavior or task coverage changed. Re-review affected areas when needed to substantiate resolution. |
| 6. Commit | Follow `git`'s `/git commit` workflow, limited to this change. Inspect the exact commit diff; exclude unrelated content, including pre-staged edits and mixed-file hunks, while preserving their staging state. Create atomic conventional commits without AI attribution; return hashes, or `nothing to commit`. Omit push/PR prompts and actions unless requested. |

## Repair and completion gates

- Address **every severity** within this change. Dismiss only demonstrated false positives, with evidence; do not expand scope or weaken requirements/tests to silence findings.
- Allow at most **two repair-and-validation rounds per fix step**. Return each finding's disposition and validation evidence. Stop if any genuine finding remains, required checks fail or cannot run, or resolution requires a user decision.
- Commit only when all required tasks are complete, all findings are resolved or justified false positives, and relevant checks pass on the final code. Reading files alone does not validate behavior fixes.
- On any blocker, stop the pipeline and leave remaining changes queued. Preserve completed work; report the blocker and next action. Do not create issues, archive changes, push, or open PRs unless requested.

Finish with `change-id | apply | verify | review | commit | result`, including commit hashes, check results, justified dismissals, and stopped/queued changes.

$ARGUMENTS
