# Upgrade PgFlow schema

Use this when a dependency bump adds a core or helpers migration. PgFlow 0.7.0 targets upstream pgflow 0.17.2 (`baa9e43f5f9122133deacbc3e8ffc80e284b4f50`): core V03 and helpers V07. 0.6.0 was never published to Hex; its schema work ships in 0.7.0.

There is no expand/contract path and no mixed-version rolling upgrade. The upgrade is one transaction behind a stop-and-drain.

## Bundled versions per release

Each release bundles a fixed latest core and helpers version. A bare `up()` installs that latest version.

| Release | Core | Helpers | `mix pgflow.setup` wrappers                               |
| ------- | ---- | ------- | --------------------------------------------------------- |
| 0.1.0   | V01  | V01     | Bare `up()`                                               |
| 0.1.1+  | V01  | V02     | Bare `up()`                                               |
| 0.2.x   | V01  | V03     | Bare `up()`                                               |
| 0.3.x   | V01  | V04     | Bare `up()`                                               |
| 0.4.0   | V02  | V05     | Bare `up()`; adds `--upgrade`                             |
| 0.5.0   | V02  | V06     | Bare `up()`; adds `escalate_permanently_stalled`          |
| 0.7.0   | V03  | V07     | Pinned `up(version: N)`; shares a database with TS 0.17.x |

Helpers V05 requires core V02: it raises `PgFlow helpers V05 requires core V02 queue identity` on a core V01 database. Never pin helpers below 7 on core 3: replaying helpers V05 re-creates the four-argument `start_tasks` that V03 removed.

## Pick your path

| Project                                                         | Follow                                                                    |
| --------------------------------------------------------------- | ------------------------------------------------------------------------- |
| App that owns the database and installed the pgflow schema      | [Upgrade an app](#upgrade-an-app)                                         |
| Library that defines flows/jobs; the host app installs schema   | [Upgrade a library](#upgrade-a-library)                                   |
| App that depends on pgflow but never installed its schema       | Bump the dependency (step 1), then [bootstrap.md](bootstrap.md) if needed |

Every library and app sharing one database must target the same pgflow schema. A host can force one version with `{:pgflow, "~> 0.7.0", override: true}`, which works at runtime, but each library should still bump its own requirement and installation docs.

## Upgrade an app

### 1. Bump the dependency

1. Edit the requirement to `{:pgflow, "~> 0.7.0"}`.
2. Run `mix deps.unlock pgflow && mix deps.get`. Review the `mix.lock` diff. A plain `mix deps.get` or `mix deps.update pgflow` can also move pgflow's own dependencies (phoenix, phoenix_html, decimal, plug_crypto, ...); keep that churn only if you want it.
3. Keep `phoenix`, `phoenix_live_view`, and `livefilter` in your deps. They are optional in pgflow's `mix.exs`, but the `PgFlowDashboard` modules compile unconditionally, so pgflow does not compile without them.

0.7.0 checks slugs at compile time in `use PgFlow.Flow` and `use PgFlow.Job`: an invalid flow, job, or step slug, an over-long queue name, or a case-insensitive step collision is a `CompileError`. Fix those in code first.

### 2. Confirm both sides

The dependency: `PgFlow.compatibility_report/0` should show `bundled_core_version: 3`, `bundled_helpers_version: 7`, and `upstream_release: "0.17.2"`. Ignore `core_version_string`: it is a fixed legacy label (`"0.5.0"`, same as `PgFlow.core_version/0`) and never tracks the package or schema.

The database:

```sql
SELECT obj_description('pgflow.pgflow_version'::regclass, 'pg_class') AS core,
       obj_description('pgflow.extensions_version'::regclass, 'pg_class') AS helpers;
```

The comments read `PgFlow version=N`. If the query fails with `relation "pgflow.pgflow_version" does not exist`, the schema is not installed: see [bootstrap.md](bootstrap.md).

### 3. Audit slugs

```bash
mix pgflow.audit_slugs
```

The audit reads existing `pgflow.flows` and `pgflow.steps` rows, so it needs an installed pgflow schema. Without one it crashes with `Postgrex.Error ... (undefined_table) relation "pgflow.flows" does not exist`; that means "not installed", not a finding.

`no slug findings` means the database can take V03. Each finding prints as `<kind> <flow_slug>.<step_slug>: <reason>` and the task exits with an error. Pass `--repo MyApp.Repo` when the app has several repos (`--prefix` defaults to `pgflow`). The migration never renames or deletes a slug.

`pgflow.is_valid_slug/1` accepts only `[A-Za-z0-9_]`, must start with a letter, must end with a letter or digit, must not contain `__`, must be at most 128 characters, and must not be `run`. The flow-mode queue name is `lower(flow_slug)`, at most 47 characters, and unique across flows and jobs. Step slugs that differ only by case collide. Finding reasons: `empty`, `too_long`, `bad_chars`, `bad_start`, `bad_end`, `double_underscore`, `reserved`, `queue_name_too_long`, and `case_insensitive_duplicate`.

To clear a finding (renaming in code alone does not: the old rows stay, and the foreign keys have no `ON UPDATE CASCADE`), while drained and on the old schema:

1. Export any run history worth keeping; the next step deletes it.
2. `SELECT pgflow.delete_flow_and_data('<old_slug>');` removes that flow's runs, step states, tasks, and PGMQ queue. Only the backup undoes it.
3. Rename the flow or step in code.
4. Rerun `mix pgflow.audit_slugs` until it reports nothing.
5. Upgrade, then deploy the renamed code. Worker boot compiles the definition under the new slug.

### 4. Pin historical wrappers

Every setup and upgrade wrapper generated before 0.7.0 calls bare `up()`. Replayed on an empty database (CI, a new machine, a review environment) under 0.7.0, the first wrapper installs V03 and V07 at once, and later migrations then run against the wrong schema.

For each historical wrapper:

1. Find the commit that added it, and read `mix.lock` at that commit to see which pgflow it ran under: `git log --diff-filter=A -- <wrapper>`, then `git show <sha>:mix.lock | grep '"pgflow"'`.
2. Look up that release in the [table above](#bundled-versions-per-release) and pin the wrapper to what actually ran, for example `PgFlow.Migration.up(version: 1)` and `PgFlow.HelpersMigration.up(version: 4)` for 0.3.x.
3. Do not trust a pin already in the file. A wrapper can name a version its release never bundled because the pin was edited later: `up(version: 5)` in a wrapper added under 0.3.1 actually installed helpers V04, since 0.3.x bundles only V01 to V04.
4. Check pairs: helpers 5 or 6 need core 2 before them; helpers 7 needs core 3.
5. Fix legacy slug literals in historical compile migrations so a replay passes the V03 slug pre-flight.

Databases that already ran these migrations are unaffected; Ecto does not rerun them.

Existing flow and job compile migrations do not need regenerating. They call `pgflow.create_flow/4` and `pgflow.add_step/8` (positional, plus named condition arguments), and core V03 keeps both signatures. Only `ensure_flow_compiled`, which workers call at boot, changed signature.

### 5. Rehearse a replay from empty

Before generating the upgrade wrapper, prove the pinned history rebuilds the old schema on an empty database:

```bash
MIX_ENV=test mix ecto.drop --force-drop && MIX_ENV=test mix ecto.create && MIX_ENV=test mix ecto.migrate
```

- History must install the Postgres extensions and pgmq before the first setup wrapper ([bootstrap.md](bootstrap.md)).
- `--force-drop` issues `DROP DATABASE ... WITH (FORCE)`. A database with `pg_cron` needs it because the pg_cron launcher stays connected.
- Rerun the version query from step 2; it should show the versions your last wrapper pinned.

### 6. Generate the upgrade wrapper

```bash
mix pgflow.setup --upgrade
```

The generated `<timestamp>_upgrade_pgflow_core_v03_helpers_v07.exs` calls `PgFlow.Migration.up(version: 3)` then `PgFlow.HelpersMigration.up(version: 7)` in one normal Ecto transaction. EctoEvolver applies only versions newer than the database tracks, so from helpers V05 it runs V06 and V07. Do not add `@disable_ddl_transaction true`. Add `--dashboard` only when historical `PgFlowDashboard.Migration` SQL should move in the same transaction.

The task does not always find a repo's configured `priv:` (it falls back to `priv/repo` when `repo.config()` cannot be read). Check where the file landed, or pass `--migrations-path <repo priv>/migrations`.

Repeat the replay from step 5. It should now end at core `PgFlow version=3`, helpers `PgFlow version=7`, and `mix pgflow.check_schema` should pass.

### 7. Stop and drain

V03 requires it in shared and production databases. Dev and test databases can be dropped and recreated instead (step 5 command).

Back up first and record enabled/disabled worker state. Then, in order:

1. Stop producers: `start_flow`, enqueue calls, cron schedules, and TypeScript `startFlow`.
2. Stop stalled-task recovery and pruning (`prune_data_older_than`).
3. Stop definition writers: flow/job compile migrations, Elixir worker boot (it compiles definitions), and TypeScript compile commands.
4. Let workers finish active handlers, then stop every Elixir and TypeScript worker gracefully.
5. Wait until this returns 0:

   ```sql
   SELECT count(*) FROM pgflow.step_tasks WHERE status = 'started';
   ```

Do not wait for `queued` tasks: with workers stopped that count never drains. Queued messages stay in their queues and resume after the upgrade.

### 8. Migrate

```bash
mix ecto.migrate
```

For Hasura or another SQL migration manager, see [below](#hasura-or-another-sql-migration-manager).

What the migration does:

- V03 sets `lock_timeout` to 10 seconds and runs the slug pre-flight; any finding aborts the transaction and leaves the previous schema in place. The timeout bounds lock acquisition, not migration duration.
- Outage cost: V03 drops and rebuilds `idx_runs_started_at` (descending to ascending, matching upstream) under an exclusive lock inside the transaction. Duration grows with `pgflow.runs`; check `SELECT count(*) FROM pgflow.runs;` and size the window.
- Helpers V07 adds `pgflow.delete_run(uuid)` and replaces `prune_data_older_than` with a run-first lock order.
- From helpers V05, V06 adds `pgflow.escalate_permanently_stalled()`. Once recovery resumes, every sweep calls it after the recovery query commits. A manual `SELECT pgflow.escalate_permanently_stalled();` must also run in its own transaction, never with the recovery query (deadlock path with live workers).

### 9. Verify

1. Rerun the version query from step 2: core `PgFlow version=3`, helpers `PgFlow version=7`.
2. Run the full schema check:

   ```bash
   mix pgflow.check_schema
   ```

   Pass `--notify-trigger pgmq_default` when the app configures `notify_trigger: :pgmq_default`. The full check also requires `pgflow.delete_run(uuid)`, which worker boot does not check. A pass may still print warnings; see [compatibility.md](compatibility.md).

### 10. Deploy and resume

Migrate before deploying. On the old schema, 0.7.0 workers never start: `PgFlow.FlowStarter` marks each module `:failed_permanent` with `{:schema_incompatible, object}` while the application itself still boots.

1. Deploy the Elixir 0.7.0 release. Boot it before resuming producers (see below).
2. Deploy TypeScript 0.17.x workers, on flow-mode flows only.
3. Restore recovery, pruning, and the exact recorded worker state.
4. Resume producers.

Scripts and probes that start PgFlow outside a booted app (for example `mix run --no-start`) must call `Application.ensure_all_started(:pgflow)` first. The `:pgflow` application starts `PgFlow.FlowRegistry`; without it `PgFlow.FlowStarter` exits on its first registry call.

#### First 0.7 boot in `:notify` mode

With `signal_strategy: :notify` and the default `notify_trigger: :deferred`, `FlowStarter` recreates pgmq's insert trigger on each flow queue as `DEFERRABLE INITIALLY DEFERRED`:

- The swap runs in its own transaction with `lock_timeout` set to `notify_lock_timeout_ms` (default `2000`) and a per-queue advisory lock, so nodes install one at a time. It needs `ACCESS EXCLUSIVE` on `pgmq.q_<queue>`; on `lock_not_available` the module retries with backoff. Booting while producers are still paused avoids that contention.
- If the deferred recreate fails after pgmq's own call succeeds, pgmq's immediate trigger stays, a warning is logged, and `mix pgflow.check_schema` reports it.
- Later boots that find the deferred trigger only reconcile the queue's `pgmq.notify_insert_throttle` row, with no DDL.
- Trigger errors now fail the producer's COMMIT instead of its INSERT. A transaction that sends to a queue and then drops or purges it must first call `PgFlow.Queries.Pgmq.flush_notify_events/1`; `PgFlow.delete_flow/1` does this itself.
- To keep pgmq's immediate trigger, set `notify_trigger: :pgmq_default` on every node. Mixed values flip the trigger back and forth on each boot.

Rollback: the wrapper is forward-only and `down/0` raises. Restore the pre-drain backup.

## Upgrade a library

A library that defines flows or jobs but leaves the schema to its host app ships no schema migration of its own.

1. **Audit at build time.** Bump the dependency (app step 1) and compile. 0.7.0's compile-time slug checks reject every invalid flow, job, or step slug, so a clean compile is the slug audit for definitions. Fix them in code; rename on the host side with `pgflow.delete_flow_and_data` (app step 3).
2. **Change the pin and docs.** Set `{:pgflow, "~> 0.7.0"}` and update the library's installation docs and upgrade notes: hosts must reach core V03/helpers V07 (this guide) before running the new library version.
3. **Do not wrap.** Do not ship a wrapper around `PgFlow.Migration` or `PgFlow.HelpersMigration`, and do not reimplement the upgrade. Point hosts at `mix pgflow.setup --upgrade`.
4. **Check against a real schema (optional).** Install a scratch schema in the library's test database: a test-only migration that runs the extensions and pgmq migrations, then `PgFlow.Migration.up(version: 3)` and `PgFlow.HelpersMigration.up(version: 7)`. After a version change, recreate the database (`mix ecto.drop --force-drop`) rather than migrating it.

Libraries often configure their repo only for `MIX_ENV=test`, sometimes with `priv:` under `test/support`. Then:

- Run tasks as `MIX_ENV=test mix pgflow.audit_slugs --repo MyLib.TestRepo` and `MIX_ENV=test mix pgflow.check_schema --repo MyLib.TestRepo`. Both need an installed schema: the audit crashes without one, and the check prints a cascade of failures starting with `pgflow schema does not exist`.
- Pass `--migrations-path test/support/<priv>/migrations` to `mix pgflow.setup` and `mix pgflow.gen.pgmq_migration`. `mix pgflow.gen.postgres_extensions_migration` has no path flag; move its file after generation.

## Hasura or another SQL migration manager

Do not run Ecto migrations. Create the migration with the manager's own tooling (for Hasura, its CLI) and assemble it from the installed package (`deps/pgflow/priv/...`), in this order:

1. `priv/pgflow_core/sql/versions/v03/v03_up.sql`
2. From helpers V05 only: `priv/pgflow_helpers/sql/versions/v06/v06_up.sql`
3. `priv/pgflow_helpers/sql/versions/v07/v07_up.sql`
4. The version comments that EctoEvolver would write:

   ```sql
   COMMENT ON VIEW pgflow.pgflow_version IS 'PgFlow version=3';
   COMMENT ON VIEW pgflow.extensions_version IS 'PgFlow version=7';
   ```

While assembling, replace `$SCHEMA$` with `pgflow` (the helpers files use the placeholder; core V03 already names `"pgflow"`), and replace every `--SPLIT--` marker with a statement terminator (`;`). Keep the whole migration in one transaction: the core file starts with `SET LOCAL lock_timeout = '10s'` and its slug pre-flight must abort everything on a finding. Write no down migration; restore the backup instead.

## Databases that applied a pre-release helpers V07

`delete_run` and the run-first prune joined helpers V07 before 0.7.0 shipped. A database that applied V07 from an earlier pre-release build reports helpers version 7 but lacks `pgflow.delete_run(uuid)`, and Ecto will not rerun its wrapper. Workers still boot (the bootstrap check does not cover it), but `PgFlow.Runs.delete/2` fails and pruning keeps the old lock order. Full `mix pgflow.check_schema` fails with `missing run deletion function pgflow.delete_run(uuid)`.

Either recreate the database, or apply the last two statements of `priv/pgflow_helpers/sql/versions/v07/v07_up.sql` (the `delete_run` and `prune_data_older_than` definitions, with `$SCHEMA$` replaced by `pgflow`) in a reviewed migration. Both are `CREATE OR REPLACE`, so re-applying them is safe. Do not change the version comment.

## What changed in 0.7.0

- Flow mode keeps one queue per flow, `lower(flow_slug)`. Step mode is TypeScript-only: Elixir refuses step-mode flows at boot with `{:error, {:unsupported_queue_mode, slug, "step"}}`, before compiling, holding upstream's flow-definition advisory lock.
- A queue-mode or route mismatch is `{:error, {:flow_routing_mismatch, message}}` with the upstream text.
- `start_tasks(text, bigint[], uuid, text, text)`: the last argument is the step slug, null for flow-mode claims. `ensure_flow_compiled(text, jsonb, text, jsonb)`: Elixir passes `'flow'` and a null route map. `register_worker` takes four arguments; workers stamp `pgflow_version` as `elixir-<package version>`.
- `use PgFlow.Flow` and `use PgFlow.Job` reject invalid slugs at compile time.
- `PgFlow.Config` raises `ArgumentError` at boot when two configured flows or jobs share a queue name.
- `mix pgflow.setup` and `mix pgflow.setup --upgrade` generate pinned wrappers.
- `pgflow_telemetry` and `ensure_workers` (Supabase `pg_net`) are not installed; OTP registers workers.
- `pgflow.delete_run(uuid)` behind `PgFlow.Runs.delete/2`. There is no per-run cancel or fail API.
- Runtime worker controls (`worker_options`, `scale_worker/2`, `check_worker/2`) and stricter `start_worker/2` validation: see [operations.md](operations.md). Unknown `start_worker/2` options now raise instead of being ignored.
- Deferred notify triggers and new `mix pgflow.check_schema` warnings: see [config.md](config.md) and [compatibility.md](compatibility.md).

## Older paths and recovery tools

Databases still on core V01 follow the September procedure in the installed PgFlow `docs/UPGRADING_UPSTREAM_2026_09.md` first. Core V02 rewrites `step_tasks`, scans constraints, creates a non-concurrent unique index, and holds an `ACCESS EXCLUSIVE` lock through the transaction; rehearse it on a restored copy.

Never rerun an old setup wrapper. Use `mix pgflow.stamp` only after proving an untracked legacy schema exactly matches the expected baseline; stamping drift makes later migrations unsafe.

For `flow_shape_mismatch`, compare the ordered stored steps with the code. Restore matching code or introduce a new flow slug for the changed shape. Do not rewrite `step_index` to make the check pass.

Production shape mismatch preserves history. Destructive recompilation is controlled by the database `app.settings.jwt_secret` GUC matching the Supabase local default, not by `MIX_ENV`. Never set that GUC on a history-bearing database.

## Database restores and project cutovers

Treat database movement as a separate state-transfer boundary. Installing `pg_cron`, restoring application tables, and passing `mix pgflow.check_schema` do **not** prove recurring jobs exist on the target. Extension-owned `cron.job` rows may be absent even though canonical host rows and `schema_migrations` were restored.

Before stopping the source database:

1. Snapshot source `cron.job` names, schedules, commands, active state, database, and owner.
2. Inventory the application's canonical scheduling rows and singleton/global jobs. Classify PgFlow-owned jobs (`pgflow:<slug>`) separately from host-owned registrations.
3. Record the reconciliation operation for every host-owned schedule class.

After restoring the target and before resuming producers:

1. Query the target independently. **Never conclude "nothing to restore" from an empty target `cron.job`; compare it with the source inventory and canonical host configuration.**
2. Restore PgFlow-owned registrations from saved schedule state or reviewed scheduling SQL generated from the matching flow/job definitions. Preserve intentionally disabled schedules. Use a new forward migration or an explicit reconciliation operation; do not rerun old definition migrations or recompile entire flows merely to restore cron rows.
3. Run the host application's idempotent schedule reconciliation after migrations. A one-time migration alone is insufficient because its `schema_migrations` row may also have been restored.
4. Compare exact job names, schedules, commands, active state, database, and owner. Confirm expected source rows have one matching cron registration and inspect `cron.job_run_details` after the first due execution.
5. Verify the reconciliation itself did not enqueue or execute business work; catch-up task execution is a separate explicitly approved operation.

The release path should invoke host reconciliation after migrations on every deploy. This makes a restored database self-repairing even when no migration is pending.

Physical and point-in-time restores, like crash recovery, empty UNLOGGED tables such as `pgmq.notify_insert_throttle`. In `:notify` mode, worker boot and `PgFlow.Signal.Notify` restore missing rows; `mix pgflow.check_schema` warns until they do.
