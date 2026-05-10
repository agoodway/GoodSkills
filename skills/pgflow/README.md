# PgFlow

Work with PgFlow -- a PostgreSQL-based DAG workflow engine for Elixir/Phoenix.

## Install

Install this skill globally:

```bash
npx skills add agoodway/GoodSkills --skill pgflow -g
```

Install into the current project:

```bash
npx skills add agoodway/GoodSkills --skill pgflow
```

## Usage

```
/pgflow help
```

## Subcommands

| Subcommand | Purpose |
|------------|---------|
| `bootstrap` | Add PgFlow to a Phoenix app (deps, migrations, config, supervision) |
| `flow` | Scaffold a new flow module and compile to database |
| `job` | Scaffold a new job module and compile to database |
| `step` | Add a step to an existing flow |
| `dashboard` | Add the PgFlow LiveView dashboard to the router |
| `liveview` | Scaffold a LiveView with LiveClient flow tracking |
| `debug` | Inspect a run -- status, step states, errors, retries |
