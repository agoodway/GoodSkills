# Tracker: Linear

Use the Linear MCP (`save_issue`, `list_issue_labels`, `save_issue_label`, `list_issues`). When it is not connected, stop and tell the user to connect it.

- **Team**: from `AGENTS.md` / `CLAUDE.md`. When none is named, list teams with `list_teams` and ask which one. Labels and statuses are team-scoped, so every call below uses that team.
- **Labels**: `list_issue_labels` for the team; create a missing one with `save_issue_label` (`name`, `description`, `teamId` set to the team's UUID).
- **Duplicates**: before creating the parent, check `list_issues` with the change name as `query`. When a matching issue exists, show it and ask whether to use it as the parent.
- **Parent ticket**: `save_issue` with `team`, `title`, `description`. No triage label.
- **Slice**: `save_issue` with `team`, `title`, `description`, `parentId` (the parent's identifier), `labels: [<label>]`, and `blockedBy: [<identifiers>]`.
- **Descriptions**: real newlines, not `\n` escapes. Keep the human-readable part short; agent-facing detail (exploration notes, prefactoring hints) goes in a collapsible section at the end:

  ```markdown
  +++ Agent notes

  ...

  +++
  ```

- **Reference format** for `tickets.md`: the identifier (e.g. `ENG-123`) linked to the issue URL.
