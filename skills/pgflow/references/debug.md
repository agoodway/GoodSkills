# pgflow debug

Inspect a PgFlow run to diagnose failures, check step states, view errors, and understand retry behavior.

## Inputs

- **Arg form**: `/pgflow debug <run_id>` — inspect the given run ID (UUID).
- **Arg form**: `/pgflow debug :process_order` — show recent runs for the given flow slug.
- **Arg form**: `/pgflow debug failed` — show recent failed runs across all flows.
- **No arg**: Ask the user what to debug — a specific run ID, a flow slug, or recent failures.

## Workflow

### 1. Determine What to Debug

Parse the argument:
- UUID format → specific run
- Atom/slug → recent runs for that flow
- `failed` / `failures` → recent failed runs
- No arg → ask the user

### 2a. Debug a Specific Run

Query the run with step states:

```elixir
# In IEx or via project_eval
{:ok, run} = PgFlow.get_run_with_states("run-uuid-here")
```

Or query directly:

```sql
SELECT r.id, r.flow_slug, r.status, r.input, r.output,
       r.remaining_steps, r.inserted_at, r.updated_at
FROM pgflow.runs r
WHERE r.id = 'run-uuid-here';
```

```sql
SELECT ss.step_slug, ss.status, ss.output, ss.error_message,
       ss.attempts_made, ss.inserted_at, ss.updated_at
FROM pgflow.step_states ss
WHERE ss.run_id = 'run-uuid-here'
ORDER BY ss.inserted_at;
```

For detailed task-level info (individual attempts):

```sql
SELECT st.step_slug, st.task_index, st.status, st.error_message,
       st.attempts_made, st.started_at, st.completed_at
FROM pgflow.step_tasks st
WHERE st.run_id = 'run-uuid-here'
ORDER BY st.step_slug, st.task_index;
```

### 2b. Debug a Flow's Recent Runs

```sql
SELECT r.id, r.status, r.remaining_steps,
       r.inserted_at, r.updated_at,
       (r.updated_at - r.inserted_at) AS duration
FROM pgflow.runs r
WHERE r.flow_slug = 'process_order'
ORDER BY r.inserted_at DESC
LIMIT 20;
```

### 2c. Debug Recent Failures

```sql
SELECT r.id, r.flow_slug, r.status, r.remaining_steps,
       r.inserted_at, r.updated_at
FROM pgflow.runs r
WHERE r.status = 'failed'
ORDER BY r.updated_at DESC
LIMIT 20;
```

### 3. Analyze and Report

Present findings in a structured format:

```
=== PGFLOW DEBUG: <run_id> ===
Flow: process_order
Status: failed
Started: 2026-05-07 14:30:00Z
Duration: 12.3s
Remaining steps: 2

STEP STATES:
  validate    completed  (1 attempt, 0.2s)
  process     failed     (3 attempts, last error below)
  finalize    created    (not started — blocked by failed dependency)

FAILURE DETAILS:
  Step: process
  Attempts: 3 / 3 (exhausted)
  Last error: "connection refused: payment-api.example.com:443"
  
  Attempt 1: failed at 14:30:01 — "connection refused..."
  Attempt 2: failed at 14:30:06 — "connection refused..."  (5s backoff)
  Attempt 3: failed at 14:30:16 — "connection refused..."  (10s backoff)

INPUT:
  {"order_id": 123, "amount": 99.99}

STEP OUTPUTS:
  validate: {"valid": true, "order_id": 123}
  process: null (failed)
  finalize: null (not started)

DIAGNOSIS:
  The :process step failed all 3 attempts with a connection error to the payment API.
  This appears to be an external service outage, not a code bug.
  
SUGGESTIONS:
  - Check if payment-api.example.com is reachable
  - Consider increasing max_attempts or base_delay for this step
  - To retry: start a new run with the same input
```

### 4. Common Failure Patterns

When analyzing failures, check for these patterns:

| Pattern | Symptom | Likely Cause |
|---|---|---|
| All attempts same error | Consistent failure message | Bug in handler or external service down |
| Timeout on all attempts | `"task timed out"` | Step timeout too low or handler hangs |
| First attempt succeeds, others fail | Intermittent errors | Race condition or non-idempotent handler |
| Step stuck in `started` | Never completes | Worker crashed mid-execution, stalled task |
| Run stuck with `remaining_steps > 0` | Not all steps completed | Dependency chain broken or worker not running |

### 5. Check Worker Health

If runs are stuck or not progressing:

```sql
-- Check if workers are registered and active
SELECT * FROM pgflow.workers
WHERE flow_slug = 'process_order'
ORDER BY started_at DESC
LIMIT 5;
```

```sql
-- Check PGMQ queue depth
SELECT * FROM pgmq.metrics('process_order');
```

```bash
# Check if PgFlow supervisor is running
# In IEx:
Process.whereis(PgFlow.Supervisor)
Process.whereis(PgFlow.WorkerSupervisor)
```

### 6. Offer Next Steps

Based on the diagnosis, suggest:

| Diagnosis | Suggestion |
|---|---|
| External service down | Wait and retry, or increase retry config |
| Bug in handler | Fix the handler code, recompile, start new run |
| Timeout too low | Increase step timeout in the flow module, recompile |
| Stalled tasks | Check for stalled task recovery process, restart workers |
| Queue depth growing | Check worker count and `max_concurrency` config |
| Worker not running | Verify flow is in config `flows:` list and PgFlow is in supervision tree |

## Guardrails

- This subcommand is read-only — it inspects state but does not modify runs or retry failed steps
- Use `psql` or Ecto queries via `project_eval` for database access
- If Tidewave MCP is available, prefer `execute_sql_query` for SQL queries
- Run IDs are UUIDs — validate format before querying
- Do not expose raw SQL results; summarize into the structured report format
- If the user wants to retry a failed run, suggest starting a new run with the same input
