# Agent Skills

Portable agent skills and matching review subagents for Claude Code, OpenCode, and Codex.

## Contents

- `skills/review-work/SKILL.md`: multi-specialist code review skill
- `skills/scratchpad/SKILL.md`: gitignored temporary project scratchpad workflow
- `skills/git/SKILL.md`: git commit and pull request workflow commands
- `skills/inspector/SKILL.md`: OpenSpec inspection and reconciliation workflows
- `skills/document/SKILL.md`: focused documentation generation (inline, API, guide, external)
- `skills/understand/SKILL.md`: multi-specialist codebase understanding analysis
- `skills/elixir-genius/SKILL.md`: Elixir/Phoenix/LiveView architecture and best practices
- `skills/bootstrap-*/SKILL.md`: Phoenix, Go, Zig, and infrastructure bootstrap skills (15 total)
- `agents/claude/`: Claude Code custom agents
- `agents/opencode/`: OpenCode markdown subagents
- `agents/codex/`: Codex custom agent TOML files

The `review-work` skill expects these specialist names across runtimes:

- `code-review-expert`
- `security-engineer`
- `qa-cli-expert`
- `quality-engineer`
- `elixir-expert`
- `react-expert`
- `ui-engineering-expert`
- `postgres-expert`
- `technical-writer`
- `system-architect`

Additional utility agents (available across all three runtimes):

- `astrojs-expert` — Astro websites, content collections, island architecture
- `code-reviewer` — General code review with checklist and commit readiness
- `data-analyst` — SQL queries, business intelligence, data patterns
- `elixir-qa` — Runs mix precommit with concise issue summaries
- `refactoring-expert` — Code simplification, technical debt, SOLID patterns
- `requirements-analyst` — Requirements discovery, PRDs, user stories
- `root-cause-analyst` — Systematic debugging and evidence-based investigation
- `tailwind-expert` — Tailwind CSS styling, responsive design, theme configuration

## Install Skills

This repository is compatible with the Vercel Labs `skills` CLI.

List available skills:

```bash
npx skills add agoodway/skills --list
```

Install the primary skills into the current project for Claude Code, OpenCode, and Codex:

```bash
npx skills add agoodway/skills --skill review-work --skill scratchpad --skill git --skill inspector --skill document --skill understand --skill elixir-genius -a claude-code -a opencode -a codex
```

Install globally instead:

```bash
npx skills add agoodway/skills --skill review-work --skill scratchpad --skill git --skill inspector --skill document --skill understand --skill elixir-genius -g -a claude-code -a opencode -a codex -y
```

Install from a local checkout:

```bash
npx skills add /path/to/skills --skill review-work --skill scratchpad --skill git --skill inspector --skill document --skill understand --skill elixir-genius -a claude-code -a opencode -a codex
```

Install all skills from this repository:

```bash
npx skills add agoodway/skills --skill '*' -a claude-code -a opencode -a codex
```

Use `--copy` if you want copied files instead of symlinks:

```bash
npx skills add agoodway/skills --skill review-work --skill scratchpad --skill git --skill inspector --skill document --skill understand --skill elixir-genius -a claude-code -a opencode -a codex --copy
```

## Skill Install Locations

The `skills` CLI installs skills, not custom subagents.

Project installs use these runtime paths:

| Runtime | Project Skill Path | Global Skill Path |
|---|---|---|
| Claude Code | `.claude/skills/` | `~/.claude/skills/` |
| OpenCode | `.agents/skills/` | `~/.config/opencode/skills/` |
| Codex | `.agents/skills/` | `~/.codex/skills/` |

## Install Agents

Install the matching subagents separately after installing the skill. The `skills` CLI installs `SKILL.md` files only; it does not install the custom agent files in `agents/`.

If you do not already have this repository checked out locally, fetch a temporary copy first:

```bash
tmpdir=$(mktemp -d)
git clone https://github.com/agoodway/skills.git "$tmpdir/skills"
```

The commands below use `$tmpdir/skills` as the source path.

### Claude Code Agents

Global install:

```bash
mkdir -p ~/.claude/agents
cp "$tmpdir/skills"/agents/claude/*.md ~/.claude/agents/
```

Project install:

```bash
mkdir -p .claude/agents
cp "$tmpdir/skills"/agents/claude/*.md .claude/agents/
```

### OpenCode Agents

OpenCode loads markdown agents from `~/.config/opencode/agents/` globally or `.opencode/agents/` per project.

Global install:

```bash
mkdir -p ~/.config/opencode/agents
cp "$tmpdir/skills"/agents/opencode/*.md ~/.config/opencode/agents/
```

Project install:

```bash
mkdir -p .opencode/agents
cp "$tmpdir/skills"/agents/opencode/*.md .opencode/agents/
```

### Codex Agents

Codex loads custom agents from `~/.codex/agents/` globally or `.codex/agents/` per project.

Global install:

```bash
mkdir -p ~/.codex/agents
cp "$tmpdir/skills"/agents/codex/*.toml ~/.codex/agents/
```

Project install:

```bash
mkdir -p .codex/agents
cp "$tmpdir/skills"/agents/codex/*.toml .codex/agents/
```

Optional project Codex concurrency config:

```bash
mkdir -p .codex
cat > .codex/config.toml <<'EOF'
[agents]
max_threads = 6
max_depth = 1
EOF
```

## Recommended Full Setup

Install the skill globally and install all three agent sets globally from a temporary repository checkout:

```bash
npx skills add agoodway/skills --skill review-work --skill scratchpad --skill git --skill inspector --skill document --skill understand --skill elixir-genius -g -a claude-code -a opencode -a codex -y
tmpdir=$(mktemp -d)
git clone https://github.com/agoodway/skills.git "$tmpdir/skills"
mkdir -p ~/.claude/agents ~/.config/opencode/agents ~/.codex/agents
cp "$tmpdir/skills"/agents/claude/*.md ~/.claude/agents/
cp "$tmpdir/skills"/agents/opencode/*.md ~/.config/opencode/agents/
cp "$tmpdir/skills"/agents/codex/*.toml ~/.codex/agents/
```

For a single project, run this from that project root:

```bash
npx skills add agoodway/skills --skill review-work --skill scratchpad --skill git --skill inspector --skill document --skill understand --skill elixir-genius -a claude-code -a opencode -a codex
tmpdir=$(mktemp -d)
git clone https://github.com/agoodway/skills.git "$tmpdir/skills"
mkdir -p .claude/agents .opencode/agents .codex/agents
cp "$tmpdir/skills"/agents/claude/*.md .claude/agents/
cp "$tmpdir/skills"/agents/opencode/*.md .opencode/agents/
cp "$tmpdir/skills"/agents/codex/*.toml .codex/agents/
```

If you already have a local checkout, replace `"$tmpdir/skills"` with that path.

## Verify Installation

List installed skills:

```bash
npx skills list
```

Check that agent files exist:

```bash
ls ~/.claude/agents
ls ~/.config/opencode/agents
ls ~/.codex/agents
```

For project installs:

```bash
ls .claude/agents
ls .opencode/agents
ls .codex/agents
```

## Usage

Ask your runtime to run the skill:

```text
/review-work
/scratchpad bootstrap
/git help
/inspector help
/document lib/my_app/accounts.ex inline
/understand authentication system
/elixir-genius
```

Or focus the review on a path or area:

```text
/review-work lib/my_app/accounts
/review-work frontend settings modal
/review-work docs setup guide
```

The skill gathers git context, selects specialists based on changed files, launches matching agents where supported, runs a Codex fresh-eyes/meta-analysis pass when available, and returns a prioritized review report.

## Notes

- The `skills` CLI can install `SKILL.md` files for many runtimes, but it does not install custom agent definitions from `agents/`.
- Keep agent filenames aligned across `agents/claude/`, `agents/opencode/`, and `agents/codex/` so `review-work` can use the same specialist names everywhere.
- Codex custom agent filenames can differ from their `name` fields, but this repository keeps them matching for clarity.
