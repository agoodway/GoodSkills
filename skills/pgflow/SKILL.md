---
name: pgflow
description: "Work with PgFlow — a PostgreSQL-based workflow engine for Elixir/Phoenix. Dispatches subcommands via `/pgflow [subcommand] [args]`. Use when the user says '/pgflow bootstrap', '/pgflow help', 'add pgflow', 'pgflow flow', 'pgflow job', 'bootstrap pgflow', 'add workflows', or wants to set up, build, or manage PgFlow flows and jobs in a Phoenix project."
---

# PgFlow

Multi-subcommand skill for working with PgFlow — a PostgreSQL-based DAG workflow engine for Elixir/Phoenix. PgFlow replaces Redis queues and external orchestration with pure PostgreSQL, using PGMQ for message queuing and OTP for execution.

## Subcommands

| Subcommand | Purpose | Reference |
|------------|---------|-----------|
| `bootstrap` | Add PgFlow to an existing Phoenix app (deps, migrations, config, supervision) | [references/bootstrap.md](references/bootstrap.md) |

### `/pgflow help`

Display a list of all available subcommands. Output the following exactly:

```
/pgflow subcommands:

  bootstrap           — Add PgFlow to a Phoenix app (deps, migrations, config, supervision tree)
  help                — Show this help message
```

More subcommands will be added over time. If `/pgflow` is invoked without a subcommand, show the help output above and ask which to run.

## Dispatch

1. Parse the subcommand and args from the user's invocation. Examples:
   - `/pgflow bootstrap` → subcommand `bootstrap`, no args
   - `/pgflow help` → show help
2. If the subcommand is unknown, list available subcommands from the table above and stop.
3. Read the matching reference file from `references/` and follow its workflow exactly.
4. Pass any remaining arguments through to the subcommand.

## PgFlow Quick Reference

These core concepts apply across all subcommands:

- **Flows**: Multi-step DAG workflows defined with `use PgFlow.Flow` and `step`/`map` macros
- **Jobs**: Single-step background tasks defined with `use PgFlow.Job` and `perform` macro
- **Runs**: Instances of a flow/job execution, tracked in `pgflow.runs`
- **Steps**: Individual units of work in a flow, forming a DAG via `depends_on:`
- **PGMQ**: PostgreSQL Message Queue — the underlying queue transport
- **LiveClient**: `PgFlow.LiveClient` for real-time flow tracking in LiveView

### Key API

```elixir
# Start a flow
{:ok, run_id} = PgFlow.start_flow(:flow_slug, %{"key" => "value"})

# Start and wait for completion
{:ok, run} = PgFlow.start_flow_sync(:flow_slug, input, timeout: 30_000)

# Enqueue a job
{:ok, run_id} = PgFlow.enqueue(MyApp.Jobs.MyJob, %{"key" => "value"})

# Check status
{:ok, run} = PgFlow.get_run(run_id)
{:ok, run} = PgFlow.get_run_with_states(run_id)
```

### Mix Tasks

| Task | Purpose |
|------|---------|
| `mix pgflow.copy_migrations` | Copy core schema migrations |
| `mix pgflow.gen.extensions_migration` | Generate worker extensions migration |
| `mix pgflow.gen.flow Module` | Generate migration to compile a flow |
| `mix pgflow.gen.job Module` | Generate migration to compile a job |
| `mix pgflow.check_schema` | Verify database schema compatibility |

### Reference Files

Detailed guides available in `references/`:

| File | Content |
|------|---------|
| [bootstrap.md](references/bootstrap.md) | Full bootstrap walkthrough |
| [flows.md](references/flows.md) | Flow DSL — step, map, DAG deps, handler context |
| [jobs.md](references/jobs.md) | Job DSL — perform, cron, jobs vs flows |
| [config.md](references/config.md) | Configuration options, signal strategies, supervision |
| [liveview.md](references/liveview.md) | LiveClient real-time tracking in LiveView |
| [dashboard.md](references/dashboard.md) | Dashboard installation and setup |
| [telemetry.md](references/telemetry.md) | Telemetry events and observability |

$ARGUMENTS
