# Runtime operations

## Workers

- `PgFlow.start_worker(Module)` is idempotent per module on one node.
- `PgFlow.stop_worker(Module)` is the operator stop: it drains active tasks and removes any concurrent supervised replacement. Do not call `PgFlow.Worker.Server.stop(pid)` as an operator primitive.
- Workers use transient restart. Crashes and `:deprecated` exits replace the child; a normal operator stop is final.
- Database-driven replacement marks `deprecated_at`; the next heartbeat drains and exits. Deprecations share the supervisor budget of 10 restarts in 60 seconds, so rotate in small batches with crash headroom.

## Queue identity

The durable identity is `(queue_name, message_id)`, not `message_id`. Flow slugs keep logical case; current physical queues use lowercase slugs and must be nonempty and at most 47 characters. Case-insensitive slug collisions are invalid. Claim, recovery, cancel/delete, and prune operations must use persisted routes. Per-step custom queues are not implemented.

## Recovery

Stalled-task recovery is supervised and defaults to a 15-second sweep. A task is eligible only when task, step, and run are all `started` and the effective timeout plus stale threshold elapsed. Recovery uses `FOR UPDATE SKIP LOCKED`, preserves attempt count, increments `requeued_count`, clears ownership/start time, and resets visibility on the persisted queue.

After three requeues, the next sweep archives the message and records `permanently_stalled_at`; it does not terminalize the task/run. Alert on these rows.

## Pruning and deletion

Pruning removes old completed/failed runs and their live/archive messages by persisted task route. Stale-worker deletion is global even when pruning has a `flow_slugs:` filter. Payload-only orphan messages without a persisted task route are intentionally not swept by run count/cancel/delete/prune APIs.

Handlers are at-least-once. SQL may later mark a step skipped while a handler is already running, so external side effects require their own idempotency key or guard.
