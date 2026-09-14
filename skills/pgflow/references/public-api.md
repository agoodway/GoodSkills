# Typed operational API

Prefer these repository-explicit APIs over handwritten SQL. They return PgFlow schemas or typed summary structs and keep dashboard/application queries aligned with the database contract.

## Definitions and schedules

```elixir
PgFlow.Definitions.get_flow(MyApp.Repo, "process_order")
PgFlow.Definitions.list_flows(MyApp.Repo, cursor: nil, limit: 50)
PgFlow.Definitions.list_steps(MyApp.Repo, "process_order")
PgFlow.Definitions.list_deps(MyApp.Repo, "process_order")
PgFlow.Definitions.get_job(MyApp.Repo, "send_email")
PgFlow.Definitions.list_jobs(MyApp.Repo)
PgFlow.Definitions.get_cron(MyApp.Repo, "daily_report")
PgFlow.Definitions.list_crons(MyApp.Repo)
```

`get_*` returns `{:ok, summary}` or `{:error, :not_found}`. Flow/job/cron
summary lists are deterministic and cursor/limit based; `list_steps/2` and
`list_deps/2` return the complete ordered collection. Non-UTC cron `next_run_at`
requires an IANA-compatible `Calendar.TimeZoneDatabase`.

`PgFlow.Definitions.unschedule/2` safely removes only the current database role's `pgflow:<slug>` cron entry. An absent schedule is a no-op; a visible foreign-owned schedule returns `{:error, :not_owned}`.

## Runs and tasks

```elixir
PgFlow.Runs.get(MyApp.Repo, run_id)
PgFlow.Runs.get_with_states(MyApp.Repo, run_id)
PgFlow.Runs.list(MyApp.Repo, flow_slug: "process_order", status: "failed", limit: 50)
PgFlow.Runs.count(MyApp.Repo, flow_type: "flow", time_range: :last_24h)
PgFlow.Runs.list_step_states(MyApp.Repo, run_id)
PgFlow.Runs.list_run_tasks(MyApp.Repo, run_id)
PgFlow.Runs.get_step_task(MyApp.Repo, run_id, "charge", 0)
PgFlow.Runs.history(MyApp.Repo, "process_order", limit: 20)
```

Run filters include `flow_slug`, `status`, `flow_type`, time bounds/range, `input_contains`, cursor, and limit.

Operational actions are route-aware:

- `PgFlow.Runs.count_queue_messages/4` counts live/archive messages by persisted `(queue_name, message_id)`.
- `PgFlow.Runs.make_available/2` resets queued task visibility for a run.
- `PgFlow.Runs.delete/2` transactionally removes a run plus its routed queue/lifecycle data; an absent run is a no-op.

## Workers and metrics

```elixir
PgFlow.Workers.healthy?(MyApp.Repo, "process_order")
PgFlow.Workers.get(MyApp.Repo, worker_id)
PgFlow.Workers.list(MyApp.Repo, flow_slug: "process_order", health_status: :healthy)
PgFlow.Workers.list_tasks(MyApp.Repo, worker_id)
PgFlow.Metrics.overview(MyApp.Repo)
```

Worker health is heartbeat-derived: healthy under 30 seconds, stale through 60 seconds, then dead; stopped/deprecated workers are dead. `PgFlow.Workers.delete/2` deletes only the worker row and clears task attribution via the foreign key—it does not stop a live worker. Use `PgFlow.stop_worker/1` for an operator stop.

Use raw SQL only for objects not exposed here (migration preflight, exact function signatures, pgmq internals). Validate identifiers and summarize results rather than exposing raw rows.
