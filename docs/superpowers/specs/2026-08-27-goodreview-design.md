# goodreview — Design Spec

Date: 2026-08-27
Status: approved (conversation); pending user review of this file

## Problem

`review-work` is a multi-specialist code review skill that depends on named custom agents (`code-review-expert`, `security-engineer`, and so on) copied into each runtime's agent directory. The skills CLI installs `SKILL.md` only, so those agents do not travel with the skill. Agent formats also differ by runtime (Claude markdown, Codex TOML, OpenCode markdown, Grok `subagent_type`), and even matching names do not share one prompt.

The portable unit is the specialist **role** plus a self-contained brief, launched as a generic subagent.

## Decision

Add a **new** skill named `goodreview`. Do not rewrite `review-work` in place.

`goodreview` is the portable review engine: role + brief + generic subagent. `review-work`, the `agents/` tree, and `/inspector review-work` stay unchanged in this work. Pointing inspector at `goodreview` is a later change.

## Goals

- One skill install is enough. No named-agent copy step.
- Works on any runtime that can spawn generic subagents, or by running briefs in the host if spawn is unavailable.
- Same job as `review-work`: multi-perspective review of uncommitted work, prioritized findings, commit-readiness verdict.
- Does not compete with `review-work` for auto-invocation while both exist.

## Non-goals

- Creating td/Linear issues.
- Committing, branching, or opening PRs.
- Editing files during the review.
- Installing or calling named custom agents.
- Changing `review-work`, `agents/`, or `/inspector review-work`.
- Writing a report file to disk.
- Applying fixes as part of `/goodreview` (a later user request may do that).

## Layout

```text
skills/goodreview/
  SKILL.md
  README.md
  references/specialists.md
```

`SKILL.md` owns workflow, role selection, launch rule, report template, and rules.
`references/specialists.md` owns the shared finding contract and every role brief.
`README.md` is install and usage only, matching other skills in this repo.

Root `README.md` **adds** `goodreview` to the skill list and install examples. It does not remove `review-work` or the agent-install docs.

## Invocation

```text
/goodreview
/goodreview lib/my_app/accounts
/goodreview frontend settings modal
```

Frontmatter description triggers: `/goodreview`, `goodreview`, `run goodreview`.

Do **not** include `review work`, `code review`, or `review my work`. Those stay on `review-work`.

Optional argument: file path, directory, or short focus. Omitted: all uncommitted changes (staged, unstaged, untracked).

## Workflow

### Phase 1 — Scope

Run as separate shell calls:

```bash
git diff HEAD --stat
git diff --staged --stat
git status --porcelain
git branch --show-current
```

Identify files, languages, layers (backend, frontend, database, tests, docs, infra, config), and risk (auth, migration, public API, UI, concurrency, performance, docs-only). If a focus argument was given, inspect that path unless surrounding context is required.

### Phase 2 — Select roles and launch

Always at least three roles for code changes.

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
Always add **Fresh Eyes** as a separate generic pass (independent second look). Fresh Eyes is not Codex-specific. If a second-model or independent-session tool exists, it may run this pass; otherwise a generic subagent runs it.

**Launch rule:** one generic subagent per selected role, in parallel.

Each subagent prompt is:

1. The shared finding contract.
2. That role's brief from `references/specialists.md`.
3. A scope packet: branch, changed file list, optional focus, instruction to read files not just the diff.

Do not look up custom agent names or `agents/` paths. If the runtime cannot spawn subagents, run the briefs sequentially in the host and keep outputs labeled by role.

Each specialist must:

- Read the changed files, not just the diff.
- Stay in its domain.
- Cite `file:line` (or supporting files for repo-wide issues).
- Rate severity: Critical, High, Medium, Low.
- Suggest a specific fix, or state `No findings`.

### Phase 3 — Synthesis

Deduplicate overlapping findings, flag conflicts, identify issues that span domains, and keep original role attribution. Use a subagent if available; otherwise the host does this pass.

### Phase 4 — Meta-analysis

A second independent pass over the combined findings: over-prioritized, under-prioritized, unsupported, or missing. Same second-model option as Fresh Eyes if one exists; otherwise another generic subagent (or the host, labeled as a separate pass).

### Phase 5 — Report

Print the report in chat only. Do not write a file.

## Finding contract

Every specialist returns:

```text
severity | file:line | title | evidence | fix
```

Severity values: Critical, High, Medium, Low.
Empty result for a role: `No findings`.

## Report template

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

Critical findings map to "must fix" and make commit readiness **Not ready**.
High and Medium map to Warnings.
Low maps to Suggestions.

## Role briefs (owned by `references/specialists.md`)

One brief per role. The brief is the source of domain focus; `SKILL.md` does not duplicate the brief text.

| Role | Focus |
|---|---|
| Code quality | Readability, maintainability, conventions, bugs, idioms, error handling, algorithmic cost, unbounded work |
| Security | Secrets, validation, injection, XSS/CSRF, authz, sensitive data, unsafe logging |
| Tests | Coverage gaps, missing edge cases, regression risk, likely test files |
| QA execution | Smallest useful test/lint/typecheck/CI commands; interpret failures; no destructive commands |
| Elixir | OTP, supervision, Ecto, changesets, migrations, LiveView, ExUnit, error tuples |
| Frontend | Components, state, effects, fetching, types, keys, user-visible states, unnecessary re-renders |
| UI/a11y | Semantics, labels, ARIA, keyboard, focus, responsive, loading/error/empty |
| Database | Integrity, indexes, constraints, migration lock/rollback, query plans, N+1 |
| Technical writing | Audience, clarity, structure, examples, verification steps |
| Accuracy | Claims vs repo: commands, paths, APIs, routes, examples |
| Architecture | Boundaries, dependency direction, coupling, public APIs, data flow |
| Fresh Eyes | Design decisions, hidden assumptions, alternatives, anything that feels off |

There is no standalone Performance role. Performance concerns live in Code quality, Frontend, and Database.

## Edges

**Stop and tell the user**

- Not a git repository, or git commands fail.
- Working tree is clean and there is no focus argument.
- Focus path does not exist.

**Degrade, do not fail**

- No parallel subagents: sequential labeled briefs.
- No second-model tool: Fresh Eyes and meta-analysis still run as generic passes.
- A role returns nothing useful: record `No findings` and continue.
- Only untracked files: include them in scope.

## Rules

- Use parallel generic subagents when the runtime supports them.
- Every finding includes `file:line` or supporting file references, plus a suggested fix.
- Run each git command as its own shell call.
- Do not create issues, commit, or edit files.
- Do not mention named custom agents or `agents/` paths in this skill.

## Repo edits in this work

| Path | Change |
|---|---|
| `skills/goodreview/SKILL.md` | New |
| `skills/goodreview/README.md` | New |
| `skills/goodreview/references/specialists.md` | New |
| `README.md` | Add `goodreview` to contents and install examples; do not remove `review-work` |

No other skill, agent file, or inspector reference is modified.

## Verification

After implementation:

1. `goodreview` never names custom agent files or runtime-specific launch tables (Claude Task vs Codex spawn vs OpenCode Task).
2. Description does not include `review-work` trigger phrases.
3. Dry read: an Elixir-only diff would select Elixir, Security, Tests, and Fresh Eyes, launched as generic subagents.
4. Dry read: a docs-only diff would select Technical writing, Accuracy, and Fresh Eyes.
5. Root README still documents `review-work` and agents; it also lists `goodreview`.
