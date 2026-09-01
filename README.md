# Agent Skills

Portable agent skills and matching review subagents for Claude Code, OpenCode, and Codex.

## Contents

### Core Skills

- `skills/review-work/SKILL.md`: multi-specialist code review skill
- `skills/goodreview/SKILL.md`: portable multi-specialist code review using generic subagents
- `skills/scratchpad/SKILL.md`: gitignored temporary project scratchpad workflow
- `skills/git/SKILL.md`: git commit and pull request workflow commands
- `skills/inspector/SKILL.md`: OpenSpec inspection and reconciliation workflows
- `skills/inspector-review-update/SKILL.md`: OpenSpec quick review + auto-patch (`--ask` or `--auto` for design questions)
- `skills/document/SKILL.md`: focused documentation generation (inline, API, guide, external)
- `skills/understand/SKILL.md`: multi-specialist codebase understanding analysis
- `skills/elixir-genius/SKILL.md`: Elixir/Phoenix/LiveView architecture and best practices

### Developer Workflow Skills

- `skills/check/SKILL.md`: run project quality checks via `just check` with auto-fix subcommand
- `skills/credo/SKILL.md`: run Credo static analysis with check and fix subcommands
- `skills/justfile/SKILL.md`: generate a justfile for the current project
- `skills/publish/SKILL.md`: publish a release via `just publish`
- `skills/workie/SKILL.md`: git worktree lifecycle manager with branch-isolated databases

### Elixir/Phoenix Skills

- `skills/boruta/SKILL.md`: add OAuth 2.0 and OpenID Connect provider using Boruta
- `skills/can-opener/SKILL.md`: create and update Elixir API client packages using CanOpener
- `skills/durex/SKILL.md`: add GenServer state checkpointing (Redis or Tigris) for crash recovery
- `skills/horde/SKILL.md`: set up Horde distributed process infrastructure (registry, supervisor, cluster monitor)
- `skills/openapi/SKILL.md`: regenerate OpenAPI specs in Phoenix apps using open_api_spex
- `skills/pgflow/SKILL.md`: PgFlow PostgreSQL-based workflow engine for Elixir/Phoenix

### CLI Tool Skills

- `skills/goodverify/SKILL.md`: verify emails, phones, and addresses via the GoodVerify CLI
- `skills/goodissues/SKILL.md`: manage projects and track issues via the GoodIssues CLI
- `skills/goodissues-reporter/SKILL.md`: set up GoodIssuesReporter error tracking and monitoring in Phoenix
- `skills/searchapi/SKILL.md`: SearchAPI.io CLI (Google Jobs, Events, News, Maps, Zillow, Locations)
- `skills/listex/SKILL.md`: Listex/Yocal city platform CLI (content, city-scoped pages, email broadcasts)
- `skills/zig-cli/SKILL.md`: build and maintain Zig CLI applications with cross-compilation and OpenAPI client generation

### Bootstrap Skills (23 total)

- `skills/bootstrap-phoenix/SKILL.md`: Phoenix application
- `skills/bootstrap-astro/SKILL.md`: Astro site
- `skills/bootstrap-astro-ses/SKILL.md`: Astro site with AWS SES form handling
- `skills/bootstrap-accounts/SKILL.md`: multi-tenant account-scoped dashboard
- `skills/bootstrap-api-keys/SKILL.md`: API key management UI and backend
- `skills/bootstrap-client-ip/SKILL.md`: client IP extraction from proxy headers
- `skills/bootstrap-credits/SKILL.md`: credit system with Stripe integration
- `skills/bootstrap-elixir-openapi/SKILL.md`: Elixir API client from OpenAPI spec
- `skills/bootstrap-env-banner/SKILL.md`: non-production environment warning banner
- `skills/bootstrap-events/SKILL.md`: event subscription system
- `skills/bootstrap-fly-env-sync/SKILL.md`: sync env vars to Fly.io secrets
- `skills/bootstrap-go-cli/SKILL.md`: Go CLI with Cobra, Viper, and goreleaser
- `skills/bootstrap-go-openapi/SKILL.md`: Go client from OpenAPI spec
- `skills/bootstrap-google-analytics/SKILL.md`: Google Analytics (GA4) in Phoenix
- `skills/bootstrap-mcp/SKILL.md`: MCP server for Phoenix
- `skills/bootstrap-nebulex/SKILL.md`: Nebulex caching in Phoenix
- `skills/bootstrap-openapi/SKILL.md`: OpenAPI for Phoenix
- `skills/bootstrap-phoenix-docker/SKILL.md`: Docker releases for Phoenix
- `skills/bootstrap-posthog/SKILL.md`: PostHog analytics in Phoenix
- `skills/bootstrap-postmark/SKILL.md`: Postmark mailer in Phoenix
- `skills/bootstrap-registration-toggle/SKILL.md`: ENV-based registration toggle
- `skills/bootstrap-user-management/SKILL.md`: account member management UI and backend
- `skills/bootstrap-zig-cli/SKILL.md`: Zig CLI application (standalone bootstrap)

### Agents

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
npx skills add agoodway/skills --skill review-work --skill goodreview --skill scratchpad --skill git --skill inspector --skill inspector-review-update --skill document --skill understand --skill elixir-genius -a claude-code -a opencode -a codex
```

Install globally instead:

```bash
npx skills add agoodway/skills --skill review-work --skill goodreview --skill scratchpad --skill git --skill inspector --skill inspector-review-update --skill document --skill understand --skill elixir-genius -g -a claude-code -a opencode -a codex -y
```

Install from a local checkout:

```bash
npx skills add /path/to/skills --skill review-work --skill goodreview --skill scratchpad --skill git --skill inspector --skill inspector-review-update --skill document --skill understand --skill elixir-genius -a claude-code -a opencode -a codex
```

Install all skills from this repository:

```bash
npx skills add agoodway/skills --skill '*' -a claude-code -a opencode -a codex
```

Use `--copy` if you want copied files instead of symlinks:

```bash
npx skills add agoodway/skills --skill review-work --skill goodreview --skill scratchpad --skill git --skill inspector --skill inspector-review-update --skill document --skill understand --skill elixir-genius -a claude-code -a opencode -a codex --copy
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
npx skills add agoodway/skills --skill review-work --skill goodreview --skill scratchpad --skill git --skill inspector --skill inspector-review-update --skill document --skill understand --skill elixir-genius -g -a claude-code -a opencode -a codex -y
tmpdir=$(mktemp -d)
git clone https://github.com/agoodway/skills.git "$tmpdir/skills"
mkdir -p ~/.claude/agents ~/.config/opencode/agents ~/.codex/agents
cp "$tmpdir/skills"/agents/claude/*.md ~/.claude/agents/
cp "$tmpdir/skills"/agents/opencode/*.md ~/.config/opencode/agents/
cp "$tmpdir/skills"/agents/codex/*.toml ~/.codex/agents/
```

For a single project, run this from that project root:

```bash
npx skills add agoodway/skills --skill review-work --skill goodreview --skill scratchpad --skill git --skill inspector --skill inspector-review-update --skill document --skill understand --skill elixir-genius -a claude-code -a opencode -a codex
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
/goodreview
/scratchpad bootstrap
/git help
/inspector help
/inspector-review-update [change-id] --ask
/inspector-review-update [change-id] --auto
/document lib/my_app/accounts.ex inline
/understand authentication system
/elixir-genius
```

Or focus the review on a path or area:

```text
/review-work lib/my_app/accounts
/review-work frontend settings modal
/review-work docs setup guide
/goodreview lib/my_app/accounts
/goodreview frontend settings modal
```

The skill gathers git context, selects specialists based on changed files, launches matching agents where supported, runs a Codex fresh-eyes/meta-analysis pass when available, and returns a prioritized review report.

`/goodreview` is the portable engine: it selects roles from the diff, launches generic subagents with skill-owned briefs, and prints a prioritized report. It does not require named custom agents. Fresh Eyes and meta-analysis use Codex MCP when available, and fall back to a generic pass otherwise.

## Notes

- The `skills` CLI can install `SKILL.md` files for many runtimes, but it does not install custom agent definitions from `agents/`.
- Keep agent filenames aligned across `agents/claude/`, `agents/opencode/`, and `agents/codex/` so `review-work` can use the same specialist names everywhere.
- Codex custom agent filenames can differ from their `name` fields, but this repository keeps them matching for clarity.
