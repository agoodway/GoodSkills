# Upgrade PgFlow schema

Use this for an existing installation when a dependency adds a core or helpers migration. PgFlow 0.6.0 targets upstream pgflow 0.17.2 (`baa9e43f5f9122133deacbc3e8ffc80e284b4f50`): core V03 and helpers V07. PgFlow 0.4.0 stayed on core V02 and helpers V05. PgFlow 0.5.0 stayed on core V02 and added helpers V06. Those earlier releases are not the current schema. Check which release the consumer actually depends on: Hex may lag the source repository.

There is no expand/contract path and no mixed-version rolling upgrade. The upgrade is one transaction behind a stop-and-drain.

## 1. Audit slugs

```bash
mix pgflow.audit_slugs
```

No findings means the database can take V03. The task finds the host app's repo on its own; pass `--repo MyApp.Repo` only when the app has several. The migration never renames or deletes a slug.

`pgflow.is_valid_slug/1` accepts only `[A-Za-z0-9_]`, must start with a letter, must end with a letter or digit, must not contain `__`, must be at most 128 characters, and must not be `run`. The flow-mode queue name is `lower(flow_slug)`, at most 47 characters, and unique across flows and jobs. Step slugs that differ only by case collide. Finding reasons: `empty`, `too_long`, `bad_chars`, `bad_start`, `bad_end`, `double_underscore`, `reserved`, `queue_name_too_long`, and `case_insensitive_duplicate`. Compile-time validation rejects the same problems, including case-insensitive step collisions.

### Clearing a finding

Renaming the slug in Elixir code does not clear a finding: the old `flows` and `steps` rows stay, and the foreign keys have no `ON UPDATE CASCADE`, so the rows cannot be renamed in SQL either. While drained, on the old schema:

1. Export any run history worth keeping; the next step deletes it.
2. `SELECT pgflow.delete_flow_and_data('<old_slug>');` removes that flow's runs, step states, tasks, and PGMQ queue. Only the backup undoes it.
3. Rename the flow or step in code.
4. Rerun `mix pgflow.audit_slugs` until it reports nothing.
5. Upgrade, then deploy the renamed code. Worker boot compiles the definition under the new slug.

## 2. Pin consumer migration history

From 0.6.0, a bare `PgFlow.Migration.up()` installs the newest bundled core version and a bare `PgFlow.HelpersMigration.up()` the newest helpers version. Replaying an old `setup_pgflow` wrapper on an empty database (CI, a new machine, a review environment) therefore installs V03 and V07, and older flow-compile migrations with legacy slug literals then fail the slug rules.

Before shipping 0.6.0, pin every existing wrapper to the versions it originally installed (for example `PgFlow.Migration.up(version: 1)` and `PgFlow.HelpersMigration.up(version: 1)`) and fix legacy slug literals in historical compile migrations. Databases that already ran those migrations are unaffected; Ecto does not rerun them. Newly generated wrappers are pinned.

## 3. Stop and drain

Back up first and record enabled/disabled worker state. Then, in order:

1. Stop producers: `start_flow`, enqueue calls, cron schedules, and TypeScript `startFlow`.
2. Stop stalled-task recovery and pruning.
3. Stop definition writers: flow/job compile migrations, Elixir worker boot (it compiles definitions), and TypeScript compile commands.
4. Let workers finish active handlers, then stop every Elixir and TypeScript worker gracefully.
5. Wait until this returns 0:

   ```sql
   SELECT count(*) FROM pgflow.step_tasks WHERE status = 'started';
   ```

Do not wait for `queued` tasks: with workers stopped that count never drains. Queued messages stay in their queues and resume after the upgrade.

## 4. Migrate

Apply through the host application's migration manager. For Hasura, create the migration with its CLI and assemble the installed package's versioned SQL there; do not run Ecto migrations. For Ecto-managed applications, generate a new wrapper (Ecto never reruns an older setup migration):

```bash
mix pgflow.setup --upgrade
mix ecto.migrate
mix pgflow.check_schema
```

The generated `<timestamp>_upgrade_pgflow_core_v03_helpers_v07.exs` calls `PgFlow.Migration.up(version: 3)` then `PgFlow.HelpersMigration.up(version: 7)` in one normal Ecto transaction. Do not add `@disable_ddl_transaction true`. V03 sets `lock_timeout` to 10 seconds and runs the slug pre-flight; any finding aborts the transaction and leaves the previous schema in place.

Core V03 requires helpers V07. Never pin helpers below 7 on core 3: replaying helpers V05 re-creates the four-argument `start_tasks` that V03 removed.

Outage cost: V03 drops and rebuilds `idx_runs_started_at` (descending to ascending, matching upstream) under an exclusive lock inside the transaction. Duration grows with `pgflow.runs`; check `SELECT count(*) FROM pgflow.runs;` and size the window.

## 5. Deploy and resume

Migrate before deploying. On the old schema, 0.6.0 workers never start: `PgFlow.FlowStarter` marks each module permanently failed with `{:schema_incompatible, object}` while the application itself still boots.

1. Deploy the Elixir release requiring core V03 and helpers V07.
2. Deploy TypeScript 0.17.x workers, on flow-mode flows only.
3. Restore recovery, pruning, and the exact recorded worker state, then resume producers.

`mix pgflow.check_schema` finds the host repo without `--repo`. `PgFlow.compatibility_report/0` reports `upstream_release: "0.17.2"`, `bundled_core_version: 3`, and `bundled_helpers_version: 7`.

## What changed in 0.6.0

- Flow mode keeps one queue per flow, `lower(flow_slug)`. Step mode (private step queues plus a route map) is TypeScript-only: Elixir refuses step-mode flows at boot with `{:error, {:unsupported_queue_mode, slug, "step"}}`, before compiling, even when local recompilation is enabled. The check holds upstream's flow-definition advisory lock, so a concurrent TypeScript step-mode compile cannot be recompiled away.
- A queue-mode or route mismatch is `{:error, {:flow_routing_mismatch, message}}` with the upstream text.
- `start_tasks(text, bigint[], uuid, text, text)`: the last argument is the step slug, null for flow-mode claims.
- `ensure_flow_compiled(text, jsonb, text, jsonb)`: Elixir passes `'flow'` and a null route map.
- `register_worker` takes four arguments; workers stamp `pgflow_version` as `elixir-<package version>`.
- `PgFlow.Config` raises `ArgumentError` at boot when two configured flows or jobs share a queue name.
- `pgflow_telemetry` and `ensure_workers` (Supabase `pg_net`) are not installed; OTP registers workers.

Rollback: the wrapper is forward-only and `down/0` raises. Restore the pre-drain backup.

## Operational risk (older upgrades)

Core V02 rewrites `step_tasks`, scans constraints, creates a non-concurrent unique index, and holds an `ACCESS EXCLUSIVE` lock through the transaction. Measure table/index size, disk, WAL capacity, long transactions, and vacuum needs on a restored copy. The lock timeout bounds acquisition, not migration duration.

Never rerun an old setup wrapper. Use `mix pgflow.stamp` only after proving an untracked legacy schema exactly matches the expected baseline; stamping drift makes later migrations unsafe.

For `flow_shape_mismatch`, compare the ordered stored steps with the code.
Restore matching code or introduce a new flow slug for the changed shape.
Do not rewrite `step_index` to make the check pass.

Production shape mismatch preserves history. Destructive recompilation is controlled by the database `app.settings.jwt_secret` GUC matching the Supabase local default—not by `MIX_ENV`. Never set that GUC on a history-bearing database.

## Database restores and project cutovers

Treat database movement as a separate state-transfer boundary. Installing
`pg_cron`, restoring application tables, and passing
`mix pgflow.check_schema` do **not** prove recurring jobs exist on the target.
Extension-owned `cron.job` rows may be absent even though canonical host rows
and `schema_migrations` were restored.

Before stopping the source database:

1. Snapshot source `cron.job` names, schedules, commands, active state,
   database, and owner.
2. Inventory the application's canonical scheduling rows and singleton/global
   jobs. Classify PgFlow-owned jobs (`pgflow:<slug>`) separately from host-owned
   registrations.
3. Record the reconciliation operation for every host-owned schedule class.

After restoring the target and before resuming producers:

1. Query the target independently. **Never conclude “nothing to restore” from
   an empty target `cron.job`; compare it with the source inventory and
   canonical host configuration.**
2. Restore PgFlow-owned registrations from saved schedule state or reviewed
   scheduling SQL generated from the matching flow/job definitions. Preserve
   intentionally disabled schedules. Use a new forward migration or an explicit
   reconciliation operation; do not rerun old definition migrations or recompile
   entire flows merely to restore cron rows.
3. Run the host application's idempotent schedule reconciliation after Ecto
   migrations. A one-time migration alone is insufficient because its
   `schema_migrations` row may also have been restored.
4. Compare exact job names, schedules, commands, active state, database, and
   owner. Confirm expected source rows have one matching cron registration and
   inspect `cron.job_run_details` after the first due execution.
5. Verify the reconciliation itself did not enqueue or execute business work;
   catch-up task execution is a separate explicitly approved operation.

The release path should invoke host reconciliation after migrations on every
deploy. This makes a restored database self-repairing even when no Ecto
migration is pending.

## Helpers V05 to V06 (previous release)

V06 adds `pgflow.escalate_permanently_stalled()` and `pgflow.step_progress`.
Hex pgflow 0.4.0 stops at helpers V05; Hex pgflow 0.5.0 bundles V06. A
dependency bump alone does not apply its SQL.
Install the V06 helper SQL through the host's migration manager while workers
and recovery are stopped. Run the one-time escalation pass only after the V06
function is installed; it terminalizes tasks that V05 stamped and left started.
Set the helpers version comment to `PgFlow version=6`, then run
`mix pgflow.check_schema --repo MyApp.Repo` before resuming workers. V06 worker
bootstrap rejects a V05 helpers schema. The one-time SQL pass is:

```sql
SELECT pgflow.escalate_permanently_stalled();
```

The recovery query and escalation query must commit separately. Recovery locks
task rows first; `fail_task` locks run and step rows first. Combining them in
one transaction creates a deadlock path with live workers. Hosts that use
Hasura or another migration manager should assemble the versioned SQL into
that manager's migration instead of running `mix ecto.migrate`.
