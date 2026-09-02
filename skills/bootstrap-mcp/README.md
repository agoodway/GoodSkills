# Bootstrap MCP Server for Phoenix

Set up a Model Context Protocol (MCP) server in a Phoenix app using
[ExMCP](https://github.com/azmaveth/ex_mcp) (`{:ex_mcp, "~> 1.1.1"}`).

ExMCP owns protocol negotiation, sessions, notifications, Origin/Host
validation, and streams. The app owns Bearer auth, a concatenating
`CacheBody` reader, `Vary: Origin`, and a Bandit-safe GET SSE owner loop.

## Install

Install this skill globally:

```bash
npx skills add agoodway/GoodSkills --skill bootstrap-mcp -g
```

Install into the current project:

```bash
npx skills add agoodway/GoodSkills --skill bootstrap-mcp
```

## Usage

```
/bootstrap-mcp
```
