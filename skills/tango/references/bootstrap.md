# Bootstrap Tango

Add Tango to an existing Phoenix application. Check what is already installed first; if `deps/tango` exists, use its version and `deps/tango/docs/` rather than assuming a release.

## Prerequisites

- Elixir 1.15+, PostgreSQL, and an Ecto SQL repo started in the host supervision tree.
- Tango's application starts its own supervisor (with `Tango.Vault`); do not add Tango children to the host tree.

## Install

Add the requested released, git, or path dependency. Verify Hex availability before choosing 0.3.0; a local 0.3.0 checkout may be unpublished. The example below is for a verified published 0.3.0. For provisional local adoption, follow [upgrading.md](upgrading.md) and preserve the requested source.

```elixir
def deps do
  [
    {:tango, "~> 0.3.0"}
  ]
end
```

```bash
mix deps.get
```

## Configure

```elixir
# config/config.exs
config :tango,
  repo: MyApp.Repo
```

```elixir
# config/runtime.exs
config :tango,
  encryption_key: System.fetch_env!("TANGO_ENCRYPTION_KEY"),
  api_key: System.get_env("TANGO_API_KEY"),
  allowed_completion_origins: ["https://app.example.com"]
```

Generate the encryption key and keep it in the secret store, never in the repo:

```bash
openssl rand -base64 32
```

| Key                          | Purpose                                                                                                       |
|------------------------------|---------------------------------------------------------------------------------------------------------------|
| `repo`                       | Host Ecto repo. Required. Finalization must run on this repo.                                                 |
| `encryption_key`             | 32 raw bytes or base64 of 32 bytes. `Tango.Vault` raises `ArgumentError` on any other size.                   |
| `api_key`                    | Bearer/`X-API-Key` secret for `Tango.API.Router`. Only needed when mounting the router.                       |
| `allowed_completion_origins` | Exact page origins allowed to receive popup completion (0.2.0+). See [authorization.md](authorization.md).    |
| `schema_prefix`              | Postgres schema for Tango tables (default `"public"`). Read with `compile_env`; see note below.                |
| `session_timeout`            | Session lifetime in seconds and the upper bound for an explicit `:expires_at` (default `1800`).               |
| `refresh_batch_size`         | Batch size for `Tango.refresh_expiring_connections/0` (default `100`).                                        |
| `nango_providers_url`        | Override the Nango `providers.yaml` URL used by the catalog mix tasks.                                        |
| `:api` keyword               | CORS for the router: `cors_origins`, `cors_methods`, `cors_headers`, `cors_max_age`, `cors_credentials`.      |

`Tango.Migration` and the Ecto schemas read `schema_prefix` at compile time. Set it in `config/config.exs` before the first compile, or run `mix deps.compile tango --force` after changing it.

Rotating `encryption_key` makes existing encrypted tokens unreadable. Treat it as a re-authorization event, not a config tweak.

## Install the schema

```bash
mix tango.setup                  # or: mix tango.setup --repo MyApp.OtherRepo
mix ecto.migrate
```

`mix tango.setup` writes `<repo priv>/migrations/<timestamp>_install_tango.exs`:

```elixir
defmodule MyApp.Repo.Migrations.InstallTango do
  use Ecto.Migration

  def up, do: Tango.Migration.up()
  def down, do: Tango.Migration.down()
end
```

`up/0` installs through the latest bundled version (V03 in both 0.2.0 and 0.3.0). `down/0` targets version 0 and drops every Tango table. Run setup once per database; for later versions follow [upgrading.md](upgrading.md).

Without Ecto migrations, copy `deps/tango/priv/repo/sql/versions/<version>/` into the host migration tool, replace `$SCHEMA$` with the prefix, and stamp the version marker:

```sql
COMMENT ON TABLE "public".tango_providers IS 'Tango version=3';
```

## Verify

```sql
SELECT obj_description('public.tango_providers'::regclass);
-- Tango version=3
```

Then add a provider ([providers.md](providers.md)) and run one flow end to end ([direct-flow.md](direct-flow.md) or [authorization.md](authorization.md)). Schedule cleanup now so it is not forgotten:

```elixir
{:ok, _} = Tango.cleanup_expired_authorizations()
{:ok, _} = Tango.cleanup_expired_sessions()
```
