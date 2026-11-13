# goodreview

Multi-specialist review of a change for what will break in production, using generic subagents. One skill install; no named custom agents.

Specialists are chosen by what the change puts at risk; a small, low-risk change gets one reviewer holding all of them. Each finding must state a failure scenario, and a second model then tries to refute it: confirmed and plausible findings reach the report, refuted ones are dropped and counted. Style, naming, and anything a linter or CI already reports are out of scope.

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
/goodreview                      # all uncommitted changes
/goodreview main                 # everything since the merge-base with main
/goodreview lib/my_app/accounts  # focus on a path or area
```

The report opens with a verdict (`Ship`, `Fix first`, or `Don't ship`), then a sketch of what changed, the numbered findings with a failure trace and a fix each, the evidence (checks run, findings refuted), and the merge danger.

## Second opinions

Fresh Eyes and verification run on a model other than the host when one is reachable:

| Host | Provider order |
|---|---|
| Claude | Codex MCP session tool, Grok CLI, Claude subagent on another model |
| Codex | Grok CLI, Claude CLI |
| Grok | Codex MCP session tool, Claude CLI |

The Grok and Claude CLIs must already be installed and authenticated; the skill never installs or authenticates them. Each runs headless with read-only file tools. If no provider is usable, the skill falls back to a generic subagent or a host pass and labels it as a fallback in the report.
