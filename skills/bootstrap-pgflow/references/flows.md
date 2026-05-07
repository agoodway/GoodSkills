# PgFlow Flow DSL Reference

## Defining a Flow

```elixir
defmodule MyApp.Flows.ProcessOrder do
  use PgFlow.Flow

  @flow queue: :process_order,
       max_attempts: 3,
       base_delay: 5,
       timeout: 60,
       cron: [schedule: "0 9 * * *", input: %{"type" => "daily"}]  # optional
end
```

### @flow Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `queue` | atom | required | Unique queue identifier (becomes PGMQ queue name) |
| `max_attempts` | integer | 3 | Maximum retry attempts per step |
| `base_delay` | integer | 5 | Initial backoff delay in seconds |
| `timeout` | integer | 60 | Execution timeout per step in seconds |
| `cron` | keyword | nil | Scheduled execution (`schedule:` cron expr, `input:` default input) |

## Step Types

### step — Single Execution

Root steps (no dependencies) receive the flow input directly:

```elixir
step :validate do
  fn input, ctx ->
    %{valid: input["amount"] > 0, order_id: input["order_id"]}
  end
end
```

Dependent steps receive a map of dependency outputs:

```elixir
step :charge, depends_on: [:validate, :lookup_customer] do
  fn deps, ctx ->
    # deps.validate => output of :validate step
    # deps.lookup_customer => output of :lookup_customer step
    %{charged: true, amount: deps.validate["amount"]}
  end
end
```

### map — Parallel Array Processing

Processes each element of an array output in parallel:

```elixir
map :send_notifications, array: :charge do
  fn item, ctx ->
    # item = single element from :charge step's output array
    %{sent: true, recipient: item["email"]}
  end
end
```

The `:array` option specifies which dependency step produces the array to iterate.

### Step Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `depends_on` | list of atoms | `[]` | Steps this depends on (empty = root step) |
| `handler` | module | nil | External handler module (alternative to inline fn) |
| `max_attempts` | integer | flow default | Override retry attempts |
| `base_delay` | integer | flow default | Override backoff delay |
| `timeout` | integer | flow default | Override execution timeout |
| `start_delay` | integer | 0 | Delay before step starts (seconds) |
| `array` | atom | nil | For map steps: which step's output to iterate |

## Handler Context

Every handler receives a `PgFlow.Context` struct as the second argument:

```elixir
step :process do
  fn input, ctx ->
    ctx.run_id        # UUID of this run
    ctx.step_slug     # :process (atom)
    ctx.task_index    # 0 for single steps, N for map items
    ctx.attempt       # current retry attempt (1-indexed)
    ctx.repo          # Ecto repo for database queries

    # Lazy-load the original flow input (useful in dependent steps)
    flow_input = PgFlow.Context.get_flow_input(ctx)

    %{result: "done"}
  end
end
```

## Handler Return Values

Handlers can return:

```elixir
# Success — map is serialized to JSON and stored as step output
%{key: "value"}

# Success — explicit ok tuple
{:ok, %{key: "value"}}

# Failure — triggers retry (up to max_attempts)
{:error, "something went wrong"}

# Failure — raises are caught and trigger retry
raise "unexpected error"
```

All return values must be JSON-serializable (maps, lists, strings, numbers, booleans, nil).

## DAG Rules

- Steps form a directed acyclic graph (DAG) — no cycles allowed
- Steps with no `depends_on` are root steps and run immediately
- A step runs only after ALL its dependencies complete successfully
- If any step fails (exhausts retries), the entire run fails
- Map steps expand at runtime based on the array length
- Multiple root steps run in parallel

## Example: Multi-Step Order Pipeline

```elixir
defmodule MyApp.Flows.ProcessOrder do
  use PgFlow.Flow

  @flow queue: :process_order, max_attempts: 3, base_delay: 5, timeout: 60

  # Root steps run in parallel
  step :validate_order do
    fn input, _ctx ->
      %{valid: true, order_id: input["order_id"]}
    end
  end

  step :lookup_inventory do
    fn input, _ctx ->
      %{available: true, items: input["items"]}
    end
  end

  # Waits for both root steps
  step :reserve_inventory, depends_on: [:validate_order, :lookup_inventory] do
    fn deps, _ctx ->
      %{reserved: true, items: deps.lookup_inventory["items"]}
    end
  end

  # Charges after reservation
  step :charge_payment, depends_on: [:reserve_inventory], timeout: 120 do
    fn deps, _ctx ->
      %{charged: true, transaction_id: Ecto.UUID.generate()}
    end
  end

  # Sends notifications to each party in parallel
  map :notify_parties, array: :charge_payment do
    fn item, _ctx ->
      %{notified: true}
    end
  end

  # Final step
  step :complete, depends_on: [:notify_parties] do
    fn deps, _ctx ->
      %{status: "completed"}
    end
  end
end
```

## Compiling Flows

Flows must be compiled to the database before workers can process them:

```bash
mix pgflow.gen.flow MyApp.Flows.ProcessOrder
mix ecto.migrate
```

This creates:
- Flow record in `pgflow.flows`
- PGMQ queue `pgmq.q_process_order`
- Step definitions in `pgflow.steps`
- pg_cron job if `:cron` option specified

## Starting Flows

```elixir
# Async — returns immediately
{:ok, run_id} = PgFlow.start_flow(:process_order, %{
  "order_id" => 123,
  "items" => ["item_a", "item_b"]
})

# Sync — waits for completion
{:ok, run} = PgFlow.start_flow_sync(:process_order, %{
  "order_id" => 123
}, timeout: 30_000, poll_interval: 500)

# Check status
{:ok, run} = PgFlow.get_run(run_id)
run.status  # "started", "completed", or "failed"

# With step details
{:ok, run} = PgFlow.get_run_with_states(run_id)
run.step_states  # list of StepState structs
```
