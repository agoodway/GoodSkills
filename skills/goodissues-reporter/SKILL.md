---
name: goodissues-reporter
description: "Set up and configure GoodIssuesReporter in Elixir/Phoenix applications. Dispatches subcommands via `/goodissues-reporter [subcommand]`. Use when the user says '/goodissues-reporter bootstrap', '/goodissues-reporter help', 'add goodissues reporter', 'setup error reporting', 'add goodissues monitoring', or wants to integrate GoodIssuesReporter into a Phoenix app."
---

# GoodIssues Reporter

Set up [GoodIssuesReporter](https://github.com/agoodway/goodissues_reporter) in Phoenix applications — error reporting, system monitoring, network scanning, and OpenTelemetry tracing via the GoodIssues API.

## Subcommands

| Subcommand | Purpose |
|------------|---------|
| `bootstrap` | Add GoodIssuesReporter to a Phoenix application |

### `/goodissues-reporter help`

Display a list of all available subcommands. Output the following exactly:

```
/goodissues-reporter subcommands:

  bootstrap   — Add GoodIssuesReporter to a Phoenix app
  help        — Show this help message
```

If `/goodissues-reporter` is invoked without a subcommand, show the help output above.

## Dispatch

1. Parse the subcommand from the user's invocation. Examples:
   - `/goodissues-reporter bootstrap` → subcommand `bootstrap`
   - `/goodissues-reporter help` → show help
2. If the subcommand is unknown, list available subcommands and stop.
3. Follow the matching workflow below.

---

## `/goodissues-reporter bootstrap`

Add GoodIssuesReporter to an existing Phoenix application. Checks what already exists and only adds missing pieces.

### Prerequisites

Verify the project is a Phoenix app:
- `mix.exs` exists
- `lib/` contains an application module with a supervision tree

If not a Phoenix app, inform the user and stop.

### Gather Input

Ask the user which features to enable:

1. **Error reporting** (default: yes) — reports `error_tracker` telemetry events to GoodIssues
2. **System monitor** (default: yes) — polls BEAM/OS metrics and reports threshold breaches
3. **Network scanner** (default: no) — scans for unexpected open TCP ports
4. **OpenTelemetry** (default: no) — auto-instruments Phoenix, LiveView, and Ecto
5. **Health endpoint** (default: yes) — mounts `/gi/health` for readiness checks
6. **Heartbeat monitors** (default: no) — periodic health check pings

### Workflow

#### 1. Add dependency to mix.exs

Add `{:good_issues_reporter, github: "agoodway/goodissues_reporter"}` to the deps list.

If error reporting is enabled and `error_tracker` is not already a dependency, add:
```elixir
{:error_tracker, "~> 0.9"}
```

If OpenTelemetry is enabled, add these dependencies if missing:
```elixir
{:opentelemetry, "~> 1.4"},
{:opentelemetry_exporter, "~> 1.7"},
{:opentelemetry_phoenix, "~> 2.0"},
{:opentelemetry_ecto, "~> 1.2"},
{:opentelemetry_liveview, "~> 1.0"}
```

#### 2. Configure runtime.exs

Add to `config/runtime.exs` (inside the existing `if config_env() == :prod do` block, or create one):

```elixir
config :good_issues_reporter,
  api_url: System.fetch_env!("GOODISSUES_API_URL"),
  api_key: System.fetch_env!("GOODISSUES_API_KEY"),
  project_id: System.fetch_env!("GOODISSUES_PROJECT_ID")
```

If system monitor is enabled, add:
```elixir
config :good_issues_reporter,
  system_monitor: [
    enabled: true,
    poll_interval_ms: 30_000,
    severity: "warning",
    memory_total_mb: 512,
    cpu_percent: 90,
    disk_percent: 85
  ]
```

If network scanner is enabled, add:
```elixir
config :good_issues_reporter,
  network_scanner: [
    enabled: true,
    strategy: :deny,
    ports: [3306, 5432, 6379, 11211, 9200, 27017]
  ]
```

If OpenTelemetry is enabled, add:
```elixir
config :good_issues_reporter,
  otel: [
    enabled: true,
    service_name: "<app_name>",
    phoenix: true,
    liveview: true,
    ecto_repo_prefix: [:<app_name>, :repo]
  ]

config :opentelemetry,
  resource: [{"service.name", "<app_name>"}],
  traces_exporter: {:otlp, [
    protocol: :http_protobuf,
    endpoints: [System.fetch_env!("GOODISSUES_API_URL") <> "/api/v1/otlp/traces"],
    headers: [{"authorization", "Bearer " <> System.fetch_env!("GOODISSUES_API_KEY")}]
  ]}
```

If heartbeat monitors are enabled, add:
```elixir
config :good_issues_reporter,
  heartbeat_monitors: [
    [
      enabled: true,
      name: :system_monitor,
      target: GoodIssuesReporter.SystemMonitor,
      heartbeat_token: System.fetch_env!("GOODISSUES_SYSTEM_MONITOR_PING_TOKEN"),
      check: {:call, :health},
      interval_ms: 60_000,
      timeout_ms: 2_000
    ]
  ]
```

#### 3. Disable in dev and test

Add to `config/dev.exs`:
```elixir
config :good_issues_reporter, enabled: false
```

Add to `config/test.exs`:
```elixir
config :good_issues_reporter, enabled: false
```

#### 4. Add to supervision tree

In `lib/<app_name>/application.ex`, add `{GoodIssuesReporter, []}` to the children list, after the Repo and before the Endpoint:

```elixir
children = [
  <AppName>.Repo,
  {GoodIssuesReporter, []},
  <AppName>Web.Endpoint
]
```

#### 5. Mount health endpoint (if enabled)

In `lib/<app_name>_web/router.ex`, add inside a pipeline or at the top level:

```elixir
forward "/gi", GoodIssuesReporter.HealthRouter
```

Place it before any catch-all routes. Consider mounting behind an internal-only pipeline if the app is public-facing.

#### 6. Update .env.sample / .env

Add environment variable placeholders:

```bash
GOODISSUES_API_URL=https://goodissues.dev
GOODISSUES_API_KEY=
GOODISSUES_PROJECT_ID=
```

If heartbeat monitors are enabled:
```bash
GOODISSUES_SYSTEM_MONITOR_PING_TOKEN=
```

#### 7. Fetch deps and compile

```bash
mix deps.get
mix compile
```

If error_tracker was added and needs a migration:
```bash
mix error_tracker.install
mix ecto.migrate
```

#### 8. Verify

Run:
```bash
mix compile --warnings-as-errors
```

Confirm no warnings related to GoodIssuesReporter configuration.

### Summary

Tell the user what was added:
- Dependency in `mix.exs`
- Runtime config in `config/runtime.exs`
- Disabled in dev/test configs
- Added to supervision tree
- Health endpoint (if enabled)
- Environment variable placeholders
- Which features are enabled and their defaults

Remind the user to:
1. Set the environment variables (`GOODISSUES_API_URL`, `GOODISSUES_API_KEY`, `GOODISSUES_PROJECT_ID`)
2. Create a project on goodissues.dev (or via `/goodissues projects create`) to get the project ID
3. Review system monitor thresholds for their deployment size
4. Mount the health router behind auth if the app is public-facing

---

## Configuration Reference

### Required

| Variable | Description |
|----------|-------------|
| `GOODISSUES_API_URL` | Base URL of GoodIssues instance (e.g., `https://goodissues.dev`) |
| `GOODISSUES_API_KEY` | API key for Bearer token authentication |
| `GOODISSUES_PROJECT_ID` | UUID of the project to report to |

### System Monitor Defaults

| Metric | Default Threshold | Description |
|--------|-------------------|-------------|
| `memory_total_mb` | 512 | Total BEAM memory |
| `memory_processes_mb` | 256 | Process memory |
| `process_count` | 50,000 | Number of processes |
| `atom_count` | 500,000 | Atom table size |
| `cpu_percent` | 90 | OS CPU usage |
| `disk_percent` | 85 | Disk usage |

### Network Scanner Strategies

| Strategy | Behavior |
|----------|----------|
| `:deny` | Alert if any listed port is open (blocklist) |
| `:allow` | Alert if any unlisted port is open (allowlist) |

$ARGUMENTS
