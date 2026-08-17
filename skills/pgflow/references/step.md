# pgflow step

Add a new step to an existing PgFlow flow module.

## Inputs

- **Arg form**: `/pgflow step MyApp.Flows.ProcessOrder notify` — add step `notify` to the given flow.
- **Partial arg**: `/pgflow step notify` — add step `notify` to a flow (ask which one if multiple exist).
- **No arg**: Ask the user which flow to modify and what step to add.

## Workflow

### 1. Locate the Flow Module

If a module name was provided, find the file:

```bash
# Search for the module definition
grep -r "defmodule MyApp.Flows.ProcessOrder" lib/ --include="*.ex" -l
```

If no module was provided, list available flows:

```bash
grep -r "use PgFlow.Flow" lib/ --include="*.ex" -l
```

Present the list and ask the user which flow to modify.

### 2. Read the Flow

Read the flow module file. Identify:
- Existing steps and their slugs
- The DAG structure (which steps depend on which)
- Terminal steps (steps that no other step depends on)
- Map steps and their array sources

### 3. Ask About the Step

If not already clear from the args, ask:
- What should this step do?
- What does it depend on? (suggest terminal steps as likely candidates)
- Is it a single step or a map step (processes array items)?
- Should it always run, or only for certain inputs? ("only for premium users", "unless X", "skip when...") — if conditional, use `if:`/`if_not:` per [conditional-steps.md](conditional-steps.md)
- If it can fail permanently, should that fail the run, or should the step be skipped (`when_exhausted: :skip`)?

### 4. Determine Step Placement

Based on the user's description and the existing DAG:

| User says... | Placement |
|---|---|
| "after everything" / "at the end" | `depends_on:` lists current terminal steps |
| "after validate" | `depends_on: [:validate]` |
| "in parallel with process" | Same `depends_on` as the `:process` step |
| "for each item from X" | `map` step with `array: :x` |
| "at the beginning" / "before everything" | Root step (no `depends_on`), update existing root steps to depend on it |
| "between validate and process" | `depends_on: [:validate]`, update `:process` to depend on new step |
| "only when/if ..." / "unless ..." | Add `if:`/`if_not:` pattern; pick `when_unmet:` (`:skip` just this step, `:skip_cascade` its subtree, `:fail` abort) |
| "optional" / "shouldn't break the run" | `when_exhausted: :skip` (fail-soft) |

### 5. Generate the Step

Add the step to the flow module at the appropriate location (after its dependencies, before its dependents):

```elixir
step :notify, depends_on: [:process] do
  fn deps, _ctx ->
    # TODO: Implement notification logic
    %{notified: true}
  end
end
```

Or for a map step:

```elixir
map :notify_each, array: :process do
  fn item, _ctx ->
    # TODO: Process each item
    %{notified: true}
  end
end
```

### 6. Update Dependencies if Inserting

If the new step is inserted between existing steps (not appended at the end), update the downstream step's `depends_on` to reference the new step instead of the old dependency.

**Example**: Inserting `:enrich` between `:validate` and `:process`:

Before:
```elixir
step :process, depends_on: [:validate] do
```

After:
```elixir
step :enrich, depends_on: [:validate] do
  fn deps, _ctx -> %{enriched: true} end
end

step :process, depends_on: [:enrich] do
```

### 7. Recompile to Database

After modifying the flow module, regenerate and migrate:

```bash
mix pgflow.gen.flow_migration MyApp.Flows.ProcessOrder
mix ecto.migrate
```

Warn the user: recompiling a flow creates a new version. Existing in-progress runs continue on the old version; new runs use the updated definition.

### 8. Show Updated DAG

Print the updated step dependency chain so the user can verify:

```
validate → enrich → process → notify
                  ↘ charge  ↗
```

## Step Options Reference

| Option | Type | Default | Description |
|---|---|---|---|
| `depends_on` | list of atoms | `[]` | Steps this depends on |
| `handler` | module | nil | External handler module |
| `max_attempts` | integer | flow default | Override retry attempts |
| `base_delay` | integer | flow default | Override backoff delay |
| `timeout` | integer | flow default | Override execution timeout |
| `start_delay` | integer | 0 | Delay before step starts (seconds) |
| `array` | atom | nil | For map steps: step whose output to iterate |
| `if` / `if_not` | map | nil | Input-pattern gate (jsonb containment) — [conditional-steps.md](conditional-steps.md) |
| `when_unmet` | atom | `:skip` | `:fail`/`:skip`/`:skip_cascade` when the gate is unsatisfied |
| `when_exhausted` | atom | `:fail` | `:fail`/`:skip`/`:skip_cascade` when retries are exhausted |

## Guardrails

- Do not introduce cycles — the DAG must remain acyclic
- Step slugs must be unique within a flow
- Map steps require the `:array` source step to return a list
- If inserting between steps, update both the new step's `depends_on` and the downstream step's `depends_on`
- Always recompile to database after modifying steps
- Handler return values must be JSON-serializable
- `when_unmet:` requires `if:` or `if_not:` on the same step; dependent-step patterns must be string-keyed under the dependency's slug (`if: %{"dep_slug" => %{...}}`)
- Dependents of a `:skip` (non-cascade) step still run with that dependency's key **missing** from their deps map — handle it with `Map.get/3`, or use `:skip_cascade`
