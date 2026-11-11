# Tracker: Jira

Use the Atlassian MCP when it is connected; otherwise fall back to [`jira-cli`](https://github.com/ankitpokhrel/jira-cli) (`jira`). When neither is available, stop and tell the user which to set up.

- **Project**: the project key from `AGENTS.md` / `CLAUDE.md`. When none is named, ask. Ask for the slice issue type too when the project lacks `Story` (fall back to `Task`).
- **Labels**: Jira labels are free-form strings, so no label needs creating; the label-confirmation step is skipped.
- **Parent ticket**: an **Epic** per change.
  - MCP: the create-issue tool with issue type `Epic`.
  - CLI: `jira epic create -n "<change title>" -s "<change title>" -b "<body>" --no-input`.
- **Slice**: a Story under the epic.
  - MCP: the create-issue tool with the epic as parent and `labels: [<label>]`.
  - CLI: `jira issue create -t Story -s "<title>" -b "<body>" -P <EPIC-KEY> -l <label> --no-input`.
- **Blockers**: the native `Blocks` issue link.
  - MCP: the issue-link tool with link type `Blocks`, the blocker as the outward ("blocks") issue.
  - CLI: `jira issue link <BLOCKER-KEY> <SLICE-KEY> Blocks`.
  - After the first link, view the slice (`jira issue view <SLICE-KEY>`) and confirm it reads "is blocked by <BLOCKER-KEY>". If the direction is reversed, swap the argument order for every later link and fix the first.
- **Bodies**: write Markdown. Both the MCP and `jira-cli` convert it; checkboxes may render as plain list items, which is fine.
- **Reference format** for `tickets.md`: the issue key (e.g. `PROJ-123`) linked to the issue URL.
