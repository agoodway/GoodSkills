# Git Workflow Skill

Git workflow commands for committing changes and managing pull requests.

## Install

Install this skill globally:

```bash
npx skills add agoodway/GoodSkills --skill git -g
```

Install into the current project:

```bash
npx skills add agoodway/GoodSkills --skill git
```

## Usage

```
/git help
```

## Subcommands

| Subcommand | Purpose |
|------------|---------|
| `commit [message]` | Commit staged/unstaged changes with conventional format |
| `commit-all` | Commit all changes as logical atomic commits, skipping junk files |
| `pr [context]` | Create a draft pull request for the current branch |
| `pr-update` | Push and update an existing PR description |
| `pr-pull-review` | Fetch PR review comments and address them |
