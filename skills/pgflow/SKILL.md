---
name: pgflow
description: "Use when installing, upgrading, configuring, operating, or debugging PgFlow in Elixir/Phoenix; defining flows, jobs, maps, conditional steps, retries, recovery, pruning, run deletion, worker scaling, notify triggers, LiveView tracking, or the dashboard; checking PgFlow schema/upstream compatibility; or invoking `/pgflow`."
---

# PgFlow

PgFlow is a PostgreSQL/PGMQ workflow engine with OTP workers. This skill describes PgFlow 0.7.0 (core V03, helpers V07, upstream pgflow 0.17.2). Inspect the consumer's installed PgFlow version before changing it: unreleased source capabilities may not exist in the published Hex package, and 0.6.0 was never published.

## Route the request

Read only the references needed for the request:

| Request                                                    | Reference                                                                                             |
| ---------------------------------------------------------- | ----------------------------------------------------------------------------------------------------- |
| Install or bootstrap                                       | [references/bootstrap.md](references/bootstrap.md)                                                    |
| Upgrade an existing database, app, or library              | [references/upgrading.md](references/upgrading.md)                                                    |
| Create a flow                                              | [references/flow.md](references/flow.md), then [references/flows.md](references/flows.md)             |
| Create a job                                               | [references/job.md](references/job.md), then [references/jobs.md](references/jobs.md)                 |
| Add/modify a step                                          | [references/step.md](references/step.md)                                                              |
| Conditions or fail-soft steps                              | [references/conditional-steps.md](references/conditional-steps.md)                                    |
| Runtime, workers, scaling, recovery, pruning, run deletion | [references/operations.md](references/operations.md)                                                  |
| Typed reads and operational actions                        | [references/public-api.md](references/public-api.md)                                                  |
| Configuration                                              | [references/config.md](references/config.md)                                                          |
| Dashboard                                                  | [references/dashboard-setup.md](references/dashboard-setup.md)                                        |
| LiveView tracking                                          | [references/liveview-setup.md](references/liveview-setup.md)                                          |
| Debug a run                                                | [references/debug.md](references/debug.md), then [references/public-api.md](references/public-api.md) |
| Consumer gates, upstream/harness verification              | [references/compatibility.md](references/compatibility.md)                                            |
| Telemetry                                                  | [references/telemetry.md](references/telemetry.md)                                                    |

For `/pgflow help` or an unknown/missing subcommand, list: `bootstrap`, `upgrade`, `flow`, `job`, `step`, `dashboard`, `liveview`, `debug`, `check`, and `help`. Then follow the matching reference. `check` runs the consumer verification in [references/compatibility.md](references/compatibility.md).

## Non-negotiable safety rules

- Treat logical flow identity and physical queue identity separately. Queue operations use persisted `(queue_name, message_id)`; flow-mode queue routes are lowercase flow slugs, at most 47 characters.
- PgFlow 0.7.0 shares a database with TypeScript 0.17.x only in flow mode. Elixir refuses step-mode flows with `{:error, {:unsupported_queue_mode, slug, "step"}}`. A routing mismatch is `{:error, {:flow_routing_mismatch, message}}`. Workers are stamped `elixir-<package version>`.
- Slugs follow upstream `is_valid_slug`. Compile-time slug errors are fixed in code; migrations never rename slugs. Run `mix pgflow.audit_slugs` (it needs an installed schema) before `mix pgflow.setup --upgrade`; clear findings with `pgflow.delete_flow_and_data` while drained, not SQL renames.
- Do not overlap old and new workers during a schema upgrade. Pause producers, drain until no task is `started` (queued tasks are kept), stop all writers, apply the new schema version, verify, and only then deploy matching callers. 0.7.0 workers on an older schema refuse to start with `{:schema_incompatible, object}`.
- Keep setup wrappers pinned (`up(version: N)`). A bare `up()` installs the newest bundled version when migration history is replayed on an empty database. Wrappers generated before 0.7.0 are bare: pin each to what actually ran under the pgflow in its commit's `mix.lock`, then rehearse a replay from empty before generating the upgrade wrapper.
- Do not expect an applied setup migration to rerun after a dependency bump. Use the host's migration manager; in Ecto-managed applications, generate a new `mix pgflow.setup --upgrade` wrapper.
- When an upgrade also moves/restores the database, a green PgFlow schema does not prove recurring schedules survived. Inventory cron state on the source and reconcile host-owned schedules on the target from canonical application configuration.
- Run `mix pgflow.check_schema`; worker bootstrap checks only the runtime-critical subset.
- Libraries that define flows/jobs leave the schema to the host: bump the pin and host docs, never wrap PgFlow migrations. Every project sharing a database targets the same pgflow schema. A ready starter can still have permanently failed modules.
- Never use runtime destructive recompilation or `mix pgflow.stamp` without proving the database contract and history implications.
- Handler outputs must be JSON-encodable. Preserve valid scalars (`false`, `0`, `""`, arrays, and `nil`); do not wrap invalid output.
- Handlers are at-least-once. Make side effects idempotent even when a step later appears skipped.
- There is no per-run cancel or fail API. `PgFlow.Runs.delete/2` (or SQL `pgflow.delete_run(uuid)`) discards a run's history and cannot interrupt a running handler.
- Worker controls (`start_worker/2`, `scale_worker/2`, `check_worker/2`, `stop_worker/1`) act on the local node only, and scaled limits reset on restart.
- In `:notify` mode, a transaction that sends to a queue and then drops or purges it must call `PgFlow.Queries.Pgmq.flush_notify_events/1` first.
- The core-backed LiveView dashboard does not require historical dashboard SQL objects.

$ARGUMENTS
