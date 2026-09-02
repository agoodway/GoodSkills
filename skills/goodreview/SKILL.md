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

## Independent second-opinion passes

Fresh Eyes (Phase 2) and meta-analysis (Phase 4) use a model other than the host when the required integration is available. Determine the host from explicit system or runtime identity; do not infer it only from which tools or commands are installed. Choose the second-opinion provider once per review, then use a new stateless session for each pass.

### Codex host: Grok headless

Run each pass as a new Grok CLI process in single-turn headless mode:

```text
grok --cwd [repository root] --permission-mode dontAsk --sandbox strict --tools read_file,list_dir,grep --deny 'MCPTool(*)' --disable-web-search --no-subagents --output-format plain -p "[pass prompt]"
```

Pass the prompt as one argument using an argument-safe execution mechanism; never allow prompt, diff, path, or user content to become shell syntax. Each prompt is self-contained:

- Fresh Eyes: Shared finding contract, Fresh Eyes brief, scope packet, and relevant git diff
- Meta-analysis: meta-analysis prompt and the collected specialist findings

The tool allowlist lets Grok inspect the actual changed files while withholding edit and shell tools. Include the relevant diff in the prompt because Grok cannot run `git diff`. Keep MCP and web access disabled, and run Grok inside both its strict sandbox and any read-only sandbox supplied by the host. Do not weaken these controls to make a failed pass run.

Do not install, update, or authenticate Grok as part of `goodreview`. If `grok -p` fails, returns no usable review, or is unavailable, fall back to a generic subagent or a separate host pass. Do not substitute a Codex session and describe it as an external Grok opinion.

### Grok host: Codex through MCP

Use the first available Codex session tool:

- `mcp__codex__codex`
- `codex__codex`
- `codex_codex`

Call it with the self-contained pass prompt. If the tool accepts them, set `sandbox` to `read-only` and `approval-policy` to `never`.

If no Codex session tool is available, fall back to a generic subagent or a separate host pass. Do not substitute Grok and describe it as an external Codex opinion.

### Other or unknown host

Prefer an available Codex session tool, then Grok through `grok -p`. Never select a provider known to be the host. If neither external provider is usable, fall back to a generic subagent or a separate host pass.

Record the provider actually used for the report. Label fallbacks accurately; a host pass is independent in role, but is not a cross-model second opinion.

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

Read [references/specialists.md](references/specialists.md). For each selected role except Fresh Eyes, launch one generic subagent in parallel. Run Fresh Eyes via Independent pass. Each generic-subagent prompt contains, in this order:

1. The Shared finding contract
2. That role's brief
3. A scope packet:

```text
Role: [name]
Branch: [branch]
Focus: [optional focus or none]
Changed files:
- [path]
Read the actual files, not only the git diff.
Return findings using the shared finding contract.
```

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

Run this pass via Independent pass. Include the collected specialist findings in the prompt.

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

FRESH EYES — [Grok CLI | Codex via MCP | generic subagent | host fallback]
[Independent findings]

SECOND-OPINION META-ANALYSIS — [provider]
[Independent analysis and re-prioritization]

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
- On Codex, use Grok through `grok -p`; on Grok, use Codex MCP; otherwise use an external provider that is not the host
- Use a new stateless external session for Fresh Eyes and meta-analysis, and label the provider actually used
- Every finding includes `file:line` or supporting file references, plus a suggested fix
- Run each git command as its own shell call
- Do not create issues, commit, or edit files
- Do not look up named custom agents
- Applying fixes is a later user request, not part of `/goodreview`

$ARGUMENTS
