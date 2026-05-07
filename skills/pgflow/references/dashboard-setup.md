# pgflow dashboard

Add the PgFlow LiveView dashboard to a Phoenix application for monitoring flows, jobs, runs, and workers.

## Inputs

- **Arg form**: `/pgflow dashboard` — no additional args needed.
- **With path**: `/pgflow dashboard /admin/pgflow` — mount at specified path instead of default `/pgflow`.

## Prerequisites

- PgFlow already bootstrapped (run `/pgflow bootstrap` first if not)
- Phoenix LiveView available in the project

## Workflow

### 1. Detect App Context

```bash
grep "app:" mix.exs | head -1
```

Extract the app module name and web module name (e.g., `MyApp`, `MyAppWeb`).

### 2. Check if Dashboard Already Installed

```bash
grep -r "pgflow_dashboard" lib/ --include="*.ex" -l
```

If already present, tell the user and stop.

### 3. Generate Dashboard Migration

```bash
mix pgflow_dashboard.gen.migration
mix ecto.migrate
```

### 4. Optional: Add Performance Indexes

Ask the user if they expect high traffic on the dashboard. If yes:

```bash
mix pgflow_dashboard.gen.indexes
mix ecto.migrate
```

### 5. Add to Router

Read `lib/<app>_web/router.ex` and add the dashboard route.

Add the import at the top of the router module:

```elixir
import PgFlowDashboard.Router
```

Add a scope block — default path is `/pgflow`, but use the user's arg if provided:

```elixir
scope "/" do
  pipe_through [:browser]
  pgflow_dashboard "/pgflow", repo: MyApp.Repo, pubsub: MyApp.PubSub
end
```

### 6. Add Access Control (Production)

Ask the user how they want to protect the dashboard:
- Behind existing admin auth plug? → Add to an authenticated scope
- HTTP basic auth? → Add a simple plug
- No protection needed (internal tool)?

Example with existing auth:

```elixir
scope "/admin" do
  pipe_through [:browser, :require_admin]
  pgflow_dashboard "/pgflow", repo: MyApp.Repo, pubsub: MyApp.PubSub
end
```

### 7. Verify

```bash
mix phx.routes | grep pgflow
```

Tell the user the dashboard URL and what pages are available:

| Page | Content |
|------|---------|
| Overview | Active workers, run counts, key metrics |
| Flows | Flow definitions with 24h statistics |
| Jobs | Job definitions with statistics |
| Crons | Scheduled tasks with next run times |
| Runs | Filterable list with status, duration, progress |
| Workers | Worker health status and throughput |
| Run Detail | Interactive SVG DAG, timeline, input/output |

## Guardrails

- Do not add the dashboard if PgFlow is not bootstrapped
- Always protect the dashboard in production with authentication
- The dashboard requires `pubsub` in PgFlow config for real-time updates
- If `pubsub` is not configured, warn the user that real-time updates won't work
