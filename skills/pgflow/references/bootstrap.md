# Bootstrap PgFlow

Add PgFlow to an existing Phoenix application. Verify the installed dependency and its documentation first; a path/git checkout may contain capabilities that published Hex `0.4.0` does not.

## Prerequisites

- Elixir 1.18+, PostgreSQL 17+, and an Ecto repo.
- `citext`, `pg_trgm`, `pgcrypto`, and pgmq.
- `pg_cron` only for cron flows/jobs; it also requires server configuration and a PostgreSQL restart.

## Install

Add the intended released, git, or path dependency and run `mix deps.get`. Do not silently replace a requested local/git build with `{:pgflow, "~> 0.3.4"}`.

Generate consumer-owned wrapper migrations in this order:

```bash
mix pgflow.gen.postgres_extensions_migration # add --no-cron if unsupported
mix pgflow.gen.pgmq_migration                # omit when the host supplies pgmq
mix pgflow.setup
mix ecto.migrate
mix pgflow.check_schema --repo MyApp.Repo
```

`mix pgflow.setup` installs core plus Elixir helpers. An already-applied wrapper never reruns after a dependency bump; use the coordinated upgrade workflow in [upgrading.md](upgrading.md).

## Configure and supervise

```elixir
config :my_app, MyApp.PgFlow,
  repo: MyApp.Repo,
  flows: [MyApp.Flows.ExampleFlow],
  jobs: [],
  signal_strategy: :polling,
  pubsub: MyApp.PubSub
```

Start PgFlow after the repo:

```elixir
children = [
  MyApp.Repo,
  {PgFlow, Application.fetch_env!(:my_app, MyApp.PgFlow)},
  MyAppWeb.Endpoint
]
```

Polling is the safest portable default. `:notify` requires compatible pgmq notification functions and retains fallback polling.

Workers compile new definitions and verify existing shapes before polling. Production mismatches fail closed rather than replacing history. Do not treat `PgFlow.FlowStarter.ready?/0` alone as usable readiness; inspect `status/0`, `module_status/1`, `healthy?/0`, and persisted `PgFlow.Workers.healthy?/2`.

The migration role needs extension and schema/function/type/table/index DDL
permissions. The runtime role needs schema usage, function execution, worker DML,
and startup permission for `ensure_flow_compiled` and `pgmq.create`; alternatively,
pre-provision definitions and prove startup with the restricted role.

## Verify the first definition

Define/register a flow or job, generate its migration if your deployment workflow uses definition migrations, migrate, start a run, and assert its terminal state:

```bash
mix pgflow.gen.flow_migration MyApp.Flows.ExampleFlow
mix ecto.migrate
```

```elixir
{:ok, run_id} = PgFlow.start_flow(:example_flow, %{"key" => "value"})
{:ok, run} = PgFlow.get_run_with_states(run_id)
```

Run the gates in [compatibility.md](compatibility.md). Without `PGFLOW_REQUIRE_DB=1`, database tests may be silently excluded.
