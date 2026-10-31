# Bootstrap PgFlow

Add PgFlow to an existing Phoenix application. Verify the installed dependency and its documentation first; a path/git checkout may contain capabilities the latest published Hex release does not. PgFlow 0.7.0 installs core V03 and helpers V07 (upstream pgflow 0.17.2); 0.6.0 was never published to Hex.

## Prerequisites

- Elixir 1.18+, PostgreSQL 17+, and an Ecto repo.
- `citext`, `pg_trgm`, `pgcrypto`, and pgmq.
- `pg_cron` only for cron flows/jobs; it also requires server configuration and a PostgreSQL restart.

## Install

Add the intended released, git, or path dependency (for Hex, `{:pgflow, "~> 0.7.0"}`) and run `mix deps.get`. Do not silently replace a requested local/git build with a Hex version. Also depend on `phoenix`, `phoenix_live_view`, and `livefilter`: they are optional in pgflow's `mix.exs`, but its dashboard modules compile unconditionally.

Generate consumer-owned wrapper migrations in this order. Extensions and pgmq must migrate before the setup wrapper, both on first install and on every replay from an empty database:

```bash
mix pgflow.gen.postgres_extensions_migration # add --no-cron if unsupported
mix pgflow.gen.pgmq_migration                # omit when the host supplies pgmq
mix pgflow.setup
mix ecto.migrate
mix pgflow.check_schema --repo MyApp.Repo
```

`mix pgflow.gen.pgmq_migration` downloads the pgmq SQL bundle (default 1.11.0, sha256-checked) from GitHub at generation time, so it needs network access once. It writes `priv/pgflow/pgmq/pgmq-<version>.sql` plus an `install_pgmq` migration; commit both, and `mix ecto.migrate` then runs offline.

`mix pgflow.setup` installs core plus Elixir helpers in a wrapper pinned to explicit versions (`up(version: 3)`, `up(version: 7)` on 0.7.0). Keep wrappers pinned; a bare `up()` installs whatever version the dependency bundles when history is replayed. Wrappers generated before 0.7.0 are bare; pin them as in [upgrading.md](upgrading.md). An already-applied wrapper never reruns after a dependency bump; use the coordinated upgrade workflow in [upgrading.md](upgrading.md).

When the repo sets a custom `priv:` (or exists only in `MIX_ENV=test`, as in many libraries), run the generators with that `MIX_ENV` and check where each file landed. `mix pgflow.setup` can fall back to `priv/repo` and `mix pgflow.gen.pgmq_migration` defaults to `priv/repo/migrations`; pass `--migrations-path` to either. `mix pgflow.gen.postgres_extensions_migration` has no path flag, so move its file. A library that leaves the schema to its host does not ship these migrations; see [upgrading.md](upgrading.md#upgrade-a-library).

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

Polling is the safest portable default. `:notify` requires pgmq 1.8.0+ and retains fallback polling; by default its first boot recreates each flow queue's pgmq insert trigger as `DEFERRABLE INITIALLY DEFERRED` (see [config.md](config.md)). Per-module limits go in `worker_options`; unknown keys raise at boot.

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

Scripts that start PgFlow without booting the app (for example `mix run --no-start`) must call `Application.ensure_all_started(:pgflow)` first; it starts `PgFlow.FlowRegistry`, which `PgFlow.FlowStarter` needs.

Run the consumer gates in [compatibility.md](compatibility.md).
