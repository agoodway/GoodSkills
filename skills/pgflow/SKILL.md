---
name: pgflow
description: "Use when installing, upgrading, configuring, operating, or debugging PgFlow in Elixir/Phoenix; defining flows, jobs, maps, conditional steps, retries, recovery, pruning, LiveView tracking, or the dashboard; checking PgFlow schema/upstream compatibility; or invoking `/pgflow`."
---

# PgFlow

PgFlow is a PostgreSQL/PGMQ workflow engine with OTP workers. Inspect the consumer's installed PgFlow version before changing it: unreleased source capabilities may not exist in the published Hex package.

## Route the request

Read only the references needed for the request:

| Request | Reference |
| --- | --- |
| Install or bootstrap | [references/bootstrap.md](references/bootstrap.md) |
| Upgrade an existing database | [references/upgrading.md](references/upgrading.md) |
| Create a flow | [references/flow.md](references/flow.md), then [references/flows.md](references/flows.md) |
| Create a job | [references/job.md](references/job.md), then [references/jobs.md](references/jobs.md) |
| Add/modify a step | [references/step.md](references/step.md) |
| Conditions or fail-soft steps | [references/conditional-steps.md](references/conditional-steps.md) |
| Runtime, workers, recovery, pruning | [references/operations.md](references/operations.md) |
| Typed reads and operational actions | [references/public-api.md](references/public-api.md) |
| Configuration | [references/config.md](references/config.md) |
| Dashboard | [references/dashboard-setup.md](references/dashboard-setup.md) |
| LiveView tracking | [references/liveview-setup.md](references/liveview-setup.md) |
| Debug a run | [references/debug.md](references/debug.md), then [references/public-api.md](references/public-api.md) |
| Upstream/harness verification | [references/compatibility.md](references/compatibility.md) |
| Telemetry | [references/telemetry.md](references/telemetry.md) |

For `/pgflow help` or an unknown/missing subcommand, list: `bootstrap`, `upgrade`, `flow`, `job`, `step`, `dashboard`, `liveview`, `debug`, `check`, and `help`. Then follow the matching reference. `check` runs the deployment verification in [references/compatibility.md](references/compatibility.md).

## Non-negotiable safety rules

- Treat logical flow identity and physical queue identity separately. Queue operations use persisted `(queue_name, message_id)`; current default queue routes are lowercase flow slugs.
- Do not overlap old and new workers during a core V02/helpers V05 upgrade. Pause producers, drain, stop all writers, migrate core then helpers in one transaction, verify, and deploy matching callers.
- Do not expect an applied setup migration to rerun after a dependency bump. Generate a new `mix pgflow.setup --upgrade` wrapper.
- When an upgrade also moves/restores the database, a green PgFlow schema does not prove recurring schedules survived. Inventory cron state on the source and reconcile host-owned schedules on the target from canonical application configuration.
- Run `mix pgflow.check_schema`; worker bootstrap checks only the runtime-critical subset. A ready starter can still have permanently failed modules.
- Never use runtime destructive recompilation or `mix pgflow.stamp` without proving the database contract and history implications.
- Handler outputs must be JSON-encodable. Preserve valid scalars (`false`, `0`, `""`, arrays, and `nil`); do not wrap invalid output.
- Handlers are at-least-once. Make side effects idempotent even when a step later appears skipped.
- The core-backed LiveView dashboard does not require historical dashboard SQL objects.

$ARGUMENTS
