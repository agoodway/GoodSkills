# PgFlow Configuration Reference

`PgFlow.Config.validate!/1` checks these options when `{PgFlow, opts}` starts and raises `ArgumentError` on invalid values.

## Full Configuration

```elixir
config :my_app, PgFlow,
  # Required
  repo: MyApp.Repo,

  # Flow and job modules to start workers for
  flows: [MyApp.Flows.ProcessOrder, MyApp.Flows.Import],
  jobs: [MyApp.Jobs.SendEmail],

  # Signal strategy: how workers detect new messages
  #   :polling  adaptive jittered exponential backoff (1s to 5s), no extensions needed
  #   :notify   LISTEN/NOTIFY wake-ups (requires pgmq 1.8.0+)
  signal_strategy: :polling,

  # Global worker limits
  max_concurrency: 10,       # max parallel tasks per worker
  batch_size: 10,            # messages to fetch per poll cycle

  # Per-module limits; keys must also appear in :flows or :jobs
  worker_options: %{
    MyApp.Flows.Import => [max_concurrency: 4, batch_size: 2]
  },

  # Polling intervals (for :polling strategy)
  min_poll_interval: 1_000,
  max_poll_interval: 5_000,

  # Notify settings (for :notify strategy)
  notify_fallback_interval: 30_000,  # safety net poll
  notify_throttle_ms: 250,
  notify_trigger: :deferred,         # or :pgmq_default
  notify_lock_timeout_ms: 2_000,

  # Liveness and stalled-task recovery
  heartbeat_interval: 10_000, # maximum 20s
  recovery_interval: 15_000,
  stale_threshold: 60,        # seconds beyond effective step/flow timeout

  # Phoenix.PubSub for telemetry broadcasting to LiveViews
  pubsub: MyApp.PubSub,

  # Default telemetry logger
  attach_default_logger: false
```

## Configuration Options

| Option                     | Type          | Default     | Description                                                                         |
| -------------------------- | ------------- | ----------- | ----------------------------------------------------------------------------------- |
| `repo`                     | module        | required    | Ecto repository module                                                              |
| `flows`                    | list          | `[]`        | Flow modules to register and start workers for                                      |
| `jobs`                     | list          | `[]`        | Job modules to register and start workers for                                       |
| `worker_name`              | string or nil | `nil`       | Worker name prefix in logs (default `pgflow-{flow_slug}`)                           |
| `signal_strategy`          | atom          | `:polling`  | `:polling` or `:notify`                                                             |
| `max_concurrency`          | pos integer   | 10          | Max parallel tasks per worker process                                               |
| `batch_size`               | pos integer   | 10          | Messages fetched per poll cycle                                                     |
| `worker_options`           | map           | `%{}`       | Module to `[max_concurrency:, batch_size:]`; keys must be in `flows` or `jobs`      |
| `min_poll_interval`        | pos integer   | 1000        | Min poll interval in ms; must be <= `max_poll_interval`                             |
| `max_poll_interval`        | pos integer   | 5000        | Max poll interval in ms; maximum 300000                                             |
| `notify_fallback_interval` | pos integer   | 30000       | Safety net poll in ms (notify strategy); maximum 600000                             |
| `notify_throttle_ms`       | integer >= 0  | 250         | Notify trigger throttle in ms (`0` notifies every insert)                           |
| `notify_trigger`           | atom          | `:deferred` | `:deferred` recreates pgmq's trigger deferred; `:pgmq_default` keeps pgmq's trigger |
| `notify_lock_timeout_ms`   | pos integer   | 2000        | How long a `:deferred` install waits for the queue table lock before retrying       |
| `heartbeat_interval`       | pos integer   | 10000       | Persisted worker heartbeat in ms; maximum 20000                                     |
| `recovery_interval`        | pos integer   | 15000       | Interval between stalled-task recovery sweeps in ms                                 |
| `stale_threshold`          | pos integer   | 60          | Seconds added beyond effective task timeout before recovery                         |
| `pubsub`                   | module or nil | `nil`       | Phoenix.PubSub module for LiveView broadcasting                                     |
| `attach_default_logger`    | boolean       | `false`     | Attach the default telemetry logger                                                 |

Validation also raises when two configured flows or jobs share a queue name (case-insensitive slug collision), when a `worker_options` key is not listed in `flows` or `jobs`, or when a `worker_options` entry has an unknown key or invalid value.

## Worker Limits

Effective limits resolve in order: global `max_concurrency`/`batch_size`, then `worker_options[module]`, then `PgFlow.start_worker/2` options. A module started only through `start_worker/2` (not listed in `flows` or `jobs`) takes its overrides from that call. Runtime changes go through `PgFlow.scale_worker/2` and reset on restart; see [operations.md](operations.md).

## Signal Strategies

### Polling (default)

Workers poll PGMQ at adaptive intervals with jittered exponential backoff:

- Starts at `min_poll_interval` (1s)
- Backs off to `max_poll_interval` (5s) when idle
- Drops back to `min_poll_interval` when messages are found

No additional database extensions required. Good for most workloads.

### Notify

Uses PostgreSQL LISTEN/NOTIFY for near-instant wake-ups when messages arrive:

- Requires pgmq 1.8.0+ (for `pgmq.enable_notify_insert`)
- Falls back to polling every `notify_fallback_interval`
- `PgFlow.Signal.Notify` restores missing `pgmq.notify_insert_throttle` rows every 30 seconds; that table is UNLOGGED, so crash recovery and Neon compute restarts empty it

With `notify_trigger: :deferred`, each boot leaves every flow queue's insert trigger `DEFERRABLE INITIALLY DEFERRED`, so the throttle row lock is held only during a producer's commit. When the trigger is already deferred the boot only reconciles the throttle row, with no DDL. Otherwise it takes a per-queue advisory lock, waits at most `notify_lock_timeout_ms` for the queue table lock, and retries with backoff on `lock_not_available`. Consequences:

- Trigger errors fail the producer's COMMIT rather than its INSERT.
- Sending to a queue and then dropping or purging it in the same transaction needs `PgFlow.Queries.Pgmq.flush_notify_events/1` first (`PgFlow.delete_flow/1` does this).
- REPEATABLE READ and SERIALIZABLE producers can see SQLSTATE 40001 at COMMIT; retry them, keep them short, or use `:pgmq_default`.

Use one `notify_trigger` value on every node; a `:pgmq_default` node puts pgmq's immediate trigger back on its boot. Run `mix pgflow.check_schema --notify-trigger pgmq_default` when using `:pgmq_default`.

```elixir
config :my_app, PgFlow,
  signal_strategy: :notify,
  notify_fallback_interval: 30_000
```

## Supervision Tree

PgFlow starts this tree (`:rest_for_one`):

```
PgFlow.Supervisor
├── PgFlow.TaskSupervisor
├── PgFlow.Signal.Notify (only for :notify)
├── PgFlow.WorkerSupervisor (DynamicSupervisor)
│   ├── Worker.Server (one per flow)
│   ├── Worker.Server (one per job)
│   └── ...
├── PgFlow.Worker.StalledTaskRecovery
└── PgFlow.FlowStarter (definition/bootstrap convergence)
```

Each `Worker.Server` is a GenServer that:

1. Polls PGMQ for messages
2. Reserves messages and creates tasks
3. Dispatches tasks to `Task.Supervisor` for crash isolation
4. Marks tasks complete/failed based on handler results
5. Handles retries with exponential backoff

Workers are transient children: crashes and database deprecation exits restart,
while `PgFlow.stop_worker/1` drains and durably removes the child. Do not use the
server PID stop call as an operator primitive. See [operations.md](operations.md).

## Environment-Specific Configuration

```elixir
# config/dev.exs
config :my_app, PgFlow,
  attach_default_logger: true,
  max_concurrency: 2

# config/test.exs: do not start PgFlow workers.
# Keep `config :pgflow, repo: MyApp.Repo` so PgFlow.enqueue/2 resolves the repo.
# Omit `:my_app, PgFlow` entirely so the host starts no PgFlow children.

# config/prod.exs
config :my_app, PgFlow,
  signal_strategy: :notify,
  max_concurrency: 20,
  batch_size: 20
```
