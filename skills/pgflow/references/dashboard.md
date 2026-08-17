# PgFlow Dashboard

Optional Phoenix LiveView dashboard for monitoring flows, jobs, runs, and workers.

## Installation

### 1. Generate Dashboard Migration

```bash
mix pgflow_dashboard.gen.migration
mix ecto.migrate
```

### 2. Optional: Add Performance Indexes

For high-traffic dashboards:

```bash
mix pgflow_dashboard.gen.indexes
mix ecto.migrate
```

### 3. Add to Router

```elixir
# lib/my_app_web/router.ex
import PgFlowDashboard.Router

scope "/" do
  pipe_through [:browser]
  pgflow_dashboard "/pgflow", repo: MyApp.Repo, pubsub: MyApp.PubSub
end
```

## Dashboard Pages

| Page | Content |
|------|---------|
| **Overview** | Active workers, run counts, key metrics |
| **Flows** | Flow definitions with 24h statistics |
| **Jobs** | Job definitions with statistics |
| **Crons** | Scheduled tasks with next run times |
| **Runs** | Filterable list with status, duration, progress (skipped steps count toward progress) |
| **Workers** | Worker health status and throughput |
| **Run Detail** | Interactive SVG DAG visualization, Gantt timeline, input/output inspection; skipped steps render distinctly (dashed/ghost) with their skip_reason |

## Access Control

Protect the dashboard in production:

```elixir
scope "/" do
  pipe_through [:browser, :require_admin]
  pgflow_dashboard "/pgflow", repo: MyApp.Repo, pubsub: MyApp.PubSub
end
```
