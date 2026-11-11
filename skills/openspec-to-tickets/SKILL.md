---
name: openspec-to-tickets
description: Break one or more OpenSpec changes into tracer-bullet tickets with blocking edges, published to the project's tracker (GitHub, Linear, Jira, or local markdown).
disable-model-invocation: true
---

# OpenSpec to Tickets

Break OpenSpec changes into **tickets**: tracer-bullet vertical slices, each declaring the tickets that **block** it, published to the project's tracker under one parent ticket per change.

## Input

```text
/openspec-to-tickets <change> [<change> ...]
```

Also accept a prose list of change names. When no change is named, run `openspec list --json` and ask which active changes to ticket (several may be picked). A name that is not an active change is reported as not found; continue with the rest.

The user may also pass an existing tracker issue as the parent for a change. Use it as that change's parent and leave its body, labels, and state untouched.

## Process

### 1. Gate each change

For each named change:

- Run `openspec validate <change>`. A change that fails is reported with the errors and dropped from the run.
- If `openspec/changes/<change>/tickets.md` exists, the change is already ticketed. Report the path and drop it. Re-ticketing is the user's call: they delete `tickets.md` and rerun.

Done when every named change is either in the run or reported as dropped. Stop if none remain.

### 2. Resolve the tracker

Read `AGENTS.md`, then `CLAUDE.md`, and follow any doc they point at for the issue tracker (Matt Pocock's layout puts it at `docs/agents/issue-tracker.md`). Look for the tracker and its target: the GitHub repo, the Linear team, the Jira project key.

When no tracker is named, ask the user which one: **GitHub**, **Linear**, **Jira**, or **local markdown**. Ask for the target too when the tracker needs one and it is not discoverable. Then offer once to record the answer in whichever of `AGENTS.md` / `CLAUDE.md` exists (`AGENTS.md` when neither does), as:

```markdown
## Agent skills

### Issue tracker

[Tracker and target, e.g. "Linear, team ENG"]. Tickets come from `/openspec-to-tickets`.
```

Update an existing `## Agent skills` block in place rather than appending a second one.

Read the matching tracker file now; it holds the commands for every later step that touches the tracker:

- GitHub: [tracker-github.md](tracker-github.md)
- Linear: [tracker-linear.md](tracker-linear.md)
- Jira: [tracker-jira.md](tracker-jira.md)
- Local markdown: [tracker-local.md](tracker-local.md)

Any other tracker the user names: ask them to describe in a paragraph how to create an issue, nest it under a parent, link a blocker, and apply a label, then follow that description.

### 3. Resolve the labels

The triage labels are Matt Pocock's defaults:

| Role              | Default label     | Meaning                                  |
| ----------------- | ----------------- | ---------------------------------------- |
| `needs-triage`    | `needs-triage`    | Maintainer needs to evaluate this issue  |
| `needs-info`      | `needs-info`      | Waiting on reporter for more information |
| `ready-for-agent` | `ready-for-agent` | Fully specified, ready for an AFK agent  |
| `ready-for-human` | `ready-for-human` | Requires human implementation            |
| `wontfix`         | `wontfix`         | Will not be actioned                     |

When `docs/agents/triage-labels.md` exists, its mapping overrides the label strings. This skill applies only `ready-for-agent` and `ready-for-human`.

### 4. Read each change

Read the whole change: `proposal.md`, `design.md` when present, every spec delta under `specs/`, and `tasks.md`. Treat `tasks.md` as a hint about scope and ordering, not as the ticket list: its tasks are usually horizontal layers.

List every **scenario** in the spec deltas (each `#### Scenario:` under an ADDED or MODIFIED requirement, plus each REMOVED requirement). This list is the coverage target for step 5.

Explore the codebase around the change. Use the project's glossary vocabulary and respect ADRs in the area. Look for prefactoring that makes the change easy: "make the change easy, then make the easy change."

### 5. Draft vertical slices

Break each change into **tracer bullet** tickets.

<vertical-slice-rules>

- Each slice cuts a narrow but COMPLETE path through every layer (schema, API, UI, tests): vertical, not a horizontal slice of one layer
- A completed slice is demoable or verifiable on its own
- Each slice is sized to fit in a single fresh context window
- Any prefactoring comes first

</vertical-slice-rules>

Each ticket carries:

- **Title**: short, in the domain vocabulary
- **Change**: the OpenSpec change it belongs to
- **Blocked by**: the tickets that must complete before it can start, from any change in the run. A cross-change edge belongs where one change builds on a capability another change adds.
- **What it delivers**: the end-to-end behaviour it makes work
- **Covers**: the scenarios it satisfies. Its acceptance criteria are those scenarios' WHEN/THEN, restated as checkboxes.
- **Label**: `ready-for-human` when the slice needs a person (credentials, a third-party dashboard, a product or design decision), else `ready-for-agent`

**Wide refactors are the exception to vertical slicing.** A wide refactor is one mechanical change (rename a column, retype a shared symbol) whose blast radius fans across the codebase, so no vertical slice can land green. Sequence it as **expand–contract**: an expand ticket adds the new form beside the old; migrate tickets move call sites over in batches sized by blast radius, each blocked by the expand; a contract ticket deletes the old form, blocked by every migrate batch. When even the batches cannot stay green alone, let them share an integration branch that all block a final integrate-and-verify ticket.

Done when every scenario from step 4 is covered by at least one ticket, and every blocking edge points at a ticket that genuinely gates it.

### 6. Quiz the user

Present one combined breakdown for all changes, grouped by change, as a numbered list. For each ticket show its title, blocked by, what it delivers, covered scenarios, and label. Ask:

- Does the granularity feel right? (too coarse / too fine)
- Are the blocking edges correct, including the cross-change ones?
- Should any tickets be merged or split?
- Is each `ready-for-human` call right?

Iterate until the user approves the breakdown. Nothing is published before approval.

### 7. Publish

Ensure the labels exist first. List any label the tracker lacks, confirm once, then create them per the tracker file.

For each change, publish its **parent ticket** first (or use the parent the user passed). Then publish every slice across the whole run in dependency order, blockers first, so each blocking edge can reference a real identifier. Work the **frontier**: any ticket whose blockers are all published. Each slice is nested under its change's parent, gets its label, and links its blockers natively where the tracker supports it.

Never close, relabel, or edit a parent the user passed in.

Done when every approved ticket exists on the tracker with its parent, label, and blockers.

### 8. Write the index

Write `openspec/changes/<change>/tickets.md` for each published change. Leave every other file in the change untouched.

```markdown
# Tickets: <change>

Tracker: <tracker and target>
Parent: <parent ID/URL>

| #  | Ticket           | Title   | Label           | Blocked by          | Covers                       |
| -- | ---------------- | ------- | --------------- | ------------------- | ---------------------------- |
| 01 | <ID/URL or path> | <title> | ready-for-agent | None                | <Requirement>: <Scenario>, … |
| 02 | <ID/URL or path> | <title> | ready-for-human | 01, other-change#03 | …                            |
```

Then report to the user: per change, the parent link and ticket count, plus any change dropped in step 1.

## Templates

Ticket bodies avoid file paths and code snippets: they go stale fast. The exception is a snippet that encodes a decision more precisely than prose (a state machine, schema, or type shape) from the change's design; trim it to the decision-rich part.

<parent-template>

## Why

The proposal's Why, condensed.

## What changes

The proposal's What Changes, condensed.

## OpenSpec

Change `<change>`. Slices are the sub-issues of this ticket.

</parent-template>

<issue-template>

## Parent

A reference to the change's parent ticket. Omit when the tracker nested it natively.

## What to build

The end-to-end behaviour this ticket makes work, from the user's perspective, not layer-by-layer implementation.

## Acceptance criteria

- [ ] WHEN … THEN … (from `<Requirement>: <Scenario>`)
- [ ] …

## Blocked by

A reference to each blocking ticket, or "None (can start immediately)". Omit this section when blockers were set as native links.

</issue-template>
