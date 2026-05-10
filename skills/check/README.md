# Check

Run the project's quality checks via `just check`, with an optional fix subcommand to auto-fix failures.

## Install

Install this skill globally:

```bash
npx skills add agoodway/GoodSkills --skill check -g
```

Install into the current project:

```bash
npx skills add agoodway/GoodSkills --skill check
```

## Usage

```
/check help
```

## Subcommands

| Subcommand | Purpose |
|------------|---------|
| `check` | Run `just check` and report results (default) |
| `fix` | Run `just check`, then fix all failures |
