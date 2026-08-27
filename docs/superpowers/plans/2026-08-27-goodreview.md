# goodreview Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a new `goodreview` skill that runs multi-specialist review of uncommitted changes using generic subagents and skill-owned briefs, without named custom agents.

**Architecture:** `SKILL.md` orchestrates git scoping, role selection, generic subagent launch, synthesis, meta-analysis, and the chat report. `references/specialists.md` is the single source of the finding contract and the twelve role briefs. Root `README.md` lists the new skill beside `review-work`; `review-work`, `agents/`, and inspector are not modified.

**Tech Stack:** Agent skill markdown (`SKILL.md` + `references/`), Vercel Labs `skills` CLI install docs, git CLI for review scope.

## Global Constraints

- Skill name is `goodreview` (no hyphen).
- Invocation is `/goodreview` with optional path/area focus. Description triggers are only `/goodreview`, `goodreview`, and `run goodreview`.
- Do not include `review work`, `code review`, or `review my work` as triggers.
- Do not look up named custom agents or `agents/` paths.
- Do not mention runtime-specific launch tables or tools (`Claude Code`, `OpenCode`, `mcp__codex`, `codex_codex`, `agents/claude`, `code-review-expert`, and the other kebab-case agent names).
- Role names are exactly: Code quality, Security, Tests, QA execution, Elixir, Frontend, UI/a11y, Database, Technical writing, Accuracy, Architecture, Fresh Eyes.
- `SKILL.md` does not duplicate brief text; it points at `references/specialists.md`.
- Review is read-only: no issues, commits, or file edits. Report is chat-only.
- Do not modify `skills/review-work/`, `agents/`, or `skills/inspector/`.
- Root `README.md` adds `goodreview`; it does not remove `review-work` or agent-install docs.
- Install package string in skill README matches siblings: `agoodway/GoodSkills`.
- Spec: `docs/superpowers/specs/2026-08-27-goodreview-design.md`.

## File structure

| File | Responsibility |
|---|---|
| `skills/goodreview/references/specialists.md` | Finding contract + twelve role briefs |
| `skills/goodreview/SKILL.md` | Triggers, workflow, selection, launch rule, edges, report template |
| `skills/goodreview/README.md` | Install and usage |
| `README.md` | Add skill to contents, install commands, and usage examples |

---

### Task 1: Specialist briefs

**Files:**
- Create: `skills/goodreview/references/specialists.md`

**Interfaces:**
- Consumes: none
- Produces: heading names that Task 2 must copy verbatim: `## Shared finding contract`, `## Code quality`, `## Security`, `## Tests`, `## QA execution`, `## Elixir`, `## Frontend`, `## UI/a11y`, `## Database`, `## Technical writing`, `## Accuracy`, `## Architecture`, `## Fresh Eyes`. Finding line shape: `severity | file:line | title | evidence | fix`.

- [ ] **Step 1: Run the failing checks**

From the repo root:

```bash
test -f skills/goodreview/references/specialists.md
```

Expected: FAIL (`test: ... No such file or directory` or exit 1).

- [ ] **Step 2: Write `skills/goodreview/references/specialists.md`**

Create the directory `skills/goodreview/references/` and write this exact file:

````markdown
# goodreview specialist briefs

Copy the shared finding contract and the selected role brief into each generic subagent prompt. Do not look up named custom agents.

## Shared finding contract

Return findings as one row per issue:

```text
severity | file:line | title | evidence | fix
```

- `severity` is exactly one of: Critical, High, Medium, Low
- `file:line` points at the implementation. Repo-wide issues still cite supporting files
- `fix` is a concrete change, not a vague recommendation
- If there are no substantive issues, return exactly: `No findings`
- Read the actual files, not only the git diff
- Stay in this role's domain. Do not repeat another role's finding unless you add evidence, impact, or a better fix

## Code quality

Review changed files for readability, maintainability, project conventions, potential bugs, language idioms, error handling, algorithmic cost, and unbounded work. Prioritize concrete defects and long-term maintainability risks over subjective style. Include performance issues that are not database- or render-specific (hot loops, unbounded collections, missing timeouts).

## Security

Analyze changes for exposed secrets, missing input validation, SQL injection, command injection, XSS, CSRF, auth and authorization gaps, sensitive data leakage, and unsafe logging. Rate each finding and include a concrete remediation.

## Tests

Assess testing adequacy: missing edge cases, coverage gaps, regression risk, and integration points that need tests. Reference implementation lines that lack coverage. Suggest specific scenarios and the likely test files.

## QA execution

Identify the smallest useful test, lint, typecheck, coverage, or CI commands for this repository. Run them. Interpret failures. Summarize pass/fail counts and next steps. Do not run destructive commands (drop database, reset git, push, deploy).

## Elixir

Review Elixir/Phoenix changes for OTP design, supervision, Ecto schemas and queries, changesets, migrations, LiveView behavior, ExUnit coverage, pattern matching, error tuples, and idiomatic functional style.

## Frontend

Review UI component and TypeScript/JavaScript changes for component architecture, state, effects, stale closures, data fetching, type safety, keys, user-visible states, and unnecessary re-renders.

## UI/a11y

Review UI changes for semantic markup, labels, ARIA, keyboard support, focus management, responsive behavior, layout resilience, and loading/error/empty states.

## Database

Review schema, migration, SQL, and query changes for data integrity, indexes, constraints, migration lock risk, rollback safety, query plans, and N+1 queries.

## Technical writing

Review documentation for audience fit, clarity, structure, completeness, examples, prerequisites, verification steps, and troubleshooting usefulness.

## Accuracy

Validate documentation claims against the repository. Check commands, paths, config names, APIs, routes, examples, and behavior claims against actual code and safe command output. Report contradicted, stale, or unverifiable claims with evidence and replacement wording.

## Architecture

Review cross-layer changes for component boundaries, dependency direction, coupling, public APIs, data flow, scalability, operational implications, and long-term tradeoffs. Recommend minimal architecture fixes over broad rewrites.

## Fresh Eyes

Review the changes from scratch without the other roles' bias. Focus on design decisions, architectural consistency, alternative approaches, hidden assumptions, and anything that feels off. Include `file:line` references where possible.
````

- [ ] **Step 3: Run the passing checks**

```bash
test -f skills/goodreview/references/specialists.md

for h in \
  "## Shared finding contract" \
  "## Code quality" \
  "## Security" \
  "## Tests" \
  "## QA execution" \
  "## Elixir" \
  "## Frontend" \
  "## UI/a11y" \
  "## Database" \
  "## Technical writing" \
  "## Accuracy" \
  "## Architecture" \
  "## Fresh Eyes"
do
  grep -F "$h" skills/goodreview/references/specialists.md >/dev/null || { echo "missing heading: $h"; exit 1; }
done

grep -F 'severity | file:line | title | evidence | fix' skills/goodreview/references/specialists.md >/dev/null
grep -F 'No findings' skills/goodreview/references/specialists.md >/dev/null

! grep -E 'agents/(claude|opencode|codex)|code-review-expert|security-engineer|qa-cli-expert|quality-engineer|elixir-expert|react-expert|ui-engineering-expert|postgres-expert|technical-writer|system-architect|mcp__codex|codex_codex' skills/goodreview/references/specialists.md
```

Expected: all commands exit 0. The last `grep` exits 1 when there are no matches; `!` inverts that to 0.

- [ ] **Step 4: Commit**

```bash
git add skills/goodreview/references/specialists.md
git commit -m "$(cat <<'EOF'
feat: add goodreview specialist briefs

Shared finding contract and twelve role briefs for generic subagents.
EOF
)"
```

---

### Task 2: Skill workflow

**Files:**
- Create: `skills/goodreview/SKILL.md`

**Interfaces:**
- Consumes: role headings and finding contract from `skills/goodreview/references/specialists.md` (Task 1)
- Produces: slash command `/goodreview`; selection table using those exact role names; report header `=== GOODREVIEW:`

- [ ] **Step 1: Run the failing check**

```bash
test -f skills/goodreview/SKILL.md
```

Expected: FAIL (exit 1).

- [ ] **Step 2: Write `skills/goodreview/SKILL.md`**

Write this exact file:

````markdown
---
name: goodreview
description: Use when the user says "/goodreview", "goodreview", or "run goodreview" and wants a multi-specialist review of uncommitted changes that does not depend on named custom agents.
---

# goodreview

Execute a multi-specialist review of uncommitted changes using generic subagents and the briefs in [references/specialists.md](references/specialists.md). This skill does not use named custom agents.

## Arguments

```text
/goodreview [optional file/area to focus on]
```

The optional argument may be a file path, directory, feature area, or short review focus. If omitted, review all uncommitted changes (staged, unstaged, and untracked).

## Phase 1: Scope

Run these commands as separate shell calls:

```bash
git diff HEAD --stat
git diff --staged --stat
git status --porcelain
git branch --show-current
```

**Stop and tell the user** if:

- This is not a git repository, or a git command fails
- The working tree is clean and there is no focus argument
- A focus path was given and it does not exist

Otherwise identify:

- Changed files and whether they are staged, unstaged, or untracked
- Languages and frameworks
- Layers: backend, frontend, database, tests, docs, infra, config
- Risk: auth, migration, public API, user-visible UI, concurrency, performance, docs-only

If a focus argument was provided, inspect that path unless surrounding context is required. Include untracked files in scope.

## Phase 2: Select roles and launch

Always include at least three roles for code changes. Always add **Fresh Eyes**.

| Change type | Roles |
|---|---|
| Any code | Code quality, Security, Tests |
| Elixir/Phoenix | Elixir, Security, Tests |
| Frontend | Frontend, UI/a11y, Tests |
| Schema/SQL | Database, Security, Tests |
| Docs only | Technical writing, Accuracy |
| Tests only | QA execution, Tests, Code quality |
| Cross-layer | Code quality, Security, Tests, Architecture |

Add Architecture when the diff spans layers, public APIs, infra, or data flow.
Add QA execution when tests, lint, or CI should actually be run.

Read [references/specialists.md](references/specialists.md). For each selected role, launch one generic subagent in parallel. Each subagent prompt contains, in this order:

1. The Shared finding contract
2. That role's brief
3. A scope packet: branch, changed file list, optional focus, and the instruction to read the actual files not only the git diff

Do not look up named custom agents. Do not use agent directories.

If the runtime cannot spawn subagents, run the briefs sequentially in this session and keep each output labeled with the role name.

Each specialist must:

- Read the changed files, not just the diff
- Stay in its domain
- Cite `file:line` (or supporting files for repo-wide issues)
- Rate severity: Critical, High, Medium, Low
- Suggest a specific fix, or state `No findings`

## Phase 3: Synthesis

After collecting specialist reports, synthesize:

- Deduplicate overlapping findings
- Flag conflicts and unresolved disagreements
- Identify issues that span domains
- Keep original role attribution

Use a generic subagent if spawning is available; otherwise do this pass in the host.

## Phase 4: Meta-analysis

Run a second independent pass over the combined findings. Prompt:

```text
Review this multi-specialist analysis. What patterns do you see differently? What risks were not considered? How would you re-prioritize these findings? Challenge the assumptions. Identify findings that are over-prioritized, under-prioritized, unsupported, or missing.
```

If a second-model or independent-session tool exists, use it for this pass (and for Fresh Eyes in Phase 2). Otherwise launch another generic subagent, or run the pass in the host and label it as a separate pass.

## Phase 5: Report

Print the report in chat only. Do not write a file. Do not create issues, commit, or edit files.

Map specialist severity onto the report buckets:

- Critical → Critical (must fix). Any Critical finding makes commit readiness **Not ready**
- High or Medium → Warnings (should fix)
- Low → Suggestions (consider)

```text
=== GOODREVIEW: [Target] ===
Branch: [branch] | Files: [N] changed | Roles: [list]

SPECIALIST FINDINGS
[Role]: [key findings with file:line]

FRESH EYES
[Independent second pass]

CROSS-SPECIALIST INSIGHTS
[Systemic issues, conflicts, overlapping patterns]

PRIORITIZED ISSUES

Critical (must fix):
- [Issue] - [file:line] - Found by: [Role]
  Fix: [specific example]

Warnings (should fix):
- [Issue] - [file:line] - Found by: [Role]
  Fix: [specific example]

Suggestions (consider):
- [Issue] - [file:line] - Found by: [Role]
  Fix: [specific example]

COMMIT READINESS: Ready | Not ready - N critical issues remain
```

If there are no findings, say so and list residual risks or testing gaps.

## Dry-run selection

Use these checks while executing the skill (not while authoring it):

- Elixir-only diff → Elixir, Security, Tests, Fresh Eyes
- Docs-only diff → Technical writing, Accuracy, Fresh Eyes

## Rules

- Use parallel generic subagents when the runtime supports them; otherwise sequential labeled briefs
- Every finding includes `file:line` or supporting file references, plus a suggested fix
- Run each git command as its own shell call
- Do not create issues, commit, or edit files
- Do not look up named custom agents
- Applying fixes is a later user request, not part of `/goodreview`

$ARGUMENTS
````

- [ ] **Step 3: Run the passing checks**

```bash
test -f skills/goodreview/SKILL.md

# frontmatter name and slash-first triggers
grep -F 'name: goodreview' skills/goodreview/SKILL.md >/dev/null
grep -F '/goodreview' skills/goodreview/SKILL.md >/dev/null
grep -F 'run goodreview' skills/goodreview/SKILL.md >/dev/null

# description (first 10 lines) must not steal review-work phrases
! sed -n '1,10p' skills/goodreview/SKILL.md | grep -E 'review work|code review|review my work'

# selection table uses Task 1 role names
grep -F 'Elixir, Security, Tests' skills/goodreview/SKILL.md >/dev/null
grep -F 'Technical writing, Accuracy' skills/goodreview/SKILL.md >/dev/null
grep -F 'Frontend, UI/a11y, Tests' skills/goodreview/SKILL.md >/dev/null

# report + launch
grep -F '=== GOODREVIEW:' skills/goodreview/SKILL.md >/dev/null
grep -F 'generic subagent' skills/goodreview/SKILL.md >/dev/null
grep -F 'references/specialists.md' skills/goodreview/SKILL.md >/dev/null
grep -F 'git diff HEAD --stat' skills/goodreview/SKILL.md >/dev/null

# no named agents or runtime launch tables
! grep -E 'agents/(claude|opencode|codex)|code-review-expert|security-engineer|qa-cli-expert|quality-engineer|elixir-expert|react-expert|ui-engineering-expert|postgres-expert|technical-writer|system-architect|mcp__codex|codex_codex|Claude Code|OpenCode' skills/goodreview/SKILL.md
```

Expected: all commands exit 0.

- [ ] **Step 4: Dry-read the selection table**

Open `SKILL.md` and confirm:

- An Elixir-only diff selects Elixir, Security, Tests, plus Fresh Eyes (always added).
- A docs-only diff selects Technical writing, Accuracy, plus Fresh Eyes.
- Briefs are not pasted into `SKILL.md`; they are loaded from `references/specialists.md`.

- [ ] **Step 5: Commit**

```bash
git add skills/goodreview/SKILL.md
git commit -m "$(cat <<'EOF'
feat: add goodreview skill workflow

Generic-subagent review orchestration with slash-first triggers.
EOF
)"
```

---

### Task 3: Install and usage docs

**Files:**
- Create: `skills/goodreview/README.md`
- Modify: `README.md` (contents list, six primary install commands, usage examples)

**Interfaces:**
- Consumes: `/goodreview` from Task 2
- Produces: installable skill documented at repo root and in the skill README

- [ ] **Step 1: Run the failing checks**

```bash
test -f skills/goodreview/README.md
grep -F 'skills/goodreview/SKILL.md' README.md
```

Expected: first command exits 1; second `grep` exits 1 (no match).

- [ ] **Step 2: Write `skills/goodreview/README.md`**

````markdown
# goodreview

Multi-specialist code review of uncommitted changes using generic subagents. One skill install; no named custom agents.

## Install

Install this skill globally:

```bash
npx skills add agoodway/GoodSkills --skill goodreview -g
```

Install into the current project:

```bash
npx skills add agoodway/GoodSkills --skill goodreview
```

## Usage

```
/goodreview [optional file/area to focus on]
```
````

- [ ] **Step 3: Update root `README.md`**

In the Core Skills list, immediately after the `review-work` bullet, insert:

```markdown
- `skills/goodreview/SKILL.md`: portable multi-specialist code review using generic subagents
```

In every primary-skill `npx skills add` command that currently contains `--skill review-work --skill scratchpad`, change that substring to `--skill review-work --skill goodreview --skill scratchpad`. That is six commands:

- project install
- global install
- local checkout install
- `--copy` install
- recommended full setup (global)
- recommended full setup (project)

Do not change the `npx skills add agoodway/skills --skill '*'` command.
Do not remove `review-work` or the Install Agents section.

In the Usage block that lists slash commands, immediately after `/review-work` insert:

```text
/goodreview
```

In the focused-review example block, after the three `/review-work` lines, add:

```text
/goodreview lib/my_app/accounts
/goodreview frontend settings modal
```

After the paragraph that starts `The skill gathers git context`, add this paragraph (do not edit the existing `review-work` sentence):

```markdown
`/goodreview` is the portable engine: it selects roles from the diff, launches generic subagents with skill-owned briefs, and prints a prioritized report. It does not require named custom agents.
```

- [ ] **Step 4: Run the passing checks**

```bash
test -f skills/goodreview/README.md
test -f skills/goodreview/SKILL.md
test -f skills/goodreview/references/specialists.md

grep -F '/goodreview' skills/goodreview/README.md >/dev/null
grep -F 'agoodway/GoodSkills --skill goodreview' skills/goodreview/README.md >/dev/null

grep -F 'skills/goodreview/SKILL.md' README.md >/dev/null
grep -F 'skills/review-work/SKILL.md' README.md >/dev/null
grep -F '/goodreview' README.md >/dev/null

# six primary install commands include goodreview
test "$(grep -c -- '--skill goodreview' README.md)" -ge 6

# review-work and agents docs remain
grep -F 'The `review-work` skill expects these specialist names' README.md >/dev/null
grep -F '## Install Agents' README.md >/dev/null

# goodreview files still have no named-agent coupling
! grep -E 'agents/(claude|opencode|codex)|code-review-expert|security-engineer|qa-cli-expert|quality-engineer|elixir-expert|react-expert|ui-engineering-expert|postgres-expert|technical-writer|system-architect|mcp__codex|codex_codex' skills/goodreview/SKILL.md skills/goodreview/README.md skills/goodreview/references/specialists.md

# inspector and review-work untouched by this work (clean vs HEAD if those paths were not yours)
git diff --name-only HEAD -- skills/review-work skills/inspector agents
```

Expected: the `git diff --name-only` command prints nothing. All other commands exit 0.

- [ ] **Step 5: Commit**

```bash
git add skills/goodreview/README.md README.md
git commit -m "$(cat <<'EOF'
docs: document and list the goodreview skill

Skill README plus root contents, install, and usage entries.
EOF
)"
```

---

## Self-review

**Spec coverage**

| Spec requirement | Task |
|---|---|
| New skill `skills/goodreview/` with SKILL.md, README.md, specialists.md | 1–3 |
| Role + brief + generic subagent; no named agents | 1, 2 |
| Slash-first triggers only | 2, 3 |
| Git scope commands as separate calls | 2 |
| Selection table + always Fresh Eyes | 2 |
| Finding contract and twelve briefs | 1 |
| Report template and severity mapping | 2 |
| Edges: stop vs degrade | 2 |
| Chat-only report; no issues/commits/edits | 2 |
| Root README adds goodreview, keeps review-work | 3 |
| Do not modify review-work, agents, inspector | 3 check |
| Elixir-only and docs-only dry reads | 2 |

**Placeholders:** none. File bodies are complete.

**Name consistency:** role headings in Task 1 match the selection table in Task 2.
