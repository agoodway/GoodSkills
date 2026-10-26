# Providers

A provider row holds the OAuth endpoints, client ID, encrypted client secret, and default scopes. Provider configs come from the [Nango catalog](https://docs.nango.dev/integrations/overview) (`providers.yaml`) or are written by hand. The provider `slug` is the name used everywhere else (`create_session("github", ...)`). `mix tango.providers.create <name>` and `create_provider_from_nango(name, ...)` store `name` as the slug, so the catalog alias `google-calendar` becomes slug `"google-calendar"`. `sync --only` matches the same catalog keys.

## Mix tasks

All tasks fetch the catalog over HTTP. `create` and `sync` also write to the configured host repo; `show` does not.

```bash
# Inspect a catalog entry (auth mode, URLs, scopes, docs)
mix tango.providers.show github

# OAuth2 provider with catalog defaults
mix tango.providers.create github --client-id=xxx --client-secret=yyy

# Repeatable --scope
mix tango.providers.create microsoft \
  --client-id="$AZURE_CLIENT_ID" \
  --client-secret="$AZURE_CLIENT_SECRET" \
  --scope="Calendars.Read" \
  --scope="User.Read" \
  --scope="offline_access"

# Comma-separated --scopes
mix tango.providers.create google \
  --client-id="$GOOGLE_CLIENT_ID" \
  --client-secret="$GOOGLE_CLIENT_SECRET" \
  --scopes="https://www.googleapis.com/auth/calendar,https://www.googleapis.com/auth/userinfo.email"

# Compare catalog vs. local providers (report only, writes nothing)
mix tango.providers.sync --only github,slack

# Refresh endpoints / metadata on already-configured providers
mix tango.providers.sync --force --only github             # merge auth_url, token_url, auth_mode
mix tango.providers.sync --update-metadata --only github   # update name + merge metadata
mix tango.providers.sync --force --dry-run                 # -n: preview the writes
```

Use `mix tango.providers.create` (or `create_provider_from_nango/3`) to add a provider. `mix tango.providers.sync` never creates rows. It matches existing providers (active or inactive) by `slug` and lists unconfigured catalog entries with a hint to run `create`. Without `--force` or `--update-metadata` it writes nothing. `--force` merges only `auth_url`, `token_url`, and `auth_mode` into the existing `config`, skipping catalog values that are missing or templated (any `${...}` placeholder, including every `a || b` template, even ones `create` resolved to the fallback, so sync never overwrites a Salesforce or Zendesk URL), and never touches `client_id`, custom config keys, `client_secret`, `default_scopes`, or `active`. Sync never reactivates an inactive provider. `--update-metadata` merges the catalog's request options over local metadata, catalog winning even when its value is `nil`, so it erases a hand-set `authorization_method` or `token_response_metadata` the catalog lacks; reapply those with `Tango.update_provider/2`.

Pass secrets through environment variables, not literal values that land in shell history or committed scripts.

## Programmatic creation

Use this from seeds, release tasks, or an admin UI. All return `{:ok, %Tango.Schemas.Provider{}}` or `{:error, changeset_or_reason}`.

From the catalog:

```elixir
{:ok, nango_config} = Tango.Catalog.get_provider("github")

{:ok, provider} =
  Tango.create_provider_from_nango("github", nango_config,
    client_id: System.fetch_env!("GITHUB_CLIENT_ID"),
    client_secret: System.fetch_env!("GITHUB_CLIENT_SECRET"),
    default_scopes: ["user:email", "repo"]
  )
```

`create_provider_from_nango/3` maps the catalog's `authorization_url` to `config["auth_url"]` and copies `authorization_params` into `metadata["auth_params"]`. Supported catalog entries (see `deps/tango/docs/PROVIDERS.md`, "Supported catalog entries"):

- Only `auth_mode: OAUTH2` (authorization code) providers. Any other mode (`OAUTH2_CC`, `MCP_OAUTH2`, `OAUTH1`, `APP`, `API_KEY`, ...) fails the changeset with "auth_mode X is not supported".
- `Tango.Catalog` resolves Nango `alias:` entries the way Nango does, as a shallow merge over the parent. So `google-calendar`, `google-mail`, `outlook` and `microsoft-teams` work as catalog names.
- `a || b` URL templates resolve to `b`, the fallback Nango uses when there is no connection config (e.g. Salesforce becomes `login.salesforce.com`). Any URL or `auth_params`/`token_params`/`refresh_params` that still contains `${connectionConfig.*}` fails with "requires connection configuration, which Tango does not support". Pass explicit URLs instead: `--auth-url/--token-url` on `mix tango.providers.create`, or the `auth_url:`/`token_url:` opts to `create_provider_from_nango/3` (e.g. Zendesk: `mix tango.providers.create zendesk --client-id=... --client-secret=... --auth-url=https://acme.zendesk.com/oauth/authorizations/new --token-url=https://acme.zendesk.com/oauth/tokens`). Params that need connection config have no override.
- Honored per-provider options, stored in metadata (catalog import copies them; they also work on hand-written providers): `scope_separator` (joins scopes in the authorization URL, default `" "`), `disable_pkce` (no `code_challenge` or `code_verifier`), `token_request_auth_method: basic` (credentials in the Basic header and the body), `authorization_method: header` (credentials only in the Basic header), `authorization_method: body` (see below), `body_format: json`, `token_params` (exchange), `refresh_params` (refresh, falling back to `token_params`), and `token_response_metadata` (see below). Catalog `grant_type` values are never sent. Unlisted options (`refresh_url`, `authorization_url_replacements`, `alternate_access_token_response_path`, ...) are ignored.
- Tango's default token request sends HTTP Basic auth plus `client_id` in the form body. Nango's default sends both credentials in the body. For a provider that rejects Basic auth, set `authorization_method: body` explicitly.

### Body client authentication

```elixir
metadata: %{"authorization_method" => "body"}
```

Sends `client_id` and `client_secret` in the POST body with no `Authorization` header, on code exchange and refresh, as a form or as JSON with `body_format: json`. Adding `"token_request_auth_method" => "basic"` keeps the Basic header too. The changeset rejects any `authorization_method` other than `nil`, `"header"`, or `"body"`. Code exchanges are never retried.

### Token-response metadata

Some providers return account details beside the token (Salesforce `instance_url`, Slack `team.id`). List the fields to keep:

```elixir
metadata: %{"token_response_metadata" => ["instance_url", "team.id"]}
```

- Applies to the popup (staged) flow only. The listed fields are stored on the candidate as `provider_data`, keyed by the configured name (dotted paths read nested objects and stay dotted: `%{"team.id" => "T012AB3C4"}`), and handed to the verifier ([authorization.md](authorization.md)). `exchange_code/4` does not retain them.
- Only string, number, and boolean values are kept; absent, `null`, and nested values are skipped silently, so `provider_data` may be `%{}`.
- Names matching `Tango.Validation.sensitive_key?/1` (`id_token`, anything containing `token`, `secret`, `password`, `signature`, `assertion`, `jwt`, `nonce`, ...) are skipped even when listed. `access_token`, `refresh_token`, `expires_in`, and `token_type` can never be retained.
- More than 4 KiB of encoded JSON fails the exchange with `:invalid_grant_metadata` (callback `oauth_error` `"invalid_grant_metadata"`).
- The changeset requires `nil` or a list of non-blank strings.
- `provider_data` is reset to `%{}` when the candidate is consumed or cleaned up and is never copied to the connection. Persist anything needed later from the verifier's claims or host records.

Providers imported before this option was copied need `mix tango.providers.sync --update-metadata --only <slug>` to pick it up ([upgrading.md](upgrading.md)).

Do not pass a raw catalog map to `create_provider/1`: catalog entries have no `auth_url`, so OAuth2 configs fail validation.

Custom OAuth2 provider (no catalog). OAuth2 configs must contain string `client_id`, `auth_url`, and `token_url`:

```elixir
{:ok, provider} =
  Tango.create_provider(%{
    name: "Custom API",
    slug: "custom_api",
    client_secret: System.fetch_env!("CUSTOM_CLIENT_SECRET"),
    config: %{
      "client_id" => System.fetch_env!("CUSTOM_CLIENT_ID"),
      "auth_url" => "https://api.example.com/oauth/authorize",
      "token_url" => "https://api.example.com/oauth/token",
      "auth_mode" => "OAUTH2"
    },
    default_scopes: ["read", "write"],
    active: true
  })
```

API-key providers are not supported: every session/connection function is OAuth2-only. `mix tango.providers.create <name> --api-key=...` prints "API key providers are not supported", writes nothing, and fetches nothing. The provider changeset returns `{:error, changeset}` for an `api_key` attribute, an `api_key:` option to `create_provider_from_nango/3`, or an `"api_key"` key inside `config`, so a key is never stored in plaintext. Store non-OAuth API keys in the host app, encrypted.

## Read, update, deactivate

```elixir
providers = Tango.list_providers()                 # active only
{:ok, provider} = Tango.get_provider("github")     # by slug
{:ok, provider} = Tango.get_provider_by_id(id)
{:ok, provider} = Tango.update_provider(provider, %{default_scopes: ["repo"]})
{:ok, provider} = Tango.delete_provider(provider)  # soft delete: active: false
```

`get_provider/1` only matches active providers (`{:error, :not_found}` otherwise, which session creation reports as `:provider_not_found`). To retire a provider, run `Tango.Connection.revoke_provider_connections("slug")` before `delete_provider/1`; once the provider is inactive that function can no longer find it.

Changing a provider's OAuth client ID mid-flight makes pending completions fail with `:client_changed`; users must re-authorize.

## Provider checklist

- Register the exact redirect URI with the provider. For popup completion that is the mounted Tango `/callback` URL (for example `https://app.example.com/api/oauth/callback`).
- Pick scopes the integration actually calls. Protocol hints such as `offline_access` may be requested but are often omitted from granted scopes; do not list them in `required_scopes` at finalize.
- Catalog `auth_params` in provider metadata are merged into the authorization URL; per-session `auth_params` override them. Providers that issue refresh tokens only on request (Google: `%{"access_type" => "offline", "prompt" => "consent"}`) need those params per session or in `metadata["auth_params"]`; otherwise finalize with `require_refresh_token: true` fails `:refresh_token_required`.
