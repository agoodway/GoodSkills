# PgFlow Configuration Reference

## Full Configuration

```elixir
config :my_app, MyApp.PgFlow,
  # Required
  repo: MyApp.Repo,

  # Flow and job modules to start workers for
  flows: [MyApp.Flows.ProcessOrder, MyApp.Flows.GenerateReport],
  jobs: [MyApp.Jobs.SendEmail],

  # Signal strategy: how workers detect new messages
  #   :polling  — adaptive jittered exponential backoff (1s→5s), no DB extensions needed
  #   :notify   — LISTEN/NOTIFY for low-latency wake-ups (requires pgmq 1.8.0+)
  signal_strategy: :polling,

  # Worker concurrency
  max_concurrency: 10,       # max parallel tasks per worker
  batch_size: 10,            # messages to fetch per poll cycle

  # Polling intervals (for :polling strategy)
  min_poll_interval: 1_000,  # 1 second (ms)
  max_poll_interval: 5_000,  # 5 seconds (ms)

  # Notify fallback (for :notify strategy)
  notify_fallback_interval: 30_000,  # safety net poll every 30s

  # Phoenix.PubSub for telemetry broadcasting to LiveViews
  pubsub: MyApp.PubSub,

  # Structured logging
  attach_default_logger: true
```

## Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `repo` | module | required | Ecto repository module |
| `flows` | list | `[]` | Flow modules to register and start workers for |
| `jobs` | list | `[]` | Job modules to register and start workers for |
| `signal_strategy` | atom | `:polling` | `:polling` or `:notify` |
| `max_concurrency` | integer | 10 | Max parallel tasks per worker process |
| `batch_size` | integer | 10 | Messages fetched per poll cycle |
| `min_poll_interval` | integer | 1000 | Min poll interval in ms (polling strategy) |
| `max_poll_interval` | integer | 5000 | Max poll interval in ms (polling strategy) |
| `notify_fallback_interval` | integer | 30000 | Safety net poll in ms (notify strategy) |
| `pubsub` | module | nil | Phoenix.PubSub module for LiveView broadcasting |
| `attach_default_logger` | boolean | false | Enable structured telemetry logging |

## Signal Strategies

### Polling (default)

Workers poll PGMQ at adaptive intervals with jittered exponential backoff:
- Starts at `min_poll_interval` (1s)
- Backs off to `max_poll_interval` (5s) when idle
- Drops back to `min_poll_interval` when messages found

No additional database extensions required. Good for most workloads.

### Notify

Uses PostgreSQL LISTEN/NOTIFY for near-instant wake-ups when messages arrive:
- Requires pgmq 1.8.0+ (for `pgmq.enable_notify_insert`)
- Falls back to polling every `notify_fallback_interval` as a safety net
- Lower latency than polling for bursty workloads

```elixir
config :my_app, MyApp.PgFlow,
  signal_strategy: :notify,
  notify_fallback_interval: 30_000
```

## Supervision Tree

PgFlow starts this supervision tree:

```
PgFlow.Supervisor
├── PgFlow.FlowRegistry (ETS-backed flow lookup)
├── PgFlow.WorkerSupervisor (DynamicSupervisor)
│   ├── Worker.Server (one per flow)
│   ├── Worker.Server (one per job)
│   └── ...
└── PgFlow.Signal.Notify (if :notify strategy)
```

Each `Worker.Server` is a GenServer that:
1. Polls PGMQ for messages
2. Reserves messages and creates tasks
3. Dispatches tasks to `Task.Supervisor` for crash isolation
4. Marks tasks complete/failed based on handler results
5. Handles retries with exponential backoff

## Environment-Specific Configuration

```elixir
# config/dev.exs
config :my_app, MyApp.PgFlow,
  attach_default_logger: true,
  max_concurrency: 2

# config/test.exs — typically don't start PgFlow in tests
# Omit PgFlow from supervision tree or use:
config :my_app, MyApp.PgFlow,
  flows: [],
  jobs: []

# config/prod.exs
config :my_app, MyApp.PgFlow,
  signal_strategy: :notify,
  max_concurrency: 20,
  batch_size: 20
```
