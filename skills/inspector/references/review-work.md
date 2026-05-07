# inspector review-work

Verify an OpenSpec change against the codebase, then run a multi-specialist code review and fix all issues found.

This is a two-phase workflow: first verify specs match implementation, then run `/review-work` and fix everything it surfaces. Writes a report to `openspec/changes/<change-id>/inspector-review-work.md`.

## Inputs

- **Arg form**: `/inspector review-work <change-id>` — use the provided change ID directly.
- **No arg**: list active changes (`ls openspec/changes/` minus `archive/`) and ask the user which to review.
- If the given change-id doesn't exist under `openspec/changes/`, stop and report.

## Workflow

### 1. Verify the implementation

Invoke the project's verification workflow to check that the OpenSpec proposal has been fully implemented and that specs/design match the actual codebase. Prefer a project-local `/opsx:verify` skill when available. If it is not available, perform the verification directly by reading the change artifacts, tasks, delta specs, and relevant code paths.

**If verification fails:**
- Present the verification failures to the user clearly, grouped by severity.
- Ask the user: "Verification found issues. Would you like to address them before proceeding with code review?"
  - **If yes**: Work through each verification failure, implementing fixes in the codebase. After fixing all issues, re-run the verification workflow to confirm they're resolved. Then proceed to Phase 2.
  - **If no**: Stop. Do not proceed to code review. Write a partial report noting verification failed and the user chose not to address the issues.

**If verification passes:** Proceed to Phase 2.

### 2. Run multi-specialist code review

Invoke the `/review-work` skill to execute a full multi-specialist code review of the changes. This launches parallel specialist subagents (code quality, security, performance, test coverage, Codex fresh eyes, etc.) and produces a prioritized findings report.

Wait for the review to complete and collect all findings.

### 3. Fix all issues

Work through every finding from the review, starting with Critical, then Warnings, then Suggestions:

**For each finding:**
1. Read the referenced file at the cited line
2. Understand the issue and the suggested fix
3. Implement the fix
4. Verify the fix doesn't break anything (run relevant tests if available)

**Fixing rules:**
- Fix ALL findings, not just Critical ones — the goal is to ship clean code
- If a finding's suggested fix would conflict with another finding, use judgment to resolve the conflict and note it in the report
- If a finding is a false positive (the code is actually correct), skip it and note why in the report
- Do not introduce new issues while fixing existing ones
- Stay within the scope of the change — do not refactor unrelated code

### 4. Re-run verification

After all fixes are applied, re-run the verification workflow to confirm the fixes didn't break spec alignment.

- If verification passes: proceed to write the report.
- If verification fails: fix the new failures and re-verify. Maximum 2 re-verification cycles before stopping and reporting.

### 5. Write the report

Write to `openspec/changes/<change-id>/inspector-review-work.md`:

```markdown
# Inspector Review-Work — <change-id>

**Date:** <YYYY-MM-DD>
**Verification:** Passed (attempt N)
**Review findings:** N Critical, N Warning, N Suggestion
**Findings fixed:** N / N total
**Findings skipped:** N (with reasons)

## Verification

<Brief summary of verification result. Note if it required fixes before passing.>

## Review Findings & Fixes

### Critical

1. **<title>** — `file:line`
   - **Issue:** <what was wrong>
   - **Fix applied:** <what was changed>

### Warning

1. **<title>** — `file:line`
   - **Issue:** <what was wrong>
   - **Fix applied:** <what was changed>

### Suggestion

1. **<title>** — `file:line`
   - **Issue:** <what was wrong>
   - **Fix applied:** <what was changed>

### Skipped findings

1. **<title>** — `file:line`
   - **Reason:** <why this was skipped — false positive, conflict, out of scope>

## Final state

- Verification: <Passed/Failed>
- All review findings addressed: <Yes/No>
- Ready to land: <Yes/No — explain if No>
```

### 6. Summarize in chat

After writing the report, print to chat:
- Verification result
- Findings summary: "Fixed N Critical, N Warning, N Suggestion. Skipped N."
- Path to the full report
- One-line verdict: "Ready to land" or "Needs attention: <reason>"

## Guardrails

- **Verification gates the review**: never run `/review-work` before the verification workflow passes (or the user explicitly declines to fix verification issues).
- **Fix everything**: unlike `/inspector review` which is read-only, this subcommand actively modifies code. The goal is to leave the codebase in a landable state.
- **No td issues, no git commits, no branch changes**: this skill modifies code but does not commit or create issues. The user can commit afterward or use `/land-the-plane`.
- **Scope to this change**: only fix issues related to files touched by the change.
- **Report location**: `openspec/changes/<change-id>/inspector-review-work.md` — overwrites any previous report.
- **Dependency on `/review-work` skill**: Phase 2 invokes the `/review-work` skill. Both skills must be installed in the current runtime. If `/review-work` is unavailable, run the multi-specialist review directly following the review-work SKILL.md workflow inline.
