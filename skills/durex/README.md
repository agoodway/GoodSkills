# Durex

Add Durex GenServer state checkpointing to Elixir projects for crash recovery and node migration.

## Install

Install this skill globally:

```bash
npx skills add agoodway/GoodSkills --skill durex -g
```

Install into the current project:

```bash
npx skills add agoodway/GoodSkills --skill durex
```

## Usage

```
/durex help
```

## Subcommands

| Subcommand | Purpose |
|------------|---------|
| `bootstrap` | Add Durex to a Phoenix/Elixir app (deps, config, optional Redis supervision) |
| `add <Module>` | Add Durex checkpointing to an existing GenServer module |
