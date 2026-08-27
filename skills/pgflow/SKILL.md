---
name: pgflow
description: "Work with PgFlow — a PostgreSQL-based workflow engine for Elixir/Phoenix. Dispatches subcommands via `/pgflow [subcommand] [args]`. Use when the user says '/pgflow bootstrap', '/pgflow flow', '/pgflow job', '/pgflow step', '/pgflow dashboard', '/pgflow liveview', '/pgflow debug', '/pgflow help', 'add pgflow', 'bootstrap pgflow', 'add workflows', 'new flow', 'new job', 'debug run', wants to set up, build, or manage PgFlow flows and jobs in a Phoenix project, or wants conditional/branching workflow behavior — run a step only if/unless some input matches, skip a step or its subtree, gate a step on plan/feature-flag, make a step fail-soft (skip instead of failing the run when retries are exhausted), or asks about if:, if_not:, when_unmet:, when_exhausted:, skipped steps, or skip_reason."
---

# PgFlow

Multi-subcommand skill for working with PgFlow — a PostgreSQL-based DAG workflow engine for Elixir/Phoenix. PgFlow replaces Redis queues and external orchestration with pure PostgreSQL, using PGMQ for message queuing and OTP for execution.

## Subcommands

| Subcommand | Purpose | Reference |
|------------|---------|-----------|
| `bootstrap` | Add PgFlow to a Phoenix app (deps, migrations, config, supervision) | [references/bootstrap.md](references/bootstrap.md) |
| `flow` | Scaffold a new flow module and compile to database | [references/flow.md](references/flow.md) |
| `job` | Scaffold a new job module and compile to database | [references/job.md](references/job.md) |
| `step` | Add a step to an existing flow | [references/step.md](references/step.md) |
| `dashboard` | Add the PgFlow LiveView dashboard to the router | [references/dashboard-setup.md](references/dashboard-setup.md) |
| `liveview` | Scaffold a LiveView with LiveClient flow tracking | [references/liveview-setup.md](references/liveview-setup.md) |
| `debug` | Inspect a run — status, step states, errors, retries | [references/debug.md](references/debug.md) |

### `/pgflow help`

Display a list of all available subcommands. Output the following exactly:

```
/pgflow subcommands:

  bootstrap             — Add PgFlow to a Phoenix app (deps, migrations, config, supervision tree)
  flow [Module]         — Scaffold a new flow module and compile to database
  job [Module]          — Scaffold a new job module and compile to database
  step [Module] [name]  — Add a step to an existing flow
  dashboard [path]      — Add the PgFlow LiveView dashboard to the router
  liveview [Module] [:slug] — Scaffold a LiveView with real-time flow tracking
  debug [run_id|:slug|failed] — Inspect a run, flow, or recent failures
  help                  — Show this help message
```

If `/pgflow` is invoked without a subcommand, show the help output above and ask which to run.

## Dispatch

1. Parse the subcommand and args from the user's invocation. Examples:
   - `/pgflow bootstrap` → subcommand `bootstrap`, no args
   - `/pgflow flow MyApp.Flows.ProcessOrder` → subcommand `flow`, arg `MyApp.Flows.ProcessOrder`
   - `/pgflow job MyApp.Jobs.SendEmail` → subcommand `job`, arg `MyApp.Jobs.SendEmail`
   - `/pgflow step MyApp.Flows.ProcessOrder notify` → subcommand `step`, args `MyApp.Flows.ProcessOrder notify`
   - `/pgflow step notify` → subcommand `step`, arg `notify` (ask which flow)
   - `/pgflow dashboard` → subcommand `dashboard`, no args
   - `/pgflow dashboard /admin/pgflow` → subcommand `dashboard`, arg `/admin/pgflow`
   - `/pgflow liveview MyAppWeb.OrderLive :process_order` → subcommand `liveview`, args
   - `/pgflow debug abc123-uuid` → subcommand `debug`, arg is a run ID
   - `/pgflow debug :process_order` → subcommand `debug`, arg is a flow slug
   - `/pgflow debug failed` → subcommand `debug`, show recent failures
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
- **Conditional steps**: `if:`/`if_not:` input-pattern gates with `when_unmet:` and `when_exhausted:` skip/fail behavior — see [references/conditional-steps.md](references/conditional-steps.md)
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
| `mix pgflow.gen.postgres_extensions_migration` | citext, pg_trgm, pgcrypto, pg_cron (`--no-cron` if unavailable) |
| `mix pgflow.gen.pgmq_migration` | SQL-only pgmq install (skip if the host already ships pgmq) |
| `mix pgflow.setup` | Wrapper migration: pgflow schema + Elixir helpers (`--dashboard` optional) |
| `mix pgflow.gen.flow_migration Module` | Generate migration to compile a flow |
| `mix pgflow.gen.job_migration Module` | Generate migration to compile a job |
| `mix pgflow.check_schema` | Verify database schema compatibility |

### Reference Files

Detailed guides available in `references/`:

| File | Content |
|------|---------|
| [bootstrap.md](references/bootstrap.md) | Full bootstrap walkthrough |
| [flow.md](references/flow.md) | Scaffold a new flow (subcommand reference) |
| [job.md](references/job.md) | Scaffold a new job (subcommand reference) |
| [step.md](references/step.md) | Add a step to a flow (subcommand reference) |
| [dashboard-setup.md](references/dashboard-setup.md) | Add the dashboard (subcommand reference) |
| [liveview-setup.md](references/liveview-setup.md) | Scaffold a LiveView (subcommand reference) |
| [debug.md](references/debug.md) | Debug runs and failures (subcommand reference) |
| [flows.md](references/flows.md) | Flow DSL — step, map, DAG deps, handler context |
| [conditional-steps.md](references/conditional-steps.md) | Conditional execution — if/if_not gates, when_unmet, when_exhausted, skip semantics |
| [jobs.md](references/jobs.md) | Job DSL — perform, cron, jobs vs flows |
| [config.md](references/config.md) | Configuration options, signal strategies, supervision |
| [liveview.md](references/liveview.md) | LiveClient API reference |
| [dashboard.md](references/dashboard.md) | Dashboard pages and features |
| [telemetry.md](references/telemetry.md) | Telemetry events and observability |

$ARGUMENTS
