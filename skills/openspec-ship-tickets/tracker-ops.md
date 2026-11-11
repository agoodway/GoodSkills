# Tracker operations

Only the orchestrator runs these. Tickets close when the pull request merges, never during the run.

| Operation | GitHub (`gh`) | Linear (MCP) | Jira (Atlassian MCP or `jira-cli`) | Local markdown |
| --- | --- | --- | --- | --- |
| Fetch ticket | `gh issue view <n> --json number,title,body,state,labels,assignees` | `get_issue` | MCP get-issue tool, or `jira issue view <KEY> --plain` | read `tickets/NN-<slug>.md` |
| Is done | `state` is `CLOSED` | state type is `completed` or `canceled` | status category is Done | `**Status:** done` |
| Blockers | `gh issue view <n> --json blockedBy`, open ones only | `get_issue` relations (blocked by) | "is blocked by" links | `**Blocked by:**` line |
| Start | `gh issue edit <n> --add-assignee @me` | `save_issue` with `id`, `state: "In Progress"` (check `list_issue_statuses` for the team's name) | transition to In Progress (MCP transition tool, or `jira issue move <KEY> "In Progress"`) | none |
| Comment | `gh issue comment <n> --body "..."` | `save_comment` | MCP add-comment tool, or `jira issue comment add <KEY> "..."` | none |
| Add `needs-info` | `gh issue edit <n> --add-label needs-info` | `save_issue` with `id`, `addLabels: ["needs-info"]` | add the label (MCP edit tool, or `jira issue edit <KEY> -l needs-info --no-input`) | none |
| PR closing reference | `Closes #<n>` | `Closes <ID>` (Linear's GitHub integration closes on merge) | `<KEY>` mentioned; Jira closes only through the team's own automation | the ticket path; mark it `done` by hand after merge |

Use the label mapping from `docs/agents/triage-labels.md` when it exists.

Local markdown takes no writes during the run: ticket files live in the change directory, and editing them would dirty the tree that rebases, commits, and cherry-picks need clean. Blocked and skipped tickets are reported in the finish summary instead, and landed tickets are marked `done` by hand after merge.
