# openspec-ship-tickets

Ship the tickets that [`openspec-to-tickets`](../openspec-to-tickets) created. Each ticket runs through its own pipeline: apply that ticket's scope, verify against its acceptance criteria, fix every verify issue, run goodreview, fix every review issue, then commit. Tickets run in blocking order. When a change's last ticket lands, the change gets a full `openspec-verify-change`, fixes, a spec sync, and an archive. The run ends with one draft pull request that references every ticket shipped.

Two modes:

- **Default (serial)**: one ticket at a time in the current checkout, one subagent per step. Like [`openspec-ship`](../openspec-ship), but per ticket.
- **Thread mode (`--threads`)**: each ticket runs in a T3 Code child thread (its own worktree) or an Amp orb, in parallel (`--parallel`, default 3). Children push ticket branches, and the orchestrator cherry-picks them onto the run branch.

The tracker (GitHub, Linear, Jira, or local markdown) decides which tickets are done. The orchestrator moves tickets to in progress, comments commits and the pull request URL, and labels blocked tickets `needs-info`. Tickets close when the pull request merges.

## Install

Install this skill globally:

```bash
npx skills add agoodway/GoodSkills --skill openspec-ship-tickets -g
```

Install into the current project:

```bash
npx skills add agoodway/GoodSkills --skill openspec-ship-tickets
```

Requires `openspec-apply-change`, `openspec-verify-change`, `openspec-archive-change`, and `openspec-sync-specs` from OpenSpec, plus the GoodSkills `goodreview` and `git` skills, and the CLI or MCP for your tracker. Amp thread mode needs all of these installed in the project, since orbs see only project skills.

## Usage

```
/openspec-ship-tickets [change-id | ticket ...] [--threads] [--parallel <n>] [--store <id>]
```

Examples:

```
/openspec-ship-tickets add-account-invites
/openspec-ship-tickets ENG-123 ENG-124
/openspec-ship-tickets add-account-invites add-invite-emails --threads --parallel 4
```

Run it in the repo that contains `openspec/changes/`. With no argument, the skill lists the active changes that have a `tickets.md` and asks which to ship.
