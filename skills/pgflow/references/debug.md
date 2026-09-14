# Debug PgFlow

Inspect persisted state without mutating it. Prefer `PgFlow.Runs`, `PgFlow.Workers`, `PgFlow.Definitions`, and `PgFlow.Metrics` over handwritten SQL; see [public-api.md](public-api.md).

## Resolve the target

- `/pgflow debug <uuid>`: one run.
- `/pgflow debug :process_order`: recent runs for a flow.
- `/pgflow debug failed`: recent failures.
- Without a target, ask which of those the user means.

## Read state

Run and all step states:

```elixir
{:ok, run} = PgFlow.Runs.get_with_states(MyApp.Repo, run_id)
{:ok, tasks} = PgFlow.Runs.list_run_tasks(MyApp.Repo, run_id)
```

Recent flow runs or failures:

```elixir
{:ok, runs} = PgFlow.Runs.list(MyApp.Repo,
  flow_slug: "process_order",
  limit: 20
)

{:ok, failures} = PgFlow.Runs.list(MyApp.Repo,
  status: "failed",
  limit: 20
)
```

Worker and queue health:

```elixir
{:ok, healthy?} = PgFlow.Workers.healthy?(MyApp.Repo, "process_order")
{:ok, workers} = PgFlow.Workers.list(MyApp.Repo, flow_slug: "process_order")
{:ok, queued} = PgFlow.Runs.count_queue_messages(
  MyApp.Repo,
  "process_order",
  run_id,
  location: :all
)
```

Use `PgFlow.FlowStarter.module_status(Module)` to distinguish pending/retrying, succeeded, and permanently failed startup. `ready?/0` means every module reached a terminal state; it can be true when modules failed. Run `mix pgflow.check_schema --repo MyApp.Repo` for schema/signature failures.

## Interpret state

- `condition_unmet`, `dependency_skipped`, and `handler_failed` are expected skip reasons; a run with skipped steps can complete.
- A non-cascade skipped dependency is absent from a dependent handler's input map, not present as `nil`.
- `attempts_count` is aggregated per task row. Use structured logs/telemetry keyed by run, step, and task index for an attempt-by-attempt timeline.
- A started task beyond its effective timeout plus stale threshold is eligible for recovery. `permanently_stalled_at` means the recovery requeue cap was exceeded; it does not itself terminalize the run.
- Message ownership is `(queue_name, message_id)`, never message ID alone.
- A growing queue with no healthy persisted worker usually points to bootstrap failure, a stopped worker, stale heartbeat, or database connectivity—not merely an empty local process registry.

## Report

Summarize run status/timing, step states, task attempt/requeue data, worker health, queue count, last errors, and the evidence-based diagnosis. Do not invent individual attempt history from the aggregate task row.

Keep this command read-only. If mutation is requested, name the exact public operation and its consequences: `Runs.make_available/2`, `Runs.delete/2`, `Definitions.unschedule/2`, or `PgFlow.stop_worker/1`. Never delete a persisted worker row as a substitute for stopping its live process.
