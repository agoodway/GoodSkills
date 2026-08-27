# pgflow flow

Scaffold a new PgFlow flow module with step definitions and generate the database migration to compile it.

## Inputs

- **Arg form**: `/pgflow flow MyApp.Flows.ProcessOrder` — use the provided module name directly.
- **No arg**: Ask the user for the flow module name. Suggest a name based on the app module detected from `mix.exs`.

## Workflow

### 1. Detect App Context

```bash
grep "app:" mix.exs | head -1
```

Extract the app module name (e.g., `MyApp`) and OTP app name (e.g., `my_app`).

### 2. Ask About the Flow

If the user didn't describe the flow's purpose, ask:
- What does this flow do? (e.g., "process an order", "generate a report", "onboard a user")
- What steps are involved? (e.g., "validate, charge, notify")

If the user described the flow in the invocation args, derive the steps from that description.

### 3. Generate the Flow Module

Create `lib/<app>/flows/<flow_name>.ex`:

```elixir
defmodule MyApp.Flows.ProcessOrder do
  use PgFlow.Flow

  @flow queue: :process_order, max_attempts: 3, base_delay: 5, timeout: 60

  step :validate do
    fn input, _ctx ->
      # TODO: Implement validation
      %{valid: true}
    end
  end

  step :process, depends_on: [:validate] do
    fn deps, _ctx ->
      # TODO: Implement processing
      %{processed: true}
    end
  end

  step :finalize, depends_on: [:process] do
    fn deps, _ctx ->
      # TODO: Implement finalization
      %{status: "completed"}
    end
  end
end
```

Rules for generating the module:
- Queue slug is the snake_case version of the last segment of the module name
- Steps should reflect the user's described workflow
- Root steps (no deps) receive flow input; dependent steps receive a map of dep outputs
- Use realistic step names based on the flow's domain
- Include TODO comments for handler bodies unless the user gave specific logic
- If the user described parallel work, use multiple root steps or `map` for array processing

### 4. Register in Config

Read `config/config.exs` and add the new module to the `flows:` list:

```elixir
config :my_app, PgFlow,
  flows: [MyApp.Flows.ProcessOrder],  # add to existing list
  # ...
```

If PgFlow is not yet configured, tell the user to run `/pgflow bootstrap` first.

### 5. Compile to Database

```bash
mix pgflow.gen.flow_migration MyApp.Flows.ProcessOrder
mix ecto.migrate
```

### 6. Show Usage

Print how to start the flow:

```elixir
{:ok, run_id} = PgFlow.start_flow(:process_order, %{"key" => "value"})
```

## Step Type Guidance

When generating steps, apply these patterns:

| User describes... | Generate... |
|---|---|
| Sequential actions | Steps with linear `depends_on` chain |
| "Then do A and B at the same time" | Two steps with same `depends_on` (parallel) |
| "For each item..." | `map` step with `:array` option |
| "Wait for all to finish then..." | Step with `depends_on` listing all parallel steps |
| External API call | Step with longer `timeout: 120` |
| Something that might fail | Step with higher `max_attempts: 5` |

## Guardrails

- Always use `use PgFlow.Flow` and the `@flow` module attribute
- Queue slugs must be unique across all flows and jobs
- All handler return values must be JSON-serializable
- Do not create the migration file manually — use `mix pgflow.gen.flow_migration`
- If the flow has a `map` step, the array source step must return a list
