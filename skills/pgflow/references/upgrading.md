# Upgrade PgFlow schema

Use this for an existing installation when a dependency adds a core or helpers migration. For the upstream-alignment release, the target contract is core V02 + helpers V05 at upstream SHA `94490709f79ebf366141dd925b047f0c1013e759`; do not call that published npm `0.17.0` compatibility.

## Coordinated procedure

There is no mixed-version rolling upgrade.

1. Back up and record enabled/disabled worker state.
2. Pause producers and cron; drain in-flight handlers without emptying queues.
3. Stop OTP workers plus recovery, pruning, and definition writers.
4. Run preflight checks for case-insensitive slug collisions, slugs longer than 47 characters, and duplicate `(lower(flow_slug), message_id)` pairs.
5. Generate a new wrapper and apply it:

   ```bash
   mix pgflow.setup --upgrade --repo MyApp.Repo
   mix ecto.migrate
   mix pgflow.check_schema --repo MyApp.Repo
   ```

6. Verify queue backfill/counts, deploy matching Elixir and pinned TypeScript callers, restore maintenance and exact worker state, then resume producers.

The wrapper must call `PgFlow.Migration.up()` then `PgFlow.HelpersMigration.up()` in one normal Ecto transaction. Do not add `@disable_ddl_transaction true`. Its down path is forward-only; restore the coordinated backup after a successful migration if rollback is required.

## Operational risk

Core V02 rewrites `step_tasks`, scans constraints, creates a non-concurrent unique index, and holds an `ACCESS EXCLUSIVE` lock through the transaction. Measure table/index size, disk, WAL capacity, long transactions, and vacuum needs on a restored copy. The lock timeout bounds acquisition, not migration duration.

Never rerun an old setup wrapper. Use `mix pgflow.stamp` only after proving an untracked legacy schema exactly matches the expected baseline; stamping drift makes later migrations unsafe.

Production shape mismatch preserves history. Destructive recompilation is controlled by the database `app.settings.jwt_secret` GUC matching the Supabase local default—not by `MIX_ENV`. Never set that GUC on a history-bearing database.
