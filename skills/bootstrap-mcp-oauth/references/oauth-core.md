# Config, migrations, Oauth, TokenResource, Consent, Provisioning

Replace `MyApp` / `my_app` with the detected names.

## Config

`config/config.exs`:

```elixir
config :my_app, :oauth,
  issuer: "http://localhost:4000",
  redirect_uri: "http://127.0.0.1/callback",
  client_id: "11111111-1111-4111-8111-111111111111",
  provision_local_client: false,
  scopes: ["mcp:read", "mcp:write", "mcp:admin"],
  dcr_body_limit: 16_384,
  dcr_max_client_name_length: 128,
  dcr_max_redirects: 8,
  dcr_max_redirect_uri_length: 512,
  dcr_ip_limit: 10,
  dcr_global_limit: 100,
  dcr_window_seconds: 3_600,
  introspection_timeout_ms: 2_000,
  dcr_redirect_allowlist: [
    "https://claude.ai/api/mcp/auth_callback",
    "https://chatgpt.com/connector_platform_oauth_redirect",
    "https://chatgpt.com/oauth/callback",
    "https://chat.openai.com/oauth/callback",
    "https://vscode.dev/redirect",
    "https://insiders.vscode.dev/redirect",
    "https://antigravity.google/oauth-callback",
    "https://grok.com/connectors-oauth-exchange-code/",
    "cursor://anysphere.cursor-mcp/oauth/callback",
    "https://www.cursor.com/agents/mcp/oauth/callback"
  ]

config :boruta, Boruta.Oauth,
  repo: MyApp.Repo,
  issuer: "http://localhost:4000",
  contexts: [
    resource_owners: MyApp.Oauth.ResourceOwners
  ]
```

If `/boruta bootstrap` already set `MyApp.ResourceOwners`, keep that module
path in `contexts` instead of moving it.

`config/dev.exs`: `provision_local_client: true`.
`config/runtime.exs`: set `issuer` to the public HTTPS URL in prod.
`config/test.exs`: `issuer: "http://localhost:4002"` (or `Endpoint.url()`),
`provision_local_client: true`.

Do not accept `mcp:tools` as a production scope.

## Migration

Greenfield: add `resource` as nullable. Application code writes it on every
new code/token/consent and rejects unbound credentials. Do not delete
in-flight rows in the schema migration.

```elixir
defmodule MyApp.Repo.Migrations.CreateMcpOauthBinding do
  use Ecto.Migration

  def change do
    alter table(:oauth_tokens) do
      add :resource, :text
    end

    create table(:oauth_consents, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :client_id, :string, null: false
      add :resource, :text, null: false
      add :scopes, {:array, :string}, null: false, default: []
      add :identity_basis, :string, null: false, default: "preregistered"

      timestamps(type: :utc_datetime)
    end

    create unique_index(:oauth_consents, [:user_id, :client_id, :resource])

    create table(:oauth_rate_limits, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :bucket, :string, null: false
      add :window_started_at, :utc_datetime, null: false
      add :count, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create unique_index(:oauth_rate_limits, [:bucket, :window_started_at])
  end
end
```

If `oauth_consents` already exists without `resource`, add the column and
replace the unique index. Leave existing rows; reject unbound credentials
in application code. Operator revoke/backfill is a later release task.

## TokenResource

`lib/my_app/oauth/token_resource.ex` — local read/write of
`oauth_tokens.resource` without forking Boruta. Copy the goodviews module
shape: schema on `oauth_tokens` with `value`, `refresh_token`, `resource`;
`get_by_value/1`, `matches_value?/2`, `matches_refresh?/2`, `stamp_value/2`,
`delete_by_value/1`. `stamp_value` must only write when the row is unbound or
already equal to `resource`.

## Consent

`lib/my_app/oauth/consent.ex` — remembered grants per user + client + exact
resource. `granted?/4` is true when stored scopes are a superset of the
request. `grant!/4` upserts on `[:user_id, :client_id, :resource]` and
filters scopes through `Oauth.scopes()`.

Authorize must **not** call `granted?` unless `Oauth.unique_identity?/1` is
true for that client. Shared loopback identity always shows consent.

## Oauth module

`lib/my_app/oauth.ex` owns URLs and DCR. Required functions:

- `issuer/0`, `https_issuer?/0`
- `account_mcp_url/1` → `issuer <> "/accounts/" <> slug <> "/mcp"`
- `protected_resource_metadata_url/1` → RFC 9728 path-inserted URL
- `protected_resource_metadata/1` → `resource`, `authorization_servers`,
  `scopes_supported`, `bearer_methods_supported: ["header"]`
- `authorization_server_metadata/0` → RFC 8414 (authorize, token, register,
  introspect, revoke, S256, the three MCP scopes)
- `valid_resource?/1` / `fetch_account_resource/1` — exact URL of an
  **active** account
- `parse_scope/1` — absent/empty → all configured scopes; any unknown member
  → `{:error, :invalid_scope}` (do not drop unknowns and keep the rest)
- `canonicalize_scope/1` — assign `:oauth_invalid_scope` on error
- `canonicalize_redirect_uri/1` — RFC 8252 loopback match: scheme, host,
  path, query, fragment must match; **port** is the only ignored component
- `restore_redirect_url/2` after authorize
- `register_dynamic_client/1` — public PKCE client; every redirect must be
  loopback HTTP or an **exact** allowlist entry; no `*`, no prefix match
- `client_registration_response/1` — RFC 7591, `token_endpoint_auth_method: "none"`
- `unique_identity?/1` — true for `:preregistered`, `:cimd`, `:dcr`; false
  for the shared seeded loopback client
- `authorize_param_keys/0` — persist these on the consent session:
  `response_type client_id redirect_uri state scope code_challenge code_challenge_method nonce resource`

Client resolution order (implement 1 and 3; 2 is optional):

1. Operator pre-registration
2. Client ID Metadata Documents (HTTPS `client_id` URL) — skip unless the
   app already needs CIMD
3. Dynamic Client Registration

Look up clients by UUID **or** stored HTTPS identifier, not UUID-only.

## DCR bounds

`MyApp.Oauth.Registration.register/2`:

- `Content-Type: application/json`
- body ≤ `dcr_body_limit` (use `assigns[:raw_body]`)
- max client name length, redirect count, per-URI length
- loopback HTTP (no fragment/userinfo) or exact vendor allowlist
- PostgreSQL fixed-window limiter: HMAC of client IP (do not store raw IPs)
  plus a global bucket
- optional hashed initial-access-token for restricted deployments

## Provisioning

`lib/my_app/oauth/provisioning.ex` — idempotent. Used by releases and tests.

- insert configured MCP scopes if missing
- insert confidential introspection client when
  `OAUTH_INTROSPECTION_CLIENT_ID` / `SECRET` are set (required for HTTPS)
- insert the seeded public loopback client **only** when
  `provision_local_client: true`
- never overwrite an existing operator-managed client

`MyApp.Release.provision_oauth/0` calls `Provisioning.provision/0`. Tests
call it from `MCPCase` / test helper.

Do **not** call this from `Application.start/2`. Startup may validate
config and fail with an actionable message.

## Rate limits

`lib/my_app/oauth/rate_limit.ex` — atomic upsert on
`(bucket, window_started_at)`, HMAC-SHA256 of `conn.remote_ip` with a
runtime pepper. Reject when count exceeds `dcr_ip_limit` /
`dcr_global_limit`.
