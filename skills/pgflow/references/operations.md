# Runtime operations

## Workers

All worker controls act on the local BEAM node only. They do not reach other nodes or TypeScript workers.

- `PgFlow.start_worker(Module, opts \\ [])` accepts only `:repo`, `:max_concurrency`, and `:batch_size`; any other key or an invalid value raises `ArgumentError`. Limits resolve from the global config, then the module's `worker_options` entry, then call-time options. Returns `{:ok, pid}`; when a worker is already running it returns that pid if no limits were passed or they match its configured (start-time) limits, else `{:error, {:conflicting_worker_options, pid}}`. `{:error, :not_started}` means a concurrent supervisor restart started a replacement that exited before it could be returned; retrying is safe.
- Starts and crash restarts cannot leave two workers polling the same module: the supervised start function returns `:ignore` when a live worker is already registered, and the explicit start then returns that worker.
- `PgFlow.stop_worker(Module)` is the operator stop: it drains active tasks, removes the child and any concurrent supervised replacement, and returns `:ok` or `{:error, :not_found}`. It holds the same per-module lock as `start_worker/2`, so a concurrent start waits for the drain and then starts a fresh worker. Do not call `PgFlow.Worker.Server.stop(pid)` as an operator primitive.
- Workers use transient restart. Crashes and `:deprecated` exits replace the child with the options it was started with; a normal operator stop is final.
- Database-driven replacement marks `deprecated_at`; the next heartbeat drains and exits. Deprecations share the supervisor budget of 10 restarts in 60 seconds, so rotate in small batches with crash headroom.

### Runtime scaling

```elixir
{:ok, status} = PgFlow.scale_worker(MyApp.Flows.Import, max_concurrency: 6)
PgFlow.check_worker(MyApp.Flows.Import)
#=> %{module: MyApp.Flows.Import, pid: pid, lifecycle: :running, max_concurrency: 6,
#     batch_size: 10, configured_max_concurrency: 10, configured_batch_size: 10, active: 2}
```

- `scale_worker/2` needs at least one of `:max_concurrency` or `:batch_size` (positive integers) and raises `ArgumentError` otherwise. It returns `{:ok, check_map}`, `{:error, :not_found}` when no local worker is registered (including while a crashed worker restarts), or `{:error, :not_running}` while the worker is not `:running` (for example stopping).
- `check_worker/2` returns the map above or `nil`. It accepts only `:timeout`.
- Both take `:timeout` (default `5_000` ms, or `:infinity`). On expiry the caller exits with `{:timeout, {GenServer, :call, _}}`; a timed-out scale may already have been applied.
- Scale-down never interrupts active handlers; new claims respect the lower limit. Any scale that leaves free slots polls immediately.
- Scaled limits live in memory. A restart restores the configured values from config, `worker_options`, or `start_worker/2`.

## Queue identity

The durable identity is `(queue_name, message_id)`, not `message_id`. Flow slugs keep logical case; flow-mode queues use lowercase slugs and must be nonempty and at most 47 characters. Case-insensitive slug collisions are invalid. Claim, recovery, run deletion, and prune operations use persisted routes. Elixir refuses step-mode flows at boot. A TypeScript step-mode worker is a separate deployment.

## Notify triggers

In `:notify` mode with `notify_trigger: :deferred`, worker boot leaves each flow queue's pgmq insert trigger `DEFERRABLE INITIALLY DEFERRED`, so long producer transactions do not block other producers. Operational consequences:

- A transaction that sends to a queue and then runs `pgmq.drop_queue` or `pgmq.purge_queue` on it fails with "pending trigger events" unless it first calls `PgFlow.Queries.Pgmq.flush_notify_events/1`. `PgFlow.delete_flow/1` flushes itself; upstream SQL `delete_flow_and_data` does not.
- `PgFlow.Queries.Pgmq.enable_notify_insert/4` returns `{:error, :in_transaction}` inside a transaction on the repo.
- `ALTER EXTENSION pgmq UPDATE` can rebuild triggers as immediate; the next boot defers them again.
- `pgmq.notify_insert_throttle` is UNLOGGED. `PgFlow.Signal.Notify` restores missing rows every 30 seconds for the queues it listens on, and each boot restores them too.

## Recovery

Stalled-task recovery is supervised and defaults to a 15-second sweep. A task is eligible only when task, step, and run are all `started` and the effective timeout plus stale threshold elapsed. Recovery uses `FOR UPDATE SKIP LOCKED`, preserves attempt count, increments `requeued_count`, clears ownership/start time, and resets visibility on the persisted queue.

After three requeues the next sweep archives the message and records `permanently_stalled_at`. The recovery process then calls `pgflow.escalate_permanently_stalled()` as a separate query. Escalation locks the run, step, then task; raises the task's attempt count to the effective maximum; and calls `fail_task`, so the step's `when_exhausted` policy terminalizes the task and resolves dependents. Do not call escalation inside a transaction that holds recovery's task-row locks. Alert on stamped tasks whose run remains `started` after escalation.

## Run deletion, pruning, and cancellation

PgFlow has no per-run cancel or fail API. When run history may be discarded, use `PgFlow.Runs.delete(repo, run_id)` or, from SQL/Hasura, `SELECT pgflow.delete_run('<uuid>');`:

- Locks the run, then every task row of the run, then deletes the exact live and archived messages by persisted `(queue_name, message_id)`, then the task, step-state, and run rows. This order keeps it free of lock cycles with claims, recovery, and pruning.
- An absent run is a no-op (`:ok`). A run whose persisted flow slug fails the slug rules raises SQLSTATE `PGF01`, which `Runs.delete/2` returns as `{:error, :invalid_flow_slug}` without deleting anything. Other database errors return `{:error, %Postgrex.Error{}}`.
- It removes history and does not interrupt a running handler; a handler that finishes afterwards finds no task to complete. Workers, definitions, queues, and unrelated messages are untouched.

`pgflow.prune_data_older_than(interval, text[])` removes old completed/failed runs and their live/archive messages by persisted task route, locking eligible runs by `run_id` before their task rows. Stale-worker deletion is global even when pruning has a flow-slug filter. Payload-only orphan messages without a persisted task route are intentionally not counted or removed by `Runs.count_queue_messages/4`, `Runs.delete/2`, or pruning.

Handlers are at-least-once. SQL may later mark a step skipped while a handler is already running, so external side effects require their own idempotency key or guard.
