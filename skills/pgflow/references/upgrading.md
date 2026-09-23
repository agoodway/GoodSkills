# Upgrade PgFlow schema

Use this for an existing installation when a dependency adds a core or helpers migration. PgFlow 0.4.0 aligned with upstream SHA `94490709f79ebf366141dd925b047f0c1013e759` at core V02 + helpers V05; do not call that published npm `0.17.0` compatibility. PgFlow 0.5.0 keeps core V02 and adds helpers V06.

## Coordinated procedure

There is no mixed-version rolling upgrade.

1. Back up and record enabled/disabled worker state.
2. Pause producers and cron; drain in-flight handlers without emptying queues.
3. Stop OTP workers plus recovery, pruning, and definition writers.
4. Run preflight checks for case-insensitive slug collisions, slugs longer than 47 characters, and duplicate `(lower(flow_slug), message_id)` pairs.
5. Apply through the host application's migration manager. For Hasura, create
   the migration with its CLI and assemble the installed package's versioned
   SQL there; do not run Ecto migrations. For Ecto-managed applications,
   generate a new wrapper and apply it:

   ```bash
   mix pgflow.setup --upgrade --repo MyApp.Repo
   mix ecto.migrate
   mix pgflow.check_schema --repo MyApp.Repo
   ```

6. Verify queue backfill/counts, deploy matching Elixir and pinned TypeScript callers, restore maintenance and exact worker state, then resume producers.

The Ecto wrapper must call `PgFlow.Migration.up()` then `PgFlow.HelpersMigration.up()` in one normal Ecto transaction. Do not add `@disable_ddl_transaction true`. Its down path is forward-only; restore the coordinated backup after a successful migration if rollback is required.

## Operational risk

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

## Helpers V05 to V06

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
