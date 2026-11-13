---
name: goodreview
description: Use when the user says "/goodreview", "goodreview", or "run goodreview" and wants a multi-specialist review of uncommitted changes, or of a branch against a base ref, that does not depend on named custom agents.
---

# goodreview

Review a change for what will break in production. Specialists raise candidate findings from the briefs in [references/specialists.md](references/specialists.md), a second model tries to refute each one, and the report carries only what survives. Reviewers are generic subagents; this skill does not use named custom agents or agent directories.

## Arguments

```text
/goodreview [base ref | file or area to focus on]
```

- No argument: review all uncommitted changes (staged, unstaged, and untracked).
- A git ref (branch, tag, or commit): review everything since its merge-base with `HEAD`, committed and uncommitted.
- Anything else: a focus within the uncommitted changes. It may be a file path, directory, feature area, or short review focus.

An argument that is both an existing path and a git ref is a path.

## Phase 1: Scope

Run these commands as separate shell calls:

```bash
git status --porcelain
git branch --show-current
git diff HEAD --stat
git diff --staged --stat
```

For a base ref, also run these, passing the ref as one argument:

```bash
git merge-base [ref] HEAD
git diff [merge-base] --stat
```

The **base** is that merge-base, or `HEAD` when no ref was given. The **change** is everything in the working tree that differs from the base, plus untracked files.

**Stop and tell the user** if:

- This is not a git repository, or a git command fails
- The change is empty and there is no focus argument. When the working tree is clean, say that `/goodreview [base ref]` reviews committed work
- A focus path was given and it does not exist

Otherwise identify:

- Changed files and whether they are committed, staged, unstaged, or untracked
- Languages and frameworks
- Layers: backend, frontend, database, tests, docs, infra, config
- Risk: auth, money, migration, public API, user-visible UI, concurrency, performance, docs-only
- Size: files changed and lines added plus removed, from the `--stat` totals plus the full length of each untracked file

If a focus argument was provided, inspect that path unless surrounding context is required.

## Second opinion

Fresh Eyes (Phase 2) and verification (Phase 4) run on a model other than the host when one is reachable. Determine the host from explicit system or runtime identity, such as the system prompt or `CLAUDECODE=1` in a Claude Code session; do not infer it only from which tools or commands are installed. Choose the provider once per review, then use a new stateless session for each pass.

Take the first usable provider in the host's row:

| Host | Provider order |
|---|---|
| Claude | Codex through MCP, Grok headless, Claude subagent on another model |
| Codex | Grok headless, Claude headless |
| Grok | Codex through MCP, Claude headless |
| Other or unknown | Codex through MCP, Grok headless, Claude headless |

Never select the provider that is the host. If nothing in the row is usable, fall back to a generic subagent or a separate host pass.

Every pass prompt is self-contained and includes the relevant diff, because the headless providers cannot run `git diff`:

- Fresh Eyes: Shared finding contract, Fresh Eyes brief, scope packet, and the full diff
- Verification: Shared finding contract, verification prompt, numbered candidate findings, scope packet, and the diff of only the files the candidates cite. The scope packet still lists every changed file, so the verifier can read the others

Pass the prompt using an argument-safe execution mechanism; never allow prompt, diff, path, or user content to become shell syntax. Do not install, update, or authenticate a provider as part of `goodreview`, and do not weaken a provider's read-only controls to make a failed pass run.

The commands, read-only controls, availability checks, and timeout for each provider are in [references/providers.md](references/providers.md). Read its availability section, then only the section for the provider you are about to use.

Record the provider actually used and label it accurately in the report: `Grok CLI`, `Codex via MCP`, `Claude CLI`, `Claude [model] subagent (cross-tier)`, `generic subagent`, or `host fallback`. Only the first three are cross-vendor second opinions when the host is a different vendor; never describe a fallback as one.

## Phase 2: Select roles and launch

Pick roles by what the change puts at risk. Every added role is one whose failure mode the change can actually reach.

Baseline, by what the code is:

| Change | Role |
|---|---|
| Elixir/Phoenix code | Elixir |
| Frontend components or client state | Frontend |
| Any other code | Correctness |
| Docs only | Technical writing, Accuracy |

Add, by risk:

| The change touches | Role |
|---|---|
| Auth, sessions, permissions, secrets, new endpoints, or untrusted input | Security |
| Schema, migrations, SQL, or the shape of a query | Database |
| User-visible markup or interaction | UI/a11y |
| Several layers, a public API, infra, or data flow | Architecture |
| Behavior that can regress silently (authz, money, parsers, migrations, public APIs), or the tests themselves | Tests |
| Code that a cheap project check command covers | QA execution |

Always add **Fresh Eyes**.

Read [references/specialists.md](references/specialists.md). The selected roles run in three places:

- **QA execution** runs in the host, not in a subagent. Follow its brief yourself. Start its commands first, in the background when the runtime supports that, and collect the results after the reviewers return.
- **Fresh Eyes** runs through the second-opinion provider, at the same time as the reviewers.
- **Every other role** runs in a generic subagent, as described below.

### Reviewers

A change is **small** when it is at most 200 changed lines across at most 5 files and its Phase 1 risk includes none of auth, money, migration, public API, or concurrency.

- Small change: launch one generic subagent that holds every selected role. Its prompt carries each of those roles' briefs.
- Any other change: launch one generic subagent per role, all in parallel. On a host where parallel means several tool calls in one message, such as Claude Code, send them in one message.

If the runtime lets you choose a subagent's model, a reviewer that holds only UI/a11y, Technical writing, or Accuracy may run on a smaller, faster model. Every other reviewer runs on the host's model: verification removes false findings but cannot recover a missed one.

Each reviewer prompt contains, in this order:

1. The Shared finding contract
2. The brief for each role the reviewer holds
3. A scope packet:

```text
Roles: [name, or several names for a small change]
Branch: [branch]
Base: [base]
Focus: [optional focus or none]
Risk: [risks identified in Phase 1]
Diff command: git diff [base] -- [paths]
Changed files:
- [path] ([committed | staged | unstaged | untracked])
Not listed: [N] changed files outside these roles' domains
```

List only the changed files in the reviewer's domain, and use the same paths in its diff command:

| Role | Files |
|---|---|
| Elixir | Elixir source, templates, and migrations |
| Frontend | Client-side source |
| Database | Migrations, schemas, and files whose queries changed |
| UI/a11y | Templates, components, and styles |
| Technical writing, Accuracy | Documentation |
| Correctness, Security, Tests, Architecture, Fresh Eyes | Every changed file |

A reviewer holding several roles gets the union of their files.

If the runtime cannot spawn subagents, run the briefs sequentially in this session and keep each output labeled with the role name.

## Phase 3: Merge

In the host, combine the reviewer, QA execution, and Fresh Eyes results into one numbered list of candidate findings:

- Merge findings that describe the same failure, keeping every role that raised it
- Keep each candidate's severity, `file:line`, failure scenario, and fix
- Note where two roles disagree about the same code

With no candidates, skip Phase 4.

## Phase 4: Verification

Run one pass through the second-opinion provider that tries to refute every candidate. Prompt:

```text
Try to refute each numbered candidate finding below by reading the code it cites. Trace its failure scenario: can the trigger actually occur, does the wrong behavior follow, did this change introduce or expose it, and does a guard, constraint, or caller elsewhere already prevent it? Apply the reporting bar in the shared finding contract.

Return one row per candidate:

number | verdict | severity | reason

verdict is exactly one of:
- CONFIRMED: you traced the scenario and it holds
- PLAUSIBLE: you could neither confirm nor refute it; say what is missing
- REFUTED: cite the file:line that prevents it, or the part of the reporting bar it fails

severity is Blocker or Should fix, corrected if the scenario's impact was overstated or understated.
```

Drop every REFUTED candidate and count it. Carry CONFIRMED and PLAUSIBLE candidates into the report with the verifier's severity.

## Phase 5: Report

Print the report in chat only. `goodreview` is read-only: applying fixes, writing files, creating issues, and committing are later user requests.

````markdown
## Verdict: [Ship | Fix first | Don't ship]

[One sentence giving the reason.]

## What changed

[The smallest view that shows the shape of the change: a diff sketch of the call tree, file tree, or control flow.]

## Findings

### 1. [Title] — [Blocker | Should fix]

`[file:line]` · [Role, Role] · [confirmed | plausible] by [provider]

```text
[failure scenario as a short trace: trigger → wrong behavior → who is affected]
```

```diff
[the fix]
```

## Evidence

- `[command]` → [pass and fail counts]
- [N] raised → [C] confirmed, [P] plausible, [R] refuted and dropped

## Merge Danger

**Door:** [one-way | two-way] — [why]

**Blast Radius:** [one word] — [what could be affected]

Roles: [list] · Second opinion: [provider label]
````

- **Verdict:** `Don't ship` for a confirmed Blocker or a check this change broke. `Fix first` for any other finding. `Ship` when there are none.
- **Findings:** Blockers first, numbered consecutively, one entry per finding with every role that raised it on the attribution line. When the fix is larger than a few lines, state it in one sentence instead of a diff. With no findings, the section reads `None above the bar.`
- **Evidence:** every command QA execution ran, with failures this change caused separated from pre-existing ones. If no checks ran, say why.
- **Merge Danger:** a one-way door cannot be walked back after it ships (destructive migrations, sent money or messages, published APIs); a two-way door is cheap to roll back. Blast radius is the widest scope a failure of this change could reach.

## Dry-run selection

Use these checks while executing the skill (not while authoring it):

- Three-line bug fix in a pure Elixir function, with `mix test` available → one reviewer holding Elixir; QA execution in the host; Fresh Eyes
- 60-line change to a LiveView form and its template → one reviewer holding Elixir and UI/a11y; QA execution in the host; Fresh Eyes
- Phoenix migration plus a new authenticated endpoint → separate reviewers for Elixir, Security, Database, and Tests; QA execution in the host; Fresh Eyes
- Short docs-only diff → one reviewer holding Technical writing and Accuracy; Fresh Eyes

$ARGUMENTS
