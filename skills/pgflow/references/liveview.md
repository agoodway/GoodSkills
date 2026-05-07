# PgFlow LiveView Integration

## LiveClient API

`PgFlow.LiveClient` provides real-time flow tracking in Phoenix LiveView with automatic PubSub subscription, incremental state updates, and multi-run tracking.

### Setup

```elixir
defmodule MyAppWeb.FlowLive do
  use MyAppWeb, :live_view
  alias PgFlow.LiveClient

  def mount(_params, _session, socket) do
    {:ok, LiveClient.init(socket, pubsub: MyApp.PubSub)}
  end
end
```

### Starting and Tracking a Flow

```elixir
def handle_event("start_process", params, socket) do
  case LiveClient.start_flow(socket, :process_order, params, as: :run) do
    {:ok, socket} -> {:noreply, socket}
    {:error, reason, socket} -> {:noreply, put_flash(socket, :error, reason)}
  end
end
```

The `:as` option sets the assign name. After starting, `@run` contains a `PgFlow.Schema.Run` struct with `step_states`.

### Handling Updates

```elixir
def handle_info({:pgflow, _, _} = msg, socket) do
  {:noreply, LiveClient.handle_info(msg, socket)}
end
```

LiveClient receives PubSub messages and applies incremental updates to the in-memory run struct. Status only advances forward: `created` → `started` → `completed`/`failed`.

### Rendering Run State

```heex
<button phx-click="start_process">Start</button>

<div :if={@run}>
  <p>Status: {@run.status}</p>

  <div :for={step <- @run.step_states}>
    <div>
      <span class="font-medium">{step.step_slug}</span>
      <span>{step.status}</span>
    </div>
    <div :if={step.output}>
      <pre>{Jason.encode!(step.output, pretty: true)}</pre>
    </div>
    <div :if={step.error_message} class="text-red-600">
      {step.error_message}
    </div>
  </div>
</div>
```

### Multiple Run Tracking

Track multiple flows simultaneously with different assign names:

```elixir
def handle_event("start_validation", params, socket) do
  case LiveClient.start_flow(socket, :validate_order, params, as: :validation_run) do
    {:ok, socket} -> {:noreply, socket}
    {:error, reason, socket} -> {:noreply, socket}
  end
end

def handle_event("start_processing", params, socket) do
  case LiveClient.start_flow(socket, :process_order, params, as: :processing_run) do
    {:ok, socket} -> {:noreply, socket}
    {:error, reason, socket} -> {:noreply, socket}
  end
end
```

Access as `@validation_run` and `@processing_run` in templates.

### Subscribing to Existing Runs

Track a run that was started elsewhere:

```elixir
def handle_event("track_run", %{"run_id" => run_id}, socket) do
  case LiveClient.subscribe(socket, run_id, as: :tracked_run) do
    {:ok, socket} -> {:noreply, socket}
    {:error, reason, socket} -> {:noreply, socket}
  end
end
```

### Cleanup

Unsubscribe when no longer tracking:

```elixir
LiveClient.unsubscribe(socket, :run)
```

Automatic cleanup happens on LiveView unmount.

## Run and StepState Structs

### PgFlow.Schema.Run

```elixir
%PgFlow.Schema.Run{
  id: "uuid",
  flow_slug: "process_order",
  status: "started",          # "created", "started", "completed", "failed"
  input: %{"order_id" => 123},
  output: nil,                # populated on completion
  remaining_steps: 3,
  step_states: [...]          # list of StepState structs
}
```

### PgFlow.Schema.StepState

```elixir
%PgFlow.Schema.StepState{
  step_slug: "validate",
  status: "completed",        # "created", "started", "completed", "failed"
  output: %{"valid" => true},
  error_message: nil,
  attempts_made: 1
}
```

## PubSub Configuration

LiveClient requires `pubsub` in the PgFlow config:

```elixir
config :my_app, MyApp.PgFlow,
  pubsub: MyApp.PubSub,
  # ...
```

PgFlow broadcasts telemetry events via PubSub on topics like `pgflow:run:{run_id}`. LiveClient subscribes to these automatically.
