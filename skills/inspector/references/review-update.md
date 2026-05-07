# inspector review-update

Run a quick review of an OpenSpec change, then **auto-patch all findings that don't require human input** and **ask the user about findings that do**. Unlike `review` (read-only audit), this subcommand modifies OpenSpec artifacts.

## Inputs

- **Arg form**: `/inspector review-update <change-id>` — use the provided change ID directly.
- **No arg**: list active changes (`ls openspec/changes/` minus `archive/`) and ask the user which to review-update.
- If the given change-id doesn't exist under `openspec/changes/`, stop and report.

## Workflow

### 1. Run a quick review

Run the same pre-read as `review` (Step 1) — read all change artifacts, canonical specs, other active changes, and codebase context in parallel.

Then dispatch **two** specialists (not four — speed over depth):

**Specialist A — Structural + consistency**
- Combines the roles of review's Agent A (format/structure) and Agent B (cross-change/spec consistency).
- Receives: all change artifacts (proposal, design, tasks, deltas) inlined, canonical specs for touched capabilities inlined, other active change proposals/deltas that touch the same capabilities inlined.
- Checks: delta format compliance, SHALL/MUST language, task↔spec mapping, orphan tasks/requirements, naming consistency, conflicts with canonical specs or other active changes.

**Specialist B — Codebase alignment + gaps**
- Combines the roles of review's Agent C (codebase alignment) and Agent D (gaps/risks).
- Receives: proposal and deltas inlined as context.
- Explores the codebase to verify assumptions (file paths, function names, schemas).
- Also checks for missing concerns: error/edge cases, auth, migrations, rollback, test coverage, backward compatibility.

Each specialist must return findings in this structured format:
```
severity | file:path:line | finding | suggested_fix | has_question: true/false
```

A finding `has_question: true` when:
- The fix requires a **design decision** the inspector cannot make (e.g., "should this be sync or async?")
- The finding surfaces a **genuine ambiguity** in the proposal/spec that needs author input
- There are **multiple valid fixes** and the right choice depends on intent

A finding `has_question: false` (auto-patchable) when:
- The fix is **mechanical** (missing scenario, format issue, naming inconsistency, missing rollback step)
- The fix is **additive** (adding a missing test task, adding a missing error scenario, adding a missing index)
- The fix has a **single obvious correct answer** (wrong file path, incorrect function name, stale assumption about code that can be verified)

### 2. Classify findings

Merge findings from both agents. Deduplicate. Split into two buckets:

**Auto-patch bucket** — findings where `has_question: false`:
- Group by target file (proposal.md, design.md, tasks.md, or a specific delta spec)
- Order patches within each file top-to-bottom to avoid offset drift
- Prepare the concrete edit for each finding

**Question bucket** — findings where `has_question: true`:
- Prepare a clear question for each, citing the artifact and line
- Include the finding context and why it matters

### 3. Auto-patch

For each finding in the auto-patch bucket:
1. Read the target file (if not already in memory)
2. Apply the fix using the runtime's edit capability
3. Log what was changed

Track all patches applied. If a patch fails (e.g., `old_string` not found because the file changed), skip it and add to a "skipped patches" list.

### 4. Ask about questions

For each finding in the question bucket, use the runtime's question mechanism to present:
- The severity and finding title
- The relevant artifact excerpt (file:line)
- The question itself
- The available options or what kind of answer is needed

Wait for the user's answer, then apply the fix based on their guidance. Continue to the next question.

If the user says "skip" or "later" for a question, leave it unpatched and note it in the report.

### 5. Write the report

Write to `openspec/changes/<change-id>/inspector-review.md` using a modified version of the standard report template. Add a `## Patches applied` section after findings:

```markdown
## Patches applied

N findings were auto-patched. M findings were patched after user guidance. K findings were skipped.

### Auto-patched
1. **<title>** — `file:line` → <what was changed>

### User-guided patches
1. **<title>** — `file:line` → <what was changed> (user chose: <summary of decision>)

### Skipped
1. **<title>** — `file:line` → <why skipped>
```

Omit the standard `Clarifying questions` section — questions have been resolved inline.

For any findings that were patched, move them from Critical/Warning/Suggestion to the `Patches applied` section (don't list them in both places). Only unpatched/skipped findings remain in the severity sections.

### 6. Summarize in chat

Print to chat:
- Original finding counts by severity
- How many were auto-patched vs user-guided vs skipped
- Any remaining unresolved findings
- Path to the report
- Verdict: ready / needs revision / blocked

## Guardrails

- **Modifies OpenSpec artifacts**: unlike `review`, this subcommand edits proposals, tasks, design docs, and delta specs. It does NOT modify source code.
- **No td issues, no git commits, no branch changes**: review-update is a spec-editing pass, not an implementation step.
- **Conservative auto-patching**: when in doubt whether a fix needs human input, ask. False questions are cheap; wrong patches are expensive.
- **Cite file:line for every finding and patch** — both the original finding location and what was changed.
- **Verify before patching**: if a finding says "function X doesn't exist", grep for it before patching the spec. Stale knowledge causes bad patches.
- **Scope to this change**: do not edit artifacts outside the change's directory.
- **Atomic questions**: ask one question at a time. Don't batch multiple questions into one prompt — the user needs to think about each independently.
