# Verification and upstream compatibility

## Deployment gates

```bash
mix pgflow.check_schema --repo MyApp.Repo
PGFLOW_REQUIRE_DB=1 mix test
PGFLOW_REQUIRE_DB=1 mix test --only migration
mix quality
```

When the release includes a database restore, branch replacement, major-version
project cutover, or point-in-time recovery, also compare source and target
`cron.job` inventories and run the host application's schedule reconciliation.
PgFlow schema compatibility and worker heartbeats do not cover application-owned
pg_cron registrations.

Run migration tests separately because they mutate the shared test schema. Without `PGFLOW_REQUIRE_DB=1`, an unreachable database can exclude integration tests while the command succeeds.

The schema gate checks core/helpers version floors, required tables and pgmq, the five-argument `start_tasks(text,bigint[],uuid,text,text)`, absence of the legacy three-argument and four-argument claims, `ensure_flow_compiled(text,jsonb,text,jsonb)`, `register_worker(uuid,text,text,text)`, `delete_run(uuid)`, queue constraints, task statuses, and the eight-field `step_task_record` with `attempts_count`. Worker bootstrap checks a narrower runtime-critical subset (it does not cover `delete_run`); it does not replace this gate.

When the gate passes, it also prints warnings without failing:

- A flow queue (`lower(flow_slug)`) notify trigger that is not `DEFERRABLE INITIALLY DEFERRED`, for example after `ALTER EXTENSION pgmq UPDATE`. `:deferred` workers fix it on their next boot. Pass `--notify-trigger pgmq_default` when the app uses `notify_trigger: :pgmq_default` to skip this one.
- A notify trigger whose queue has no `pgmq.notify_insert_throttle` row, so it sends no NOTIFY until worker boot or `PgFlow.Signal.Notify` restores it.
- A notify trigger on a partitioned flow queue when the installed pgmq (before 1.13.1) cannot resolve the partition to its queue.

A polling-only database has no notify triggers and reports none of these.

PgFlow 0.7.0 requires core V03 and helpers V07. Verify `pgflow.escalate_permanently_stalled()`, `pgflow.delete_run(uuid)`, and the 15-column `pgflow.step_progress` view after the migration. A helpers V07 applied from a pre-release build can lack `delete_run`; see [upgrading.md](upgrading.md). Elixir workers stamp `elixir-<package version>` and refuse step-mode flows. A queue-mode mismatch returns `{:error, {:flow_routing_mismatch, message}}`.

## Upstream harness

Run only against a disposable database with the permitted test prefix:

```bash
MIX_ENV=test mix run --no-start test/support/upstream/run.exs \
  --checkout /path/to/upstream \
  --sha baa9e43f5f9122133deacbc3e8ffc80e284b4f50 \
  --database-url postgres://postgres:postgres@localhost:54323/pgflow_compat_xxx \
  --suite all
```

The full harness needs Git, `psql`, Node, pnpm, Supabase CLI, and server pgTAP. Report passes, unresolved probes, and skips separately. Do not claim universal JSON parity: pinned TypeScript coerces falsy handler output while Elixir preserves `false`, `0`, and `""`. Full notify acceptance also requires a pgmq version providing notify-insert support; fallback polling is a distinct profile.

Report compatibility as upstream pgflow 0.17.2 (`baa9e43f5f9122133deacbc3e8ffc80e284b4f50`) through `PgFlow.compatibility_report/0`. `PgFlow.core_version/0` remains the legacy string `"0.5.0"` and does not track the package. Pinned TypeScript 0.17.2 still coerces falsy handler output; Elixir preserves `false`, `0`, and `""`.

Runtime-only divergences add nothing to the shared schema: `worker_options`, `start_worker/2`, and `scale_worker/2` play the role of the TypeScript worker's `maxConcurrent` and `batchSize` (upstream has no runtime scaling), and upstream never uses LISTEN/NOTIFY. The deferred pgmq notify trigger that `:notify` mode installs does not affect TypeScript workers or producers on shared flow queues, but an SQL or TypeScript caller that sends and then deletes a flow in one transaction must run `SET CONSTRAINTS pgmq.trigger_notify_queue_insert_listeners IMMEDIATE` first.
