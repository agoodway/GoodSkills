# Add the PgFlow dashboard

Install the complete core-backed LiveView dashboard, not just its route. Accept an optional mount path; default to `/pgflow`.

## Inspect first

Confirm PgFlow is installed and compatible:

```bash
mix pgflow.check_schema --repo MyApp.Repo
rg -n "PgFlowDashboard|pgflow_dashboard|livefilter|pgflow_dashboard/hooks" lib assets mix.exs config
```

Treat each component independently. Existing route text does not prove supervision, dependencies, hooks, or asset scanning are installed.

## Install runtime pieces

Add `livefilter` explicitly to `mix.exs` because it is optional in PgFlow, then run `mix deps.get`. Use the version compatible with the installed PgFlow release rather than copying a stale hardcoded constraint.

Start the dashboard after the repo/PubSub:

```elixir
children = [
  MyApp.Repo,
  {Phoenix.PubSub, name: MyApp.PubSub},
  PgFlowDashboard,
  MyAppWeb.Endpoint
]
```

Add the protected route:

```elixir
import PgFlowDashboard.Router

scope "/" do
  pipe_through [:browser, :require_authenticated_admin]

  pgflow_dashboard "/pgflow",
    repo: MyApp.Repo,
    pubsub: MyApp.PubSub
end
```

An `on_mount` authorization hook is also supported. Never expose the dashboard publicly by default.

## Configure assets

Import PgFlow Dashboard and LiveFilter hooks from their dependency asset paths and merge them into the LiveSocket hooks. The installed PgFlow `docs/DASHBOARD.md` is the authority for the current hook names.

Ensure the JS bundler can resolve dependency assets. For esbuild, set `NODE_PATH` to the application's `deps/` directory. Add Tailwind sources for:

```css
@source "../../deps/pgflow/lib/pgflow_dashboard";
@source "../../deps/daisy_ui_components";
@source "../../deps/livefilter";
```

Use equivalent content globs for legacy `tailwind.config.js` projects.

## Database objects

The core-backed dashboard does not need `PgFlowDashboard.Migration`. Only historical external SQL consumers need those views/functions. For those consumers, use `mix pgflow.setup --upgrade --dashboard` during a coordinated PgFlow upgrade or generate a dedicated `mix pgflow_dashboard.gen.migration` wrapper.

Optional high-traffic indexes are still available:

```bash
mix pgflow_dashboard.gen.indexes
mix ecto.migrate
```

## Verify

```bash
mix phx.routes | rg pgflow
mix assets.build
```

Boot the app and smoke-test overview, flows, jobs, crons, runs, worker detail, filtering, keyboard/mobile menu hooks, real-time updates, and the authenticated boundary. If data is absent, first call `PgFlow.Metrics.overview(MyApp.Repo)` in IEx; if filtering is broken, recheck LiveFilter, `NODE_PATH`, hooks, and Tailwind sources.
