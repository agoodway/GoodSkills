---
name: review-work
description: Multi-specialist collaborative code review using parallel subagents for comprehensive analysis. Use when the user says "review work", "review changes", "code review", "review my work", or wants a multi-perspective review of recent changes. Standalone review without td issue creation; use pre-landing-check when review findings should become tracked issues.
---

# Multi-Agent Work Review

Execute a multi-specialist work review of recent changes. This skill is portable across Claude Code, OpenCode, and Codex: use the current runtime's native agent/subagent mechanism where available, and use Codex as the independent fresh-eyes reviewer where available.

## Arguments

```text
/review-work [optional file/area to focus on]
```

The optional argument may be a file path, directory, feature area, or short review focus. If omitted, review all uncommitted changes.

## Runtime Compatibility

Use these launch mechanisms depending on where the skill is running:

| Runtime | Specialist Launch | Codex Fresh Eyes / Meta-Analysis |
|---|---|---|
| Claude Code | Use Task/Agent with matching agents from `agents/claude/` or `~/.claude/agents/` | Use `mcp__codex__codex` if available |
| OpenCode | Use the Task tool with matching agents from `agents/opencode/` | Use `codex_codex` if available |
| Codex | Spawn matching custom agents from `agents/codex/` when available; otherwise run specialist prompts directly | Use a separate Codex session when available; otherwise perform an explicit second-pass fresh-eyes review |

Do not fail the review only because one runtime lacks a named specialist. If a specialist agent is unavailable, run that specialist's prompt directly yourself and label the output with the intended specialist name.

## Available Review Agents

The portable agent set is intentionally aligned across Claude Code, OpenCode, and Codex:

| Agent | Review Role |
|---|---|
| `code-review-expert` | General code quality, maintainability, correctness, security, and performance review |
| `security-engineer` | Vulnerabilities, secrets, input validation, injection, XSS, auth, and data protection |
| `qa-cli-expert` | Test execution, coverage commands, linting, CI/test failure debugging |
| `quality-engineer` | Testing strategy, missing edge cases, coverage gaps, QA risk, release readiness |
| `elixir-expert` | Elixir/Phoenix, OTP, Ecto, LiveView, ExUnit, BEAM-specific concerns |
| `react-expert` | React, TypeScript, frontend state, rendering, data fetching, component architecture |
| `ui-engineering-expert` | UI implementation, accessibility, responsive behavior, CSS, browser behavior |
| `postgres-expert` | PostgreSQL, schema, migrations, indexes, SQL, Ecto query performance, data integrity |
| `technical-writer` | Documentation clarity, structure, completeness, examples, usability |
| `system-architect` | Cross-layer architecture, boundaries, dependencies, scalability, long-term tradeoffs |

## Phase 1: Gather Context And Select Specialists

### 1.1 Analyze The Work

Run these commands as separate shell calls:

```bash
git diff HEAD --stat
git diff --staged --stat
git status --porcelain
git branch --show-current
```

If a focus argument was provided, inspect only that path or area unless the surrounding context is required. Otherwise inspect all uncommitted changes.

Identify:

- Changed files and whether changes are staged, unstaged, or untracked
- Languages and frameworks involved
- Layers touched: backend, frontend, database, tests, docs, infra, config
- Risk level: security-sensitive, data migration, public API, user-visible UI, concurrency, performance, or docs-only

### 1.2 Select Specialists

Always include at least three perspectives for code changes:

| Change Type | Specialists |
|---|---|
| Any code changes | `code-review-expert`, `security-engineer`, `quality-engineer` |
| Elixir/Phoenix backend | `elixir-expert`, `security-engineer`, `quality-engineer` |
| Frontend/JS/CSS | `react-expert`, `ui-engineering-expert`, `quality-engineer` |
| Database/schema/migrations/SQL | `postgres-expert`, `security-engineer`, `quality-engineer` |
| Documentation only | `technical-writer`, plus direct Accuracy Validator prompt from this skill |
| Tests only | `qa-cli-expert`, `quality-engineer`, `code-review-expert` |
| Mixed cross-layer changes | `code-review-expert`, `security-engineer`, `quality-engineer`, `system-architect` |

Include `system-architect` when changes span layers, introduce new boundaries, modify public APIs, add infrastructure, or alter data flow.

Include `qa-cli-expert` when tests need to be run, coverage needs validation, or CI/test failures are part of the request.

Always include a Codex Fresh Eyes perspective when a Codex tool/session is available. If no Codex integration exists, run the Codex Fresh Eyes prompt yourself as an explicit independent pass.

## Phase 2: Parallel Specialist Analysis

Launch selected specialists simultaneously when the runtime supports parallel subagents. If parallel launch is unavailable, run them sequentially but keep outputs separate.

Each specialist must:

- Read the actual changed files, not just the diff
- Provide findings with `file:line` references
- Rate severity for every finding: Critical, High, Medium, Low
- Suggest a specific fix for every finding
- Avoid repeating another specialist's exact finding unless adding a domain-specific angle
- State "No findings" if no substantive issues were found

### Specialist Prompt Templates

Use the matching named agent where available. If the agent is not available in the current runtime, run the prompt directly.

#### Code Quality via `code-review-expert`

Review changed files for readability, maintainability, design patterns, project conventions, potential bugs, language idioms, and error handling. Include `file:line` references for every finding. Prioritize concrete defects and long-term maintainability risks over subjective style preferences.

#### Security via `security-engineer`

Analyze changes for vulnerabilities, exposed secrets, input validation issues, SQL injection risks, command injection, XSS protection, CSRF, auth/authorization patterns, sensitive data leakage, and unsafe logging. Rate each finding's severity and include a concrete remediation.

#### Test Coverage via `quality-engineer`

Assess testing adequacy, missing edge cases, coverage gaps, regression risks, and integration points needing tests. Reference implementation lines that lack adequate coverage. Suggest specific test scenarios and likely test files.

#### QA Execution via `qa-cli-expert`

Identify relevant test, lint, typecheck, coverage, or CI commands for this repository. Run the smallest useful commands needed for the review, interpret failures, and summarize pass/fail counts, timing, and next steps. Do not run destructive commands.

#### Performance via `code-review-expert` or Relevant Specialist

Evaluate changes for efficiency, database query optimization, unnecessary re-renders, algorithmic complexity, N+1 queries, unbounded work, cache risks, and scalability concerns. Use `postgres-expert` for database-heavy performance and `react-expert` or `ui-engineering-expert` for frontend rendering performance.

#### Codex Fresh Eyes

Review git changes from scratch without specialist bias. Focus on overall design decisions, architectural consistency, alternative approaches, hidden assumptions, and anything that feels off. Identify patterns from similar codebases that might indicate future issues. Include `file:line` references where possible.

#### Elixir/Phoenix via `elixir-expert`

Review Elixir/Phoenix changes for OTP design, supervision, Ecto schemas and queries, changesets, migrations, LiveView behavior, ExUnit coverage, pattern matching, error tuples, and idiomatic functional style.

#### React/Frontend via `react-expert`

Review React and TypeScript changes for component architecture, state management, effects, stale closures, data fetching, type safety, rendering behavior, keys, user-visible states, and frontend test coverage.

#### UI/Accessibility via `ui-engineering-expert`

Review UI changes for semantic markup, labels, ARIA, keyboard support, focus management, responsive behavior, layout resilience, loading/error/empty states, and browser behavior.

#### Database via `postgres-expert`

Review database, schema, migration, SQL, and Ecto query changes for data integrity, indexes, constraints, migration lock risk, rollback safety, query plans, N+1 queries, and PostgreSQL operational concerns.

#### Technical Writing via `technical-writer`

Review documentation for audience fit, clarity, structure, completeness, examples, accessibility, prerequisites, verification steps, and troubleshooting usefulness.

#### Accuracy Validator Direct Prompt

Validate documentation claims against the repository. Check commands, paths, config names, APIs, routes, examples, and behavior claims against actual code and safe command output. Report contradicted, stale, or unverifiable claims with evidence and replacement wording.

#### Architecture via `system-architect`

Review cross-layer changes for component boundaries, dependency direction, coupling, public APIs, data flow, scalability, operational implications, and long-term tradeoffs. Recommend minimal architecture fixes over broad rewrites.

## Phase 3: Cross-Pollination Round

After collecting specialist reports, perform a synthesis pass. Use a subagent if the runtime supports it; otherwise do it directly.

The synthesis pass must:

- Review all specialist findings for intersections and conflicts
- Identify systemic issues spanning multiple domains
- Cross-validate findings across specialist perspectives
- Flag integration risks and broader impact
- Deduplicate overlapping findings
- Preserve which specialist originally found each issue
- Note unresolved disagreements or assumptions requiring verification

## Phase 4: Codex Meta-Analysis

Run a final Codex review when available:

```text
Review this multi-specialist analysis. What patterns do you see differently? What risks were not considered? How would you re-prioritize these findings? Challenge the assumptions and provide alternative perspectives. Identify findings that are over-prioritized, under-prioritized, unsupported, or missing.
```

If Codex is not available, perform this as a separate second-pass meta-analysis yourself and label it `Codex-style Meta-Analysis`.

## Phase 5: Final Report

Produce the final response in this structure:

```text
=== MULTI-AGENT WORK REVIEW: [Target] ===
Branch: [branch] | Files: [N] changed | Specialists: [list]

SPECIALIST FINDINGS
[Specialist Name]: [Key findings with file:line references]

CODEX PERSPECTIVE
[Independent Codex analysis or Codex-style analysis]

CROSS-SPECIALIST INSIGHTS
[Systemic issues, conflicts, or patterns spanning multiple domains]

PRIORITIZED ISSUES

Critical (must fix):
- [Issue] - [file:line] - Found by: [Specialist]
  Fix: [specific example]

Warnings (should fix):
- [Issue] - [file:line] - Found by: [Specialist]
  Fix: [specific example]

Suggestions (consider):
- [Issue] - [file:line] - Found by: [Specialist]
  Fix: [specific example]

COMMIT READINESS: [Ready / Not ready - N critical issues remain]
```

If there are no findings, explicitly state that no substantive findings were discovered and list residual risks or testing gaps.

## Review Standards

Each specialist evaluates against these standards:

- **Code Quality**: Simple, readable, self-documenting, well-named, no duplication, follows project conventions
- **Security**: No exposed secrets, proper validation, injection prevention, auth correctness, sensitive data protection
- **Error Handling**: Proper boundaries, meaningful errors, graceful degradation, safe retries and rollbacks
- **Performance**: Efficient algorithms, bounded work, no unnecessary re-renders, query optimization, no N+1s
- **Testing**: Adequate behavior coverage, edge cases, regression tests, integration points, deterministic tests
- **Architecture**: Clear boundaries, correct dependency direction, minimal coupling, scalable data flow
- **Documentation**: Accurate, task-oriented, accessible, current commands and examples

## Anti-Repetition Rules

- Specialists should focus on domain-specific insights others are likely to miss
- Do not repeat another finding unless adding evidence, a different impact, or a better fix
- Prefer concrete fix examples over abstract recommendations
- Consider broader system implications, not only local code style

## Rules

- Use parallel subagents when supported by the runtime; otherwise keep sequential specialist outputs separate
- Codex Fresh Eyes is always included when Codex is available
- Every finding must include a `file:line` reference unless the issue is repository-wide; repository-wide issues must include supporting file references
- Every finding must include a suggested fix
- Do not create td issues; this skill is standalone review only
- Run each git command as its own separate shell call
- Do not modify files unless the user explicitly asks for fixes after the review

$ARGUMENTS
