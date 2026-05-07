# inspector review

Audit a single OpenSpec change for **gaps**, **correctness**, **consistency**, and **alignment** with the rest of the project (other changes, canonical specs, and the current codebase state).

This is a read-only inspection. The only file written is the report at `openspec/changes/<change-id>/inspector-review.md`.

## Inputs

- **Arg form**: `/inspector review <change-id>` — use the provided change ID directly.
- **No arg**: list active changes (`ls openspec/changes/` minus `archive/`) and ask the user which to review.
- If the given change-id doesn't exist under `openspec/changes/`, stop and report.

## Workflow

### 1. Pre-read all files (parallel)

Read everything in a single parallel batch — there are no dependencies between these reads:

**Change artifacts** (from `openspec/changes/<change-id>/`):
- `proposal.md` (why + what)
- `design.md` (if present — architectural decisions, alternatives)
- `tasks.md` (implementation plan, checked state shows progress)
- All delta specs under `specs/<capability>/spec.md`

**Surrounding context** (parallel with above):
- **Canonical specs**: for each capability the change touches, read `openspec/specs/<capability>/spec.md` (if it exists) to understand the pre-change contract.
- **Other active changes**: `ls openspec/changes/` — identify any other unarchived changes that touch the same capabilities or files.
- **Recently archived changes**: `ls openspec/changes/archive/ | tail -20` to spot recent related work whose context may matter.
- **Git state**: `git log --oneline -20 openspec/changes/<change-id>/` and `git status` for the change dir.

Note for each delta: which capability it touches, whether it's an ADDED / MODIFIED / REMOVED section, and what it claims to introduce.

### 2. Dispatch parallel inspection specialists

Launch these specialists **in parallel** using the current runtime's subagent mechanism when available. If subagents are unavailable, run the briefs directly and keep each output separate. **Inline the pre-read file contents into each specialist's brief** so specialists start analyzing immediately without redundant file I/O. Each specialist gets a focused, concrete brief: include the change ID, the file contents relevant to its task, and what to report. Tell each specialist to return findings as a terse list of `severity | file:line | finding | suggestion` rows.

**Specialist A — Format & structural coherence**
- Receives: `proposal.md`, `design.md`, `tasks.md`, and all delta specs (inlined).
- Checks: delta spec headers follow OpenSpec format (`## ADDED/MODIFIED/REMOVED Requirements`, `### Requirement:`, `#### Scenario:`); SHALL/MUST language is used where required; every delta scenario maps to at least one task; every task maps back to a delta requirement or proposal bullet; no orphan tasks; no requirements without scenarios; proposal's "What Changes" matches the delta specs.
- This is mechanical pattern matching — no judgment calls needed.

**Specialist B — Cross-change & spec consistency**
- Receives: this change's deltas (inlined), canonical specs for each touched capability (inlined), and the proposal/deltas of other active changes that touch the same capabilities (inlined).
- Checks: no conflict with canonical specs (e.g. MODIFIED requirement text actually matches a current requirement); no collision with other active changes touching the same requirements; terminology/naming consistent with existing specs; no duplicated effort with another in-flight change.

**Specialist C — Codebase alignment**
- Receives: the change's proposal and deltas (inlined as context).
- Explores the codebase for the modules, schemas, contexts, and tests the change touches.
- Checks: assumptions in the proposal still hold (file paths, function names, schemas, dependencies exist as described); no hidden prerequisite work already landed or still missing; the change isn't re-proposing something already implemented; any "we will add X to Y module" is feasible given the current shape of Y.
- For every codebase claim the change makes, verify it with file:line citations.

**Specialist D — Gaps & risks**
- Receives: proposal, design, tasks, deltas (all inlined).
- Checks for missing concerns: error/edge cases, auth/permissions, observability, migrations, rollout/backfill, test coverage, performance, feature flags, docs updates, backward compatibility. Flag anything the change handwaves or omits that a reasonable reviewer would raise.
- This is the highest-judgment task — detecting what's *absent* requires deep reasoning about the domain.

### 3. Synthesize

Merge the four specialists' findings. Deduplicate overlapping findings. Assign severity:
- **Critical** — blocks implementation or archiving (contradicts canonical spec, references nonexistent code, conflicts with another active change, missing a requirement the proposal promises).
- **Warning** — should fix before landing (missing scenarios, weak error handling, untested edge case, unclear task ↔ spec mapping).
- **Suggestion** — nice-to-have (naming, wording, small scope trims, extra test).

### 4. Write the report

Write to `openspec/changes/<change-id>/inspector-review.md` using the template in [report_template.md](report_template.md). Overwrite any existing file at that path (single canonical report per change).

### 5. Summarize in chat

After writing, print to chat:
- Counts by severity (e.g. "3 Critical, 5 Warning, 2 Suggestion")
- The Critical findings inline (one line each with file:line)
- Path to the full report
- A one-sentence verdict: ready / needs revision / blocked

Do not dump the full report into the chat — link to it.

## Guardrails

- **Read-only on OpenSpec**: do not edit `proposal.md`, `tasks.md`, `design.md`, or any delta spec. Inspector only writes its own report file.
- **No td issues, no git commits, no branch changes**: review is a pure audit.
- **Cite file:line for every concrete finding** — vague findings without a citation should be dropped or rephrased as a Suggestion with a clear "where to look".
- **Verify before you claim**: if a specialist says "function X doesn't exist", search for it yourself before including it as Critical. Stale knowledge is the most common false positive.
- **Scope to this change**: do not review unrelated code or propose refactors outside the change's stated scope.
