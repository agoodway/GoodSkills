# Inspector

Inspect OpenSpec artifacts for gaps, correctness, consistency, and alignment with other specs/changes and the current codebase.

## Install

Install this skill globally:

```bash
npx skills add agoodway/GoodSkills --skill inspector -g
```

Install into the current project:

```bash
npx skills add agoodway/GoodSkills --skill inspector
```

## Usage

```
/inspector help
```

## Subcommands

| Subcommand | Purpose |
|------------|---------|
| `review` | Audit an OpenSpec change for gaps, correctness, consistency, and codebase alignment |
| `review-update` | Quick review then auto-patch fixable findings |
| `sync-linear` | Sync an OpenSpec change to a Linear issue (create or update) |
| `commits` | Detect recent commits that require OpenSpec spec/change updates |
| `reconcile` | Update a change's artifacts to match the current codebase state |
| `explain` | Explain a change with prose, ASCII diagrams, and ASCII mockups |
| `review-work` | Verify implementation, run code review, and fix all findings |
