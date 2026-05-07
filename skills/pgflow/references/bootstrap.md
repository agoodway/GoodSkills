# pgflow bootstrap

Add PgFlow to an existing Phoenix application. This walks through dependency installation, database setup, configuration, supervision tree integration, and creating a first flow and job.

## Prerequisites

Verify before starting:
1. Phoenix 1.7+ application with PostgreSQL
2. Ecto configured with a Repo module
3. Phoenix.PubSub in supervision tree (standard in Phoenix apps)

## Phase 1: Add Dependency

Add PgFlow to `mix.exs`:

```elixir
defp deps do
  [
    {:pgflow, "~> 0.1.0"}
  ]
end
```

```bash
mix deps.get
```

## Phase 2: Database Setup

### 2.1 Copy Core Migrations

```bash
mix pgflow.copy_migrations
```

This copies the pgflow schema migrations that create:
- `pgflow` schema with flows, steps, runs, step_states, step_tasks tables
- PGMQ extension and queue infrastructure
- SQL functions for flow orchestration

### 2.2 Generate Worker Extensions

```bash
mix pgflow.gen.extensions_migration
```

This adds Elixir-specific worker tracking tables and functions.

### 2.3 Run Migrations

```bash
mix ecto.migrate
```

### 2.4 Verify Schema

```bash
mix pgflow.check_schema
```

## Phase 3: Configuration

Add PgFlow configuration to `config/config.exs`:

```elixir
config :my_app, MyApp.PgFlow,
  repo: MyApp.Repo,
  flows: [],
  jobs: [],
  signal_strategy: :polling,
  max_concurrency: 10,
  batch_size: 10,
  pubsub: MyApp.PubSub,
  attach_default_logger: true
```

See [config.md](config.md) for all configuration options and signal strategies.

## Phase 4: Supervision Tree

Add PgFlow to the application supervision tree in `lib/my_app/application.ex`:

```elixir
def start(_type, _args) do
  children = [
    MyApp.Repo,
    MyAppWeb.Endpoint,
    {PgFlow, Application.fetch_env!(:my_app, MyApp.PgFlow)}
  ]

  opts = [strategy: :one_for_one, name: MyApp.Supervisor]
  Supervisor.start_link(children, opts)
end
```

## Phase 5: Create a Flow

See [flows.md](flows.md) for the full Flow DSL reference.

### 5.1 Define the Flow Module

Create `lib/my_app/flows/example_flow.ex`:

```elixir
defmodule MyApp.Flows.ExampleFlow do
  use PgFlow.Flow

  @flow queue: :example_flow, max_attempts: 3, base_delay: 5, timeout: 60

  step :validate do
    fn input, _ctx ->
      %{valid: true, data: input}
    end
  end

  step :process, depends_on: [:validate] do
    fn deps, _ctx ->
      %{processed: true, source: deps.validate}
    end
  end

  step :finalize, depends_on: [:process] do
    fn deps, _ctx ->
      %{status: "completed"}
    end
  end
end
```

### 5.2 Register the Flow

Add the module to the `flows` list in config:

```elixir
config :my_app, MyApp.PgFlow,
  repo: MyApp.Repo,
  flows: [MyApp.Flows.ExampleFlow],
  # ...
```

### 5.3 Compile to Database

```bash
mix pgflow.gen.flow MyApp.Flows.ExampleFlow
mix ecto.migrate
```

### 5.4 Start a Flow

```elixir
{:ok, run_id} = PgFlow.start_flow(:example_flow, %{"key" => "value"})
```

## Phase 6: Create a Job (Optional)

See [jobs.md](jobs.md) for the Job DSL reference.

Create `lib/my_app/jobs/example_job.ex`:

```elixir
defmodule MyApp.Jobs.ExampleJob do
  use PgFlow.Job

  @job queue: :example_job, max_attempts: 5, base_delay: 10, timeout: 120

  perform :run do
    fn input, _ctx ->
      %{result: "processed #{input["id"]}"}
    end
  end
end
```

Register, compile, and enqueue:

```elixir
# Add to config
config :my_app, MyApp.PgFlow,
  jobs: [MyApp.Jobs.ExampleJob],
  # ...
```

```bash
mix pgflow.gen.job MyApp.Jobs.ExampleJob
mix ecto.migrate
```

```elixir
# Enqueue
{:ok, run_id} = PgFlow.enqueue(MyApp.Jobs.ExampleJob, %{"id" => 42})
```

## Phase 7: LiveView Integration (Optional)

See [liveview.md](liveview.md) for the LiveClient API.

```elixir
defmodule MyAppWeb.FlowLive do
  use MyAppWeb, :live_view
  alias PgFlow.LiveClient

  def mount(_params, _session, socket) do
    {:ok, LiveClient.init(socket, pubsub: MyApp.PubSub)}
  end

  def handle_event("start", params, socket) do
    case LiveClient.start_flow(socket, :example_flow, params, as: :run) do
      {:ok, socket} -> {:noreply, socket}
      {:error, reason, socket} -> {:noreply, put_flash(socket, :error, reason)}
    end
  end

  def handle_info({:pgflow, _, _} = msg, socket) do
    {:noreply, LiveClient.handle_info(msg, socket)}
  end
end
```

## Phase 8: Dashboard (Optional)

See [dashboard.md](dashboard.md) for dashboard setup.

```bash
mix pgflow_dashboard.gen.migration
mix ecto.migrate
```

In `router.ex`:

```elixir
import PgFlowDashboard.Router

scope "/" do
  pipe_through [:browser]
  pgflow_dashboard "/pgflow", repo: MyApp.Repo, pubsub: MyApp.PubSub
end
```

## Verification Checklist

- [ ] PgFlow dependency added and fetched
- [ ] Core migrations copied and run
- [ ] Worker extensions migration generated and run
- [ ] Schema verified with `mix pgflow.check_schema`
- [ ] Configuration added to `config.exs`
- [ ] PgFlow added to supervision tree
- [ ] At least one flow or job defined
- [ ] Flow/job compiled to database
- [ ] Flow starts and completes successfully
