---
name: inspector-review-update
description: >
  Quick-review an OpenSpec change, auto-patch mechanical findings, then resolve
  design-decision findings either by asking the user or by applying the model's
  recommended answers. Use when the user says "/inspector-review-update",
  "inspector review-update", "/inspector review-update", "review and fix the
  openspec", "patch the change specs", "auto-fix OpenSpec findings", or wants
  a review-update pass that can ask questions or decide for them.
---

# Inspector Review-Update

Run a quick review of an OpenSpec change, **auto-patch findings that do not need human input**, then resolve the remaining design-decision findings according to the selected **question mode**.

Unlike `inspector review` (read-only audit), this skill **modifies** OpenSpec change artifacts. It does **not** modify application source code.

This skill is runtime-neutral (Claude Code, OpenCode, Codex). When a step says to use a subagent, question tool, Read, Edit, or Write, use the equivalent capability in the current runtime. If a named subagent is unavailable, run that specialist prompt directly and label the result with the intended role.

## Invocation

```text
/inspector-review-update [change-id] [--ask | --auto]
```

Also accept natural language equivalents:

| User says | Mode |
|-----------|------|
| `--ask`, `ask`, `ask me`, `interactive` | `ask` |
| `--auto`, `auto`, `decide for me`, `recommend`, `model decides`, `answer for me` | `auto` |
| (mode omitted) | Resolve mode in [Mode selection](#mode-selection) |

Legacy entry point: `/inspector review-update …` should load and follow this skill.

## Mode selection

| Mode | Behavior |
|------|----------|
| **`ask`** | Auto-patch mechanical findings. For each design-decision finding, ask the user one question at a time, then apply the fix from their answer. |
| **`auto`** | Auto-patch mechanical findings. For each design-decision finding, pick the **recommended** option, apply it, and record the rationale — no user prompts for those questions. |

If the user already specified a mode (flag or natural language), use it.

If mode is **not** specified:

1. Prefer the runtime question tool when available; otherwise ask in chat.
2. Present exactly these options (safer default first):
   - **Ask me (default)** — you answer each design question
   - **Decide for me** — model applies its recommended answers and records rationale
3. Do not start the specialist review until a mode is chosen.

In `auto` mode, still ask the user which **change-id** to use when none was provided. Only design-decision questions are auto-answered.

## Inputs

- **Arg form**: `/inspector-review-update <change-id>` — use the provided change ID.
- **No arg**: list active changes (`ls openspec/changes/` minus `archive/`) and ask which to review-update.
- If the given change-id does not exist under `openspec/changes/`, stop and report.

## Runtime compatibility

| Concept | Claude Code | OpenCode | Codex |
|---|---|---|---|
| Parallel specialists | Task/Agent subagents | Task subagents when available | Spawn custom agents when available |
| Codebase exploration | Explore/finder-style agent when available | `explore` or direct Glob/Grep/Read | `explorer` or direct search/read |
| User questions (`ask` mode) | `AskUserQuestion` | question tool | Ask directly in the conversation |
| File edits | Edit/Write | apply_patch/edit/write | apply_patch/edit/write |

Prefer direct Glob/Grep/Read over broad shell scans when the runtime provides those tools.

## OpenSpec conventions

- Changes live in `openspec/changes/<change-id>/` with `proposal.md`, `tasks.md`, optional `design.md`, and delta specs at `specs/<capability>/spec.md`.
- Canonical specs live in `openspec/specs/<capability>/spec.md`.
- This skill may edit only files under the target change directory.
- Report path: `openspec/changes/<change-id>/inspector-review-update.md` (overwrite if present).
- Severity tiers: **Critical** (blocks implementation/archiving), **Warning** (should fix before landing), **Suggestion** (nice-to-have).

## Workflow

### 1. Resolve change-id and mode

1. Resolve `change-id` (from args or by asking).
2. Resolve question mode (`ask` / `auto`) per [Mode selection](#mode-selection).
3. Confirm both in a one-line status before reviewing, e.g. `Review-update: buyer-caps · mode=auto`.

### 2. Pre-read (parallel)

Read in one parallel batch:

**Change artifacts** (`openspec/changes/<change-id>/`):

- `proposal.md`
- `design.md` (if present)
- `tasks.md`
- All delta specs under `specs/<capability>/spec.md`

**Surrounding context** (same batch):

- Canonical specs for each touched capability: `openspec/specs/<capability>/spec.md`
- Other active changes: `ls openspec/changes/` (unarchived) that touch the same capabilities
- Recently archived: `ls openspec/changes/archive/ | tail -20` if useful
- Git: `git log --oneline -20 -- openspec/changes/<change-id>/` and status for that dir

Note for each delta: capability, ADDED / MODIFIED / REMOVED, and claimed behavior.

### 3. Quick review — two specialists (parallel)

Dispatch **two** specialists (speed over the four-way full review). Inline pre-read contents into each brief so specialists start immediately.

**Specialist A — Structural + consistency**

- Combines format/structure + cross-change/spec consistency.
- Receives: all change artifacts, canonical specs for touched capabilities, other active change proposals/deltas for the same capabilities.
- Checks: delta format, SHALL/MUST language, task↔spec mapping, orphan tasks/requirements, naming consistency, conflicts with canonical specs or other active changes.

**Specialist B — Codebase alignment + gaps**

- Combines codebase alignment + gaps/risks.
- Receives: proposal and deltas as context; explores the codebase.
- Checks: file paths, function names, schemas, hidden prerequisites, already-implemented work; missing error/edge cases, auth, migrations, rollback, tests, backward compatibility.

Each specialist returns rows in this format:

```text
severity | file:path:line | finding | suggested_fix | has_question: true/false | recommended: <short recommendation or n/a>
```

**`has_question: true`** when:

- The fix needs a **design decision** the inspector cannot make alone
- There is **genuine ambiguity** in proposal/spec
- There are **multiple valid fixes** and intent decides

**`has_question: false`** (auto-patchable) when:

- Fix is **mechanical** (format, naming, missing scenario, missing rollback step)
- Fix is **additive** with a single obvious content (missing test task, error scenario, index)
- Fix has a **single verifiable correct answer** (wrong path, wrong function name, stale code claim)

For every `has_question: true` row, **`recommended` is required**: the single best option the specialist would pick, with enough detail to apply without further input. Example: `recommended: use async PgFlow job; add failure retry task`.

### 4. Classify findings

Merge both specialists. Deduplicate. Split:

**Auto-patch bucket** (`has_question: false`):

- Group by target file
- Order patches top-to-bottom within each file
- Prepare concrete edits

**Question bucket** (`has_question: true`):

- Prepare: severity, title, `file:line`, excerpt, question text, options, and the **recommended** option

### 5. Auto-patch mechanical findings

For each auto-patch finding:

1. Read the target file if needed
2. Apply the edit
3. Log the change

If a patch fails (e.g. `old_string` not found), skip and record under skipped patches.

### 6. Resolve the question bucket

#### Mode `ask`

For each finding, **one question at a time** (do not batch independent design decisions into one prompt):

Present:

- Severity and finding title
- Artifact excerpt (`file:line`)
- The question
- Discrete options when possible; mark **(Recommended)** on the specialist's preferred option
- Allow free-form / "Other" when the runtime supports it

Then:

1. Wait for the user's answer
2. Apply the fix based on their guidance
3. Continue to the next question

If the user says `skip` or `later`, leave unpatched and note it in the report.

#### Mode `auto`

For each finding, **without prompting the user**:

1. Select the **recommended** option from the finding row
2. If `recommended` is missing or empty, derive one from `suggested_fix` and mark confidence low in the report
3. Apply the fix
4. Record: title, `file:line`, chosen recommendation, 1–2 sentence rationale (why this option over alternatives)

Do **not** invent product requirements that contradict the proposal. Prefer the option that:

1. Matches stated proposal intent
2. Matches existing codebase patterns
3. Is the smallest safe change to the specs
4. Preserves backward compatibility when the proposal is silent

If a finding is truly unresolvable without author intent (e.g. two equally valid product directions with no proposal signal), **skip it**, leave it in the report under Skipped, and list it as needing human input — do not guess product strategy.

### 7. Write the report

Write `openspec/changes/<change-id>/inspector-review-update.md` using [references/report_template.md](references/report_template.md).

Rules:

- Include `**Mode:** ask | auto` in the header
- Put patched findings only under **Patches applied** (not also under Critical/Warning/Suggestion)
- Severity sections list only remaining unpatched/skipped findings
- Omit a free-standing "Clarifying questions" dump when questions were resolved inline; unresolved skips stay under **Skipped** and/or severity sections

### 8. Summarize in chat

Print:

- Mode used
- Original finding counts by severity
- Counts: auto-patched / user-guided / model-recommended / skipped
- Any remaining unresolved findings (especially skips in `auto` mode)
- Path to the report
- Verdict: ready / needs revision / blocked

Do not dump the full report into chat.

## Guardrails

- **Modifies OpenSpec only** — proposal, tasks, design, delta specs under the change dir. Never source code.
- **No td issues, no git commits, no branch changes**
- **Conservative classification** — when unsure whether a fix needs human input, set `has_question: true`. False questions are cheap; wrong patches are expensive.
- **`auto` is not reckless** — still skip when product intent is unknowable; never silently invent scope.
- **Cite `file:line`** for every finding and patch
- **Verify before patching** — if a finding claims "function X does not exist", search before editing the spec
- **Scope** — only this change's directory
- **`ask` mode atomicity** — one design question at a time
- **`auto` mode transparency** — every model decision appears in the report with rationale
