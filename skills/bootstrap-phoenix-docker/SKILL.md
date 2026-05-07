---
name: bootstrap-phoenix-docker
description: Bootstrap Docker releases for Phoenix applications. Use when the user wants to containerize a Phoenix app, add Docker support, create a production Dockerfile, set up release configuration, or deploy Phoenix with Docker. Triggers on "docker", "containerize", "release", "deploy phoenix", "production build", or when setting up CI/CD pipelines for Phoenix.
---

# Phoenix Docker Release Bootstrap

Generate production-ready Docker releases for Phoenix applications.

## Prerequisites

- Existing Phoenix application with Ecto (database)
- Mix installed locally

## Workflow

### 1. Generate Release Files

Run in project root:

```bash
mix phx.gen.release --docker
```

This generates:
- `lib/<app>/release.ex` - Migration and seeding helpers
- `rel/overlays/bin/server` - Server start script
- `rel/overlays/bin/migrate` - Migration runner
- `Dockerfile` - Multi-stage production build
- `.dockerignore` - Build exclusions

### 2. Configure Runtime Environment

Edit `config/runtime.exs` to read from environment variables:

```elixir
import Config

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise "DATABASE_URL not set"

  config :my_app, MyApp.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise "SECRET_KEY_BASE not set"

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :my_app, MyAppWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [ip: {0, 0, 0, 0}, port: port],
    secret_key_base: secret_key_base
end
```

### 3. Build Docker Image

```bash
docker build -t my_app:latest .
```

### 4. Run Container

```bash
# Generate a secret
mix phx.gen.secret

# Run with environment variables
docker run -d \
  -p 4000:4000 \
  -e DATABASE_URL="ecto://user:pass@host/db" \
  -e SECRET_KEY_BASE="generated_secret_here" \
  -e PHX_HOST="localhost" \
  my_app:latest
```

### 5. Run Migrations

Before starting the app or as part of deployment:

```bash
docker run --rm \
  -e DATABASE_URL="ecto://user:pass@host/db" \
  my_app:latest /app/bin/migrate
```

Or from within the container:

```bash
/app/bin/my_app eval "MyApp.Release.migrate"
```

## Common Customizations

### Add Health Check Endpoint

Add to router for container orchestration:

```elixir
get "/health", HealthController, :index
```

Simple controller:

```elixir
defmodule MyAppWeb.HealthController do
  use MyAppWeb, :controller

  def index(conn, _params) do
    json(conn, %{status: "ok"})
  end
end
```

### Configure DNS Clustering

For multi-node deployments, edit `rel/env.sh.eex`:

```bash
export RELEASE_DISTRIBUTION=name
export RELEASE_NODE=<%= @release.name %>@${HOSTNAME}
```

And configure in `runtime.exs`:

```elixir
if dns_query = System.get_env("DNS_CLUSTER_QUERY") do
  config :my_app, :dns_cluster_query, dns_query
end
```

### Custom Release Commands

Add to `lib/<app>/release.ex`:

```elixir
def seed do
  load_app()
  for repo <- repos() do
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, fn repo ->
      Code.eval_file(Path.join([:code.priv_dir(:my_app), "repo", "seeds.exs"]))
    end)
  end
end
```

## Environment Variables Reference

| Variable | Required | Description |
|----------|----------|-------------|
| `DATABASE_URL` | Yes | PostgreSQL connection string |
| `SECRET_KEY_BASE` | Yes | 64+ char secret (use `mix phx.gen.secret`) |
| `PHX_HOST` | No | Production hostname |
| `PORT` | No | HTTP port (default: 4000) |
| `POOL_SIZE` | No | DB pool size (default: 10) |
| `DNS_CLUSTER_QUERY` | No | DNS query for clustering |

## Reference Files

- **Dockerfile Template**: See `references/dockerfile.md` for customizing the Dockerfile
