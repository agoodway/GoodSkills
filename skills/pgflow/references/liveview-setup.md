# pgflow liveview

Scaffold a Phoenix LiveView module with PgFlow LiveClient integration for real-time flow tracking.

## Inputs

- **Arg form**: `/pgflow liveview MyAppWeb.OrderFlowLive :process_order` — create LiveView for the given flow.
- **Partial arg**: `/pgflow liveview :process_order` — create LiveView, derive module name from flow slug.
- **No arg**: Ask the user which flow to track and what to name the LiveView.

## Workflow

### 1. Detect App Context

```bash
grep "app:" mix.exs | head -1
```

Extract the app module name and web module name.

### 2. Identify the Flow

If a flow slug was provided, verify it exists:

```bash
grep -r "queue: :process_order" lib/ --include="*.ex" -l
```

If no flow was specified, list available flows:

```bash
grep -r "use PgFlow.Flow" lib/ --include="*.ex" -l
```

Read each to extract queue slugs and present them to the user.

### 3. Read the Flow Module

Read the flow to understand:
- The queue slug
- What input it expects
- What steps exist (for rendering step progress)
- What output each step produces

### 4. Generate the LiveView Module

Create `lib/<app>_web/live/<flow_name>_live.ex`:

```elixir
defmodule MyAppWeb.OrderFlowLive do
  use MyAppWeb, :live_view

  alias PgFlow.LiveClient

  @flow_slug :process_order

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> LiveClient.init(pubsub: MyApp.PubSub)
      |> assign(:form, to_form(%{"order_id" => ""}))

    {:ok, socket}
  end

  @impl true
  def handle_event("start", %{"order_id" => order_id}, socket) do
    input = %{"order_id" => order_id}

    case LiveClient.start_flow(socket, @flow_slug, input, as: :run) do
      {:ok, socket} ->
        {:noreply, socket}

      {:error, reason, socket} ->
        {:noreply, put_flash(socket, :error, "Failed to start: #{reason}")}
    end
  end

  @impl true
  def handle_info({:pgflow, _, _} = msg, socket) do
    {:noreply, LiveClient.handle_info(msg, socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto p-6">
      <h1 class="text-2xl font-bold mb-6">Process Order</h1>

      <.form for={@form} phx-submit="start" class="mb-8">
        <div class="flex gap-4">
          <input
            type="text"
            name="order_id"
            value={@form[:order_id].value}
            placeholder="Order ID"
            class="input input-bordered flex-1"
          />
          <button type="submit" class="btn btn-primary" disabled={@run && @run.status == "started"}>
            Start Flow
          </button>
        </div>
      </.form>

      <div :if={@run} class="space-y-4">
        <div class="flex items-center gap-2">
          <span class="font-medium">Status:</span>
          <span class={[
            "badge",
            @run.status == "completed" && "badge-success",
            @run.status == "failed" && "badge-error",
            @run.status == "started" && "badge-info"
          ]}>
            {@run.status}
          </span>
        </div>

        <div class="space-y-2">
          <h2 class="text-lg font-semibold">Steps</h2>
          <div :for={step <- @run.step_states} class="flex items-center justify-between p-3 bg-base-200 rounded-lg">
            <span class="font-mono">{step.step_slug}</span>
            <span class={[
              "badge badge-sm",
              step.status == "completed" && "badge-success",
              step.status == "failed" && "badge-error",
              step.status == "started" && "badge-info",
              step.status == "created" && "badge-ghost"
            ]}>
              {step.status}
            </span>
          </div>
        </div>

        <div :if={@run.status == "completed" && @run.output} class="mt-4">
          <h2 class="text-lg font-semibold">Output</h2>
          <pre class="bg-base-200 p-4 rounded-lg text-sm overflow-auto"><%= Jason.encode!(@run.output, pretty: true) %></pre>
        </div>

        <div :if={@run.status == "failed"} class="alert alert-error mt-4">
          <div>
            <div :for={step <- Enum.filter(@run.step_states, & &1.error_message)}>
              <strong>{step.step_slug}:</strong> {step.error_message}
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
```

### 5. Customize the Template

Adapt the generated LiveView based on the flow:
- Replace the form fields with inputs matching the flow's expected input keys
- Replace the page title and labels with the flow's domain language
- If the flow has many steps, consider grouping them visually
- If using Tailwind without DaisyUI, replace `badge`, `btn`, `input` classes with plain Tailwind

### 6. Add Route

Read `lib/<app>_web/router.ex` and add a route for the LiveView:

```elixir
scope "/", MyAppWeb do
  pipe_through [:browser]
  live "/orders/process", OrderFlowLive
end
```

### 7. Verify

Tell the user the URL and how to test:

```
Visit http://localhost:4000/orders/process
Enter an order ID and click "Start Flow"
Watch the steps update in real-time as the flow executes
```

## Multiple Flow Tracking

If the user needs to track multiple flows on one page:

```elixir
LiveClient.start_flow(socket, :flow_a, input_a, as: :run_a)
LiveClient.start_flow(socket, :flow_b, input_b, as: :run_b)
```

Access as `@run_a` and `@run_b` in the template.

## Subscribing to Existing Runs

To track a run started elsewhere (e.g., from an API):

```elixir
def handle_event("track", %{"run_id" => run_id}, socket) do
  case LiveClient.subscribe(socket, run_id, as: :tracked_run) do
    {:ok, socket} -> {:noreply, socket}
    {:error, reason, socket} -> {:noreply, socket}
  end
end
```

## Guardrails

- Always use `LiveClient.init/2` in mount — it sets up required assigns
- Always handle `{:pgflow, _, _}` messages in `handle_info` — missing this means no updates
- The `pubsub` option must match the PgFlow config
- LiveClient applies incremental updates — no polling needed
- Status only advances forward: `created` → `started` → `completed`/`failed`
