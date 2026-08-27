# pgflow bootstrap

Add PgFlow to an existing Phoenix application. This walks through dependency installation, database setup, configuration, supervision tree integration, and creating a first flow and job.

## Prerequisites

Verify before starting:
1. Phoenix 1.7+ application with PostgreSQL
2. Ecto configured with a Repo module
3. Phoenix.PubSub in supervision tree (standard in Phoenix apps)

## Phase 1: Add Dependency

Add PgFlow to `mix.exs` (GitHub `main`, matching Goodviews):

```elixir
defp deps do
  [
    {:pgflow, github: "agoodway/pgflow", branch: "main"}
  ]
end
```

```bash
mix deps.get
```

## Phase 2: Database Setup

Generate consumer migrations. Each writes one wrapper into `priv/repo/migrations/`:

```bash
# 1. citext, pg_trgm, pgcrypto, pg_cron (`--no-cron` if pg_cron isn't available)
mix pgflow.gen.postgres_extensions_migration

# 2. pgmq via SQL (skip on hosts that already ship pgmq, e.g. Supabase)
mix pgflow.gen.pgmq_migration

# 3. pgflow schema + Elixir helpers. No `--dashboard` unless requested.
mix pgflow.setup

mix ecto.migrate
mix pgflow.check_schema
```

Then edit generated migrations (Goodviews pattern):

- Rename modules to `MyApp.Repo.Migrations.*` if the generator emits `PgFlow.Repo.Migrations.*`
- Keep `@disable_ddl_transaction true` / `@disable_migration_lock true` on the extensions migration
- Wrap `CREATE EXTENSION pg_cron` and later `cron.schedule` / `cron.unschedule` so they run only when `current_setting('cron.database_name', true) IS NOT DISTINCT FROM current_database()`
- citext uses `IF NOT EXISTS`; do not drop citext on down if auth tables already own it

## Phase 3: Configuration

**File:** `config/config.exs` — repo for enqueue without a running supervisor (tests):

```elixir
config :pgflow, repo: MyApp.Repo
```

**File:** `config/runtime.exs` — omit in test so Application does not start workers:

```elixir
if config_env() != :test do
  config :my_app, PgFlow,
    repo: MyApp.Repo,
    flows: [],
    jobs: [],
    signal_strategy: :notify,
    max_concurrency: 10
end
```

Do **not** set `:pubsub` unless adding LiveClient / dashboard. See [config.md](config.md) for all options.

## Phase 4: Supervision Tree

Add a config-gated child in `lib/my_app/application.ex`. Do **not** call `Mix.env/0`. Tests omit `:my_app, PgFlow`, so this starts nothing there:

```elixir
children =
  [
    MyApp.Repo,
    {Phoenix.PubSub, name: MyApp.PubSub}
  ] ++
    pgflow_children() ++
    [
      MyAppWeb.Endpoint
    ]

defp pgflow_children do
  case Application.get_env(:my_app, PgFlow) do
    opts when is_list(opts) -> [{PgFlow, opts}]
    _other -> []
  end
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
      %{processed: true, source: deps["validate"]}
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
config :my_app, PgFlow,
  repo: MyApp.Repo,
  flows: [MyApp.Flows.ExampleFlow],
  # ...
```

### 5.3 Compile to Database

```bash
mix pgflow.gen.flow_migration MyApp.Flows.ExampleFlow
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
config :my_app, PgFlow,
  jobs: [MyApp.Jobs.ExampleJob],
  # ...
```

```bash
mix pgflow.gen.job_migration MyApp.Jobs.ExampleJob
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

- [ ] PgFlow dependency added (`github: "agoodway/pgflow"`) and fetched
- [ ] Extensions + pgmq + `mix pgflow.setup` migrations generated, modules renamed, cron guarded, migrated
- [ ] Schema verified with `mix pgflow.check_schema`
- [ ] `config :pgflow, repo:` plus non-test `:my_app, PgFlow` config
- [ ] Config-gated `{PgFlow, opts}` child in the supervision tree (no workers in test)
- [ ] At least one flow or job defined
- [ ] Flow/job compiled to database (`gen.flow_migration` / `gen.job_migration`)
- [ ] Flow starts and completes successfully
