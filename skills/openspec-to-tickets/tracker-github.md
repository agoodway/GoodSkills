# Tracker: GitHub

Use the `gh` CLI. The repo comes from `git remote -v`; before the first `gh issue create` of a run, confirm the target with `gh repo view --json nameWithOwner`, and confirm with the user when it is not their own repo (a fork can default to the upstream parent).

- **Labels**: list with `gh label list --json name --jq '.[].name'`; create a missing one with `gh label create <label> --description "<meaning>"`.
- **Parent ticket**: `gh issue create --title "<change title>" --body-file <file>`. Write bodies to a file in the scratchpad or use a heredoc.
- **Slice**: `gh issue create --title "..." --body-file <file> --label <label> --parent <parent> --blocked-by <n>,<n>` (`gh` 2.94+).
- **Older `gh`**:
  - Sub-issue: `gh api --method POST repos/<owner>/<repo>/issues/<parent>/sub_issues -F sub_issue_id=<child-db-id>`.
  - Blocker: `gh api --method POST repos/<owner>/<repo>/issues/<child>/dependencies/blocked_by -F issue_id=<blocker-db-id>`.
  - `<db-id>` is the numeric database id from `gh api repos/<owner>/<repo>/issues/<n> --jq .id`, not the `#number` or `node_id`.
- **No sub-issues or dependencies on the repo**: put `Part of #<parent>` at the top of the slice body, and keep the template's `## Blocked by` section listing `#<n>` references.
- **Reference format** for `tickets.md`: `#<n>` linked to the issue URL.
