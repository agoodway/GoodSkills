# PgFlow Telemetry Reference

PgFlow emits telemetry events for monitoring, metrics, and observability.

## Events

### Worker Events

```elixir
[:pgflow, :worker, :start]          # Worker process started
[:pgflow, :worker, :stop]           # Worker process stopped
[:pgflow, :worker, :poll, :start]   # Poll cycle started
[:pgflow, :worker, :poll, :stop]    # Poll cycle completed
[:pgflow, :worker, :task, :start]   # Task execution started
[:pgflow, :worker, :task, :stop]    # Task execution completed
[:pgflow, :worker, :task, :exception]  # Task execution raised
```

### Step Events

```elixir
[:pgflow, :step, :skipped]    # Step skipped without running (conditional gate,
                              # cascade, or when_exhausted skip)
```

Metadata: `flow_slug`, `run_id`, `step_slug`, `skip_reason` (`"condition_unmet"`, `"dependency_skipped"`, or `"handler_failed"`). Delivery is exactly-once per emitter, not globally — handlers needing global exactly-once should dedupe on `{run_id, step_slug}`. See [conditional-steps.md](conditional-steps.md).

### Run Events

```elixir
[:pgflow, :run, :started]     # Run transitioned to started
[:pgflow, :run, :completed]   # Run completed successfully (skipped steps count as resolved)
[:pgflow, :run, :failed]      # Run failed (step exhausted retries with when_exhausted: :fail)
```

## Attaching Handlers

```elixir
:telemetry.attach_many(
  "pgflow-metrics",
  [
    [:pgflow, :worker, :task, :stop],
    [:pgflow, :run, :completed],
    [:pgflow, :run, :failed]
  ],
  &MyApp.Metrics.handle_event/4,
  nil
)
```

## Example: Prometheus Metrics

```elixir
defmodule MyApp.Metrics do
  def handle_event([:pgflow, :worker, :task, :stop], measurements, metadata, _config) do
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)
    # Record task duration histogram
    :telemetry.execute([:my_app, :pgflow_task_duration], %{value: duration_ms}, %{
      flow: metadata.flow_slug,
      step: metadata.step_slug
    })
  end

  def handle_event([:pgflow, :run, :completed], _measurements, metadata, _config) do
    # Increment completion counter
    :telemetry.execute([:my_app, :pgflow_run_completed], %{count: 1}, %{
      flow: metadata.flow_slug
    })
  end

  def handle_event([:pgflow, :run, :failed], _measurements, metadata, _config) do
    # Increment failure counter
    :telemetry.execute([:my_app, :pgflow_run_failed], %{count: 1}, %{
      flow: metadata.flow_slug
    })
  end
end
```

## Structured Logging

Enable the built-in structured logger:

```elixir
config :my_app, MyApp.PgFlow,
  attach_default_logger: true
```

This logs all telemetry events with structured metadata (flow_slug, step_slug, run_id, duration, etc.) via `Logger`.
