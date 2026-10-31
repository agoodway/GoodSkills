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

The schema gate checks core/helpers version floors, required tables and pgmq, the five-argument `start_tasks(text,bigint[],uuid,text,text)`, absence of the legacy three-argument and four-argument claims, `ensure_flow_compiled(text,jsonb,text,jsonb)`, `register_worker(uuid,text,text,text)`, queue constraints, task statuses, and the eight-field `step_task_record` with `attempts_count`. Worker bootstrap checks a narrower runtime-critical subset; it does not replace this gate.

PgFlow 0.6.0 requires core V03 and helpers V07. Verify `pgflow.escalate_permanently_stalled()` and the 15-column `pgflow.step_progress` view after the migration. Elixir workers stamp `elixir-<package version>` and refuse step-mode flows. A queue-mode mismatch returns `{:error, {:flow_routing_mismatch, message}}`.

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
