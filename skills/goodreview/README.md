# goodreview

Multi-specialist code review of uncommitted changes using generic subagents. One skill install; no named custom agents. On Codex it uses the Grok CLI in single-turn headless mode; on Grok it uses Codex MCP.

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

For cross-model second opinions, Codex hosts require an installed and authenticated Grok CLI. Grok hosts require an available Codex MCP session tool. If the external provider is unavailable, the skill falls back to a generic or separately labeled host pass.
