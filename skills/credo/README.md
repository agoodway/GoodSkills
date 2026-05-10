# Credo

Run Credo static analysis checks and fix issues in Elixir projects.

## Install

Install this skill globally:

```bash
npx skills add agoodway/GoodSkills --skill credo -g
```

Install into the current project:

```bash
npx skills add agoodway/GoodSkills --skill credo
```

## Usage

```
/credo help
```

## Subcommands

| Subcommand | Purpose |
|------------|---------|
| `check` | Run `mix credo --strict` and report issues |
| `fix` | Run Credo, then fix all reported issues |
