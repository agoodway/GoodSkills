# PgFlow Conditional Steps Reference

Conditional step execution: run, skip, or fail steps based on input patterns (`if:` / `if_not:` / `when_unmet:`), and convert exhausted retries into skips instead of run failures (`when_exhausted:`). Skips are decided entirely in PostgreSQL — Elixir observes the decision.

## When to Reach for Conditionals

| Situation | Use | Instead of |
|---|---|---|
| Step applies only to some inputs (plan tiers, feature flags, record types) | `if:` / `if_not:` (default skip) | `if/else` inside the handler returning placeholder output |
| A whole sub-graph applies only conditionally | `when_unmet: :skip_cascade` on the gate step | repeating the condition on every downstream step |
| Optional / fail-soft step (notification, enrichment) whose permanent failure must not fail the run | `when_exhausted: :skip` (or `:skip_cascade`) | rescue-and-swallow inside the handler |
| Missing or invalid gating input should abort the run loudly | `when_unmet: :fail` | letting the handler raise |

Prefer branching **inside the handler** when the step must always run and produce output. Prefer **conditionals** when the step (and possibly its subtree) should not run at all: skipped steps consume no worker time, produce no output, record why they were skipped, and render as `skipped` — not `completed` — in the dashboard, LiveClient, and telemetry.

## Options

All four options work on both `step` and `map`, in the compile-time DSL and in runtime `upsert_flow` step maps:

| Option | Values | Default | Meaning |
|---|---|---|---|
| `if:` | JSON-encodable map | — | Step runs only if its input **contains** this pattern |
| `if_not:` | JSON-encodable map | — | Step runs only if its input does **not** contain this pattern |
| `when_unmet:` | `:fail` / `:skip` / `:skip_cascade` | `:skip` | Outcome when `if:`/`if_not:` is not satisfied. Requires `if:` or `if_not:` |
| `when_exhausted:` | `:fail` / `:skip` / `:skip_cascade` | `:fail` | Outcome when the step exhausts `max_attempts` |

String equivalents are accepted everywhere: `"fail"`, `"skip"`, `"skip_cascade"`, and the SQL literal `"skip-cascade"`. Defaults live in the database — options you don't set fall through to SQL `DEFAULT`s.

## What the Pattern Matches Against

Matching is PostgreSQL jsonb containment (`@>`) — the pattern must be *contained in* the input, so extra keys in the input are fine.

- **Root steps** (no `depends_on`) match against the **flow input**:

  ```elixir
  step :premium_only, if: %{"plan" => "premium"} do
  ```

- **Dependent steps** match against their **deps object** — string-keyed, shaped `%{"dep_slug" => dep_output}`:

  ```elixir
  # Gate on the OUTPUT of the :create_account dependency
  step :setup_premium,
    depends_on: [:create_account],
    if: %{"create_account" => %{"plan" => "premium"}},
    when_unmet: :skip_cascade do
  ```

Keys are JSON strings, never atoms — `if: %{plan: "premium"}` on a dependent step will not match `%{"create_account" => ...}`.

## Skip Semantics

Every skipped step records a machine-readable `skip_reason` in `pgflow.step_states`:

| skip_reason | Meaning |
|---|---|
| `condition_unmet` | The step's own `if:`/`if_not:` was not satisfied |
| `dependency_skipped` | A dependency was skipped with `:skip_cascade` (propagates transitively) |
| `handler_failed` | Retries exhausted with `when_exhausted: :skip`/`:skip_cascade` |

Rules that follow:

- **Runs with skipped steps complete successfully.** Skipped counts as resolved, not failed.
- **`:skip` omits the key** — a dependent of a non-cascade-skipped step still runs, and the skipped dependency's key is **absent** from its deps map (not `nil`). Write dependents defensively:

  ```elixir
  step :finish, depends_on: [:create_account, :send_welcome] do
    fn deps, _ctx ->
      # deps["send_welcome"] may be MISSING entirely if it was skipped
      welcomed = Map.get(deps, "send_welcome", %{"sent" => false})
      %{done: true, welcomed: welcomed["sent"]}
    end
  end
  ```

- **`:skip_cascade` propagates**: everything depending on the skipped step (directly or through other skipped steps) is also skipped with `dependency_skipped`.
- **Type violations are exempt** from `when_exhausted` skipping — structurally invalid input fails outright rather than being masked as a skip.

## Complete Example

```elixir
defmodule MyApp.Flows.Onboarding do
  use PgFlow.Flow

  # `queue:` is the canonical option name; `slug:` is accepted as an alias.
  @flow queue: :onboarding, max_attempts: 3, base_delay: 1, timeout: 30

  step :create_account do
    fn input, _ctx -> %{account_id: 123, plan: input["plan"]} end
  end

  # Premium gate: skipped (with its whole subtree) for non-premium plans.
  step :setup_premium,
    depends_on: [:create_account],
    if: %{"create_account" => %{"plan" => "premium"}},
    when_unmet: :skip_cascade do
    fn deps, _ctx -> %{tier: "premium"} end
  end

  # Cascades to skipped/"dependency_skipped" when :setup_premium is skipped.
  step :activate_perk, depends_on: [:setup_premium] do
    fn deps, _ctx -> %{perk: true} end
  end

  # Fail-soft: a permanently erroring email marks this step skipped
  # ("handler_failed") instead of failing the run.
  step :send_welcome, depends_on: [:create_account], when_exhausted: :skip do
    fn deps, _ctx -> MyApp.Mailer.welcome(deps["create_account"]) end
  end

  step :finish, depends_on: [:create_account] do
    fn _deps, _ctx -> %{onboarded: true} end
  end
end
```

`%{"plan" => "premium"}` input: everything runs. `%{"plan" => "free"}`: `setup_premium` skips (`condition_unmet`), `activate_perk` skips (`dependency_skipped`), the rest completes — run status `completed`.

## Runtime API

`PgFlow.Client.upsert_flow/2` accepts the same four keys per step map (atom or string keys/values):

```elixir
PgFlow.Client.upsert_flow("acct_123_sync_v1",
  steps: [
    %{slug: "reshape", deps: []},
    %{
      slug: "premium_only",
      deps: ["reshape"],
      if: %{"reshape" => %{"plan" => "premium"}},
      when_unmet: :skip_cascade,
      when_exhausted: :skip
    }
  ]
)
```

Validation errors: `{:invalid_condition_pattern, key, value}` (pattern not a map), `{:invalid_condition_mode, key, value}` (mode outside fail/skip/skip_cascade), `{:when_unmet_requires_condition, slug}` (`when_unmet:` without `if:`/`if_not:`).

## Compiling and Version Requirements

After adding or changing conditions on a DSL flow, regenerate and migrate:

```bash
mix pgflow.gen.flow_migration MyApp.Flows.Onboarding
mix ecto.migrate
```

**Version gotcha:** pgflow releases without conditional support **silently ignore** these options — the flow compiles, but every step always runs. If conditions appear to be no-ops, verify the installed pgflow ships the step-conditions schema (the `pgflow.steps` table must have `when_unmet` / `when_exhausted` / `required_input_pattern` columns).

## Observing Skips

- **Step states**: `pgflow.step_states` rows carry `status = 'skipped'`, `skip_reason`, and `skipped_at`. `PgFlow.get_run_with_states/1` exposes all three.
- **Telemetry**: `[:pgflow, :step, :skipped]` fires with `flow_slug`, `run_id`, `step_slug`, `skip_reason`. Delivery is exactly-once **per emitter** (the client on synchronous start-time skips, each worker for skips it discovers) — consumers needing global exactly-once should dedupe on `{run_id, step_slug}`.
- **LiveClient**: `skipped` is a first-class step status; a provisional `failed` from a `when_exhausted: :skip` step is replaced by the authoritative `skipped`.
- **Dashboard**: skipped steps count toward progress, render distinctly in the run DAG and Gantt timeline, and show their skip_reason.

## Guardrails

- `when_unmet:` requires `if:` or `if_not:` on the same step — it is rejected otherwise. `when_exhausted:` stands alone.
- Dependent-step patterns must be string-keyed and nested under the dependency's slug: `if: %{"dep_slug" => %{...}}`.
- Containment, not equality: the pattern may match more inputs than intended if it is too sparse.
- Dependents of a `:skip` (non-cascade) step still run — handle the missing deps key. Use `:skip_cascade` if dependents are meaningless without the output.
- Conditions are step-level: a `map` step's condition gates the whole array, not individual items.
- Do not use `when_exhausted: :skip` on steps whose output later steps require without a fallback — prefer `:skip_cascade` there.
- Always recompile the flow to the database after adding or changing conditions.
