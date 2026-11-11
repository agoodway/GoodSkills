# openspec-to-tickets

Break one or more OpenSpec changes into tracer-bullet tickets and publish them to the project's tracker. Each change gets a parent ticket. Its slices are vertical, each declares the tickets that block it (blockers can cross changes), and each takes its acceptance criteria from the spec-delta scenarios it covers. After you approve the breakdown, the skill publishes in dependency order and writes an index to `openspec/changes/<change>/tickets.md`.

Supported trackers: GitHub (`gh`), Linear (MCP), Jira (Atlassian MCP or `jira-cli`), and local markdown inside the change directory. The tracker is read from `AGENTS.md` / `CLAUDE.md`; if neither names one, the skill asks and offers to record the answer.

Tickets are labelled with [Matt Pocock's default triage labels](https://github.com/mattpocock/skills/blob/main/skills/engineering/setup-matt-pocock-skills/triage-labels.md): `ready-for-agent`, or `ready-for-human` when a slice needs a person. A `docs/agents/triage-labels.md` overrides the label strings.

## Install

Install this skill globally:

```bash
npx skills add agoodway/GoodSkills --skill openspec-to-tickets -g
```

Install into the current project:

```bash
npx skills add agoodway/GoodSkills --skill openspec-to-tickets
```

Requires the `openspec` CLI, plus the CLI or MCP for your tracker.

## Usage

```
/openspec-to-tickets [change-id ...]
```

Example:

```
/openspec-to-tickets add-account-invites add-invite-emails
```

Run it in the repo that contains `openspec/changes/`. If no change name is given, the skill lists the active changes and asks which ones to ticket. Changes that fail `openspec validate`, or already have a `tickets.md`, are skipped and reported.

## Credit

Based on [`to-tickets`](https://github.com/mattpocock/skills/tree/main/skills/engineering/to-tickets) from Matt Pocock's skills (MIT).
