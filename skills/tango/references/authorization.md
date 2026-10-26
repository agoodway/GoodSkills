# Authorization completion (0.2.0+)

Popup flow where the browser never sees a credential. Ordinary connection completion requires Tango 0.2.0+ and defaults to `completion_mode: :connection`. For one-time account links or organization administrator proofs without a durable connection, use server-selected `completion_mode: :consume` and `Tango.Authorization.multi_consume_authorization/5` ([consumption.md](consumption.md)); this requires verified 0.4.1 source and revised V04. Confirm installed APIs and schema before use ([upgrading.md](upgrading.md)).

## Contents

- [Flow](#flow)
- [1. Configure exact origins](#1-configure-exact-origins)
- [2. Start the session on the server](#2-start-the-session-on-the-server)
- [3. Callback and browser forwarding](#3-callback-and-browser-forwarding)
- [4. Write a verifier](#4-write-a-verifier)
- [5. Verify and finalize](#5-verify-and-finalize)
- [Reauthorizing an existing connection](#reauthorizing-an-existing-connection)
- [Errors](#errors)
- [Cleanup](#cleanup)
- [Token retention](#token-retention)

## Flow

```
1. Server: Tango.create_authorization_session/3 binds provider, scopes, redirect URI,
   completion origin, and intent reference; Tango.Auth.authorization_url/1 builds the URL
2. Browser opens the URL in a popup; provider redirects to Tango's GET /callback
3. /callback exchanges the code and stores an encrypted candidate plus any configured token-response metadata (10-minute lifetime, capped by session expiry)
4. /callback posts { type, completion_handle, intent_reference } to the completion origin
5. Browser forwards the handle to an authenticated host endpoint
6. Server: Tango.verify_authorization/4 (HTTP to provider, outside any transaction)
7. Server: Tango.multi_finalize_authorization/5 inside the host Ecto.Multi for a connection
   OR Tango.Authorization.multi_consume_authorization/5 for a consume-mode proof
```

The `redirect_uri` must be registered with the provider and routed to the mounted `Tango.API.Router` `/callback` ([api.md](api.md)). For connection completion, the LiveView component performs steps 1, 2, and 5 for you ([liveview.md](liveview.md)); steps 6-7 are always host code.

## 1. Configure exact origins

```elixir
# config/runtime.exs
config :tango,
  allowed_completion_origins: [System.fetch_env!("APP_ORIGIN")]
```

- Origin format is `scheme://host[:port]`: no path, query, fragment, user info, trailing slash, or wildcard.
- `https` is required; `http` is accepted only for `localhost` and loopback.
- `completion_origin` is the origin of the page hosting the button. `Tango.Validation.origin/1` derives the exact `scheme://host[:port]` string from a URL (`nil` if unparsable). It may differ from the origin serving `/callback`.
- A session whose `completion_origin` is not listed fails with `{:error, :invalid_completion_origin}`.

In tests, set the env with `Application.put_env/3` and restore the previous value in `on_exit`.

## 2. Start the session on the server

```elixir
intent_reference = :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)

{:ok, session} =
  Tango.create_authorization_session("example", tenant_id,
    scopes: ["accounts.read", "records.write"],
    redirect_uri: "https://app.example.com/api/oauth/callback",
    completion_origin: "https://app.example.com",
    intent_reference: intent_reference,
    auth_params: %{"prompt" => "consent"}
  )

{:ok, url} = Tango.Auth.authorization_url(session)
```

`Tango.Auth.authorization_url/1` is not delegated from `Tango`; call it on `Tango.Auth`.

| Option                                         | Notes                                                                                                                                                                                                                                                                                             |
| ---------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `:redirect_uri`                                | Required. Tango `/callback` URL registered with the provider.                                                                                                                                                                                                                                     |
| `:completion_origin`                           | Required. Must be in `allowed_completion_origins`.                                                                                                                                                                                                                                                |
| `:intent_reference`                            | Required. Opaque string, 1-255 bytes. Ties the completion to the action that started it. Keep it in server state.                                                                                                                                                                                 |
| `:scopes`                                      | Defaults to provider `default_scopes`. Bound and authoritative.                                                                                                                                                                                                                                   |
| `:auth_params`                                 | Extra provider params. Map of string (or atom) keys to string/number/boolean values. Reserved keys (`state`, `redirect_uri`, `client_id`, `response_type`, `scope`, `code_challenge`, `code_challenge_method`) return `:reserved_auth_parameter`; other bad shapes return `:invalid_auth_params`. |
| `:expires_at`                                  | Optional `DateTime` in the future, no later than `session_timeout` seconds from now.                                                                                                                                                                                                              |
| `:completion_mode`                             | Defaults to `:connection`. Optional `:consume` in 0.4.1 selects a one-time proof; see [consumption.md](consumption.md).                                                                                                                                                                           |
| `:expected_connection_id`, `:expected_subject` | Connection reauthorization binding. In consume mode, only an independent optional subject is supported. See below.                                                                                                                                                                                |

Session-start errors: `:provider_not_found`, `:invalid_provider_slug`, `:invalid_tenant_id`, `:invalid_redirect_uri` / `:insecure_redirect_uri`, `:invalid_scopes`, `:invalid_completion_origin`, `:invalid_intent_reference`, `:invalid_expiration`, `:reserved_auth_parameter`, `:invalid_auth_params`, `:stale_connection` (expected connection missing, another tenant's, revoked, or already replaced; or, in connection mode, `:expected_subject` without `:expected_connection_id`), and `:account_mismatch` (`:expected_subject` differs from the connection's stored subject).

## 3. Callback and browser forwarding

The callback posts exactly one of:

```javascript
{ type: "oauth_complete", completion_handle: "...", intent_reference: "..." }
{ type: "oauth_error", error: "access_denied", intent_reference: "..." }
```

With the LiveView component, the `TangoOAuth` hook validates and forwards this. Without LiveView, accept the message only from the popup you opened and the exact callback origin, then POST to an authenticated, CSRF-protected host endpoint:

```javascript
window.addEventListener("message", async (event) => {
  if (event.source !== popup) return;
  if (event.origin !== CALLBACK_ORIGIN) return;

  const data = event.data;
  if (!data || data.intent_reference !== pendingIntent) return;

  if (data.type === "oauth_complete" && typeof data.completion_handle === "string") {
    await fetch("/integrations/complete", {
      method: "POST",
      credentials: "same-origin",
      headers: { "Content-Type": "application/json", "X-CSRF-Token": csrfToken },
      body: JSON.stringify({
        completion_handle: data.completion_handle,
        intent_reference: data.intent_reference
      })
    });
  }
});
```

Reject any message containing `access_token` or other credential fields; that is a 0.1.x payload and must connect nothing.

## 4. Write a verifier

A verifier proves which provider account the candidate token belongs to. It runs on the server with the candidate's ephemeral access token.

```elixir
defmodule MyApp.Integrations.ExampleVerifier do
  @behaviour Tango.AuthorizationVerifier

  @impl true
  def verify(_provider, %{access_token: access_token, provider_data: _provider_data}, opts) do
    case MyApp.ExampleClient.fetch_account(access_token) do
      {:ok, %{"id" => id, "display_name" => display_name}} ->
        {:ok,
         %{
           subject: to_string(id),
           claims: %{"display_name" => display_name},
           continuity: continuity(opts)
         }}

      {:error, {:http_status, status}} when status >= 500 ->
        {:error, :provider_unavailable}

      {:error, {:http_status, 429}} ->
        {:error, :temporarily_unavailable}

      {:error, :timeout} ->
        {:error, :timeout}

      {:error, :transport} ->
        {:error, :network_error}

      _ ->
        {:error, :invalid_identity}
    end
  end

  defp continuity(opts) do
    case Keyword.get(opts, :connection_id) do
      nil -> :initial
      connection_id -> {:connection, connection_id}
    end
  end
end
```

- Callback: `verify(Tango.Schemas.Provider.t(), %{access_token:, granted_scopes:, provider_data:}, keyword()) :: {:ok, %{subject:, claims:, continuity:}} | {:error, atom()}`.
- `subject` is the provider's stable account ID as a string. `continuity` is `:initial` or `{:connection, id}`; Tango sets `opts[:connection_id]` when the session expects an existing connection.
- `provider_data` (0.4.0+) holds the scalar token-response fields the provider's `token_response_metadata` lists, for example `%{"instance_url" => "https://acme.my.salesforce.com"}` for the identity call or Slack `"team.id"` to check the expected workspace. It is `%{}` when none are configured or present ([providers.md](providers.md#token-response-metadata)). Allowlist only reviewed non-secret identity fields: these are plain metadata, and a safe-looking key can still contain a secret. It exists only while the candidate is staged: `verify_connection_identity/3` passes `provider_data: %{}`, so a verifier shared with identity rechecks must handle the empty map.
- Only `:network_error`, `:timeout`, `:temporarily_unavailable`, and `:provider_unavailable` leave the handle usable for a retry (map 5xx, 429, timeouts, and transport errors to them as above; adapt the `{:error, ...}` shapes to your client). Any other verifier error, a malformed result (`:invalid_claims`), or a subject/continuity mismatch (`:account_mismatch`) consumes the handle.
- `claims` must be JSON-compatible, at most 4 KiB encoded, with no token-like keys (`access_token`, `authorization`, `cookie`, `client_secret`, ...) at any depth. Return only display-safe identity fields.
- Never store, log, or return the access token.

## 5. Verify and finalize

Run this from the authenticated request that received the handle. Verification makes HTTP calls, so it runs before the transaction opens.

```elixir
defmodule MyApp.Integrations do
  alias MyApp.Integrations.ExampleVerifier

  def complete(handle, intent_reference, tenant_id, expected_connection_id \\ nil) do
    with {:ok, identity} <-
           Tango.verify_authorization(handle, tenant_id, {ExampleVerifier, []},
             intent_reference: intent_reference,
             provider: "example"
           ) do
      Ecto.Multi.new()
      |> Tango.multi_finalize_authorization(:authorization, handle, tenant_id,
        required_scopes: ["accounts.read", "records.write"],
        require_refresh_token: true,
        intent_reference: intent_reference,
        provider: "example",
        expected_connection_id: expected_connection_id
      )
      |> Ecto.Multi.insert(:link, fn %{authorization: %{connection: connection}} ->
        MyApp.AccountLink.changeset(%MyApp.AccountLink{}, %{
          tenant_id: tenant_id,
          tango_connection_id: connection.id,
          subject: identity.subject
        })
      end)
      |> MyApp.Repo.transaction()
      |> case do
        {:ok, %{authorization: %{connection: connection}, link: link}} -> {:ok, connection, link}
        {:error, _step, reason, _changes} -> {:error, reason}
      end
    end
  end
end
```

Controller endpoint for the non-LiveView path:

```elixir
def complete(conn, %{"completion_handle" => handle, "intent_reference" => intent})
    when is_binary(handle) and is_binary(intent) do
  tenant_id = current_tenant_id(conn)

  case MyApp.Integrations.complete(handle, intent, tenant_id) do
    {:ok, connection, _link} -> json(conn, %{status: "connected", connection_id: connection.id})
    {:error, reason} when is_atom(reason) -> conn |> put_status(422) |> json(%{error: reason})
    {:error, _reason} -> conn |> put_status(422) |> json(%{error: "oauth_failed"})
  end
end
```

Also check that `intent` matches the intent reference the server stored when it started the flow.

The verifier argument is `{module, opts}`. Tango sets `opts[:connection_id]` from the session's `expected_connection_id` (and removes it for an initial authorization), so do not pass it yourself.

`verify_authorization/4` requires `:intent_reference` and `:provider` (missing or empty values return `:invalid_completion`) and returns `{:ok, %{provider, subject, claims, granted_scopes, expected_connection_id, intent_reference, has_refresh_token}}`.

`multi_finalize_authorization/5` options: `:intent_reference`, `:provider` (must match the session), `:expected_connection_id` (must match the session's binding), `:required_scopes` (API scopes the consumer needs; omit protocol hints such as `offline_access` that providers drop from granted scopes), `:require_refresh_token` (default `false`). The step result is `%{connection: %Tango.Schemas.Connection{}, authorization: summary}`.

Finalize must use the Repo from `config :tango, repo:`. Do not call provider APIs inside the Multi.

## Reauthorizing an existing connection

Connection completion allows one active connection per provider per tenant through this flow. Consume mode neither blocks on nor replaces existing credential connections. An initial authorization (no `expected_connection_id`) fails with `:stale_connection` when the tenant already has an active connection for that provider. To reconnect, either reauthorize the existing connection as below or revoke it first.

Bind the session to the connection and its known subject:

```elixir
Tango.create_authorization_session("example", tenant_id,
  redirect_uri: callback_url,
  completion_origin: origin,
  intent_reference: intent_reference,
  expected_connection_id: connection.id,
  expected_subject: connection.account_subject
)
```

Then pass the same `expected_connection_id` to finalize. The verifier must return `continuity: {:connection, expected_connection_id}` (Tango supplies the ID in `opts[:connection_id]`) and the same subject; a wrong continuity or a different subject fails verification with `:account_mismatch`. Finalize fails with `:stale_connection` when the `expected_connection_id` option differs from the session's or another active connection replaced it.

The expected connection may be `:active` or `:expired` (for example, expired by `record_auth_failure/3`); finalize inserts a new connection row and marks the old one `:revoked`, so update host rows to the new `connection.id`.

Refresh-token handling when the provider issues no new refresh token: the existing one is carried forward when the OAuth client ID and subject match and the new granted scopes are a subset of the old ones. A different client ID (both recorded and unequal) fails `:client_changed`, and a different subject fails `:account_mismatch`; scopes outside the old set drop it (or fail with `:refresh_token_required` when `require_refresh_token: true`). A connection with no recorded `oauth_client_id` or `account_subject` (created before V03, or via `exchange_code/4`) cannot prove continuity: finalize drops the old refresh token instead of failing, so the new connection has no refresh token unless the provider issued one. With `require_refresh_token: true`: if the old connection has no refresh token either, finalize fails `:refresh_token_required`; if it has one, finalize fails `:client_changed` (no recorded client) or `:account_mismatch` (no recorded subject). `Tango.verify_connection_identity/3` records only `account_subject`, never `oauth_client_id`, so it cannot make such a connection eligible to keep its refresh token.

To recheck or bind an active connection's identity outside a flow, use `Tango.verify_connection_identity/3` ([connections.md](connections.md)).

## Errors

All errors are atoms or `{:oauth_error, category}`; no exception or raw provider body is returned.

| Error                                                                                                   | Meaning                                                                                                                                                                                                                                     |
| ------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `:invalid_completion`                                                                                   | Unknown, malformed, cross-tenant, or wrong-provider handle; missing `:intent_reference`/`:provider` option                                                                                                                                  |
| `:completion_consumed`                                                                                  | Handle already used (handles work once)                                                                                                                                                                                                     |
| `:expired_completion`                                                                                   | Candidate older than ten minutes                                                                                                                                                                                                            |
| `:verification_required`                                                                                | Finalize called before a successful `verify_authorization/4` for this handle                                                                                                                                                                |
| `:intent_mismatch`                                                                                      | Intent reference differs from the session's                                                                                                                                                                                                 |
| `:account_mismatch`                                                                                     | Verifier subject differs from `expected_subject` / the connection's subject, or verifier continuity is wrong                                                                                                                                |
| `:stale_connection`                                                                                     | Binding no longer current: an active connection already exists for an initial authorization, or `expected_connection_id` differs/was replaced                                                                                               |
| `:client_changed`                                                                                       | Provider OAuth client ID changed since the session started                                                                                                                                                                                  |
| `:missing_scopes`                                                                                       | Granted scopes lack a `required_scopes` entry                                                                                                                                                                                               |
| `:refresh_token_required`                                                                               | No refresh token issued or retained                                                                                                                                                                                                         |
| `:token_expired`                                                                                        | Candidate access token already expired                                                                                                                                                                                                      |
| `:repo_mismatch`                                                                                        | Multi ran on a different Repo than `config :tango, repo:`                                                                                                                                                                                   |
| `:invalid_completion_origin`                                                                            | Session origin not in `allowed_completion_origins`                                                                                                                                                                                          |
| `:invalid_claims`                                                                                       | Verifier returned a malformed result: missing/blank subject, claims too large, non-JSON, or token-like                                                                                                                                      |
| `"invalid_session"` (callback `oauth_error`)                                                            | Staged session expired, already claimed, or redirect URI differs. An unknown `state`, a `create_session/3` session, or an origin no longer allowed gets no `postMessage` at all                                                             |
| `"client_changed"`, `"access_denied"`, ... (callback `oauth_error`)                                     | Other callback failures as snake_case strings; unrecognized reasons collapse to `"callback_failed"`                                                                                                                                         |
| `"invalid_token_response"`, `"empty_access_token"`, `"invalid_grant_metadata"` (callback `oauth_error`) | Code exchange got a 2xx non-token body (HTML, JSON scalar, malformed), an empty 2xx body, or retained metadata over 4 KiB. A 3xx or a 2xx JSON `error` object posts its OAuth category instead (`"provider_error"`, `"access_denied"`, ...) |

## Cleanup

Tango starts no scheduler. Run both functions from the host job runner every few minutes, authorizations first:

```elixir
defmodule MyApp.Workers.TangoCleanup do
  use Oban.Worker, queue: :maintenance, max_attempts: 3

  @impl Oban.Worker
  def perform(_job) do
    {:ok, _candidates} = Tango.cleanup_expired_authorizations()
    {:ok, _sessions} = Tango.cleanup_expired_sessions()
    :ok
  end
end
```

```elixir
config :my_app, Oban,
  plugins: [
    {Oban.Plugins.Cron, crontab: [{"*/5 * * * *", MyApp.Workers.TangoCleanup}]}
  ]
```

Both return `{:ok, deleted_count}`. Adapt to Quantum, PgFlow, or a GenServer timer if the host does not use Oban.

## Token retention

- Tokens live only in AES-GCM encrypted columns. Candidate handles are stored as SHA-256 hashes; candidate token columns are nulled and `provider_data` reset to `%{}` on finalization or consumption and again by cleanup. Safe identity fields remain until cleanup; erasure affects live records, not backups/WAL or guaranteed memory zeroization. Consume mode creates no connection and does not revoke provider-side authorization.
- The `connection` returned by finalize holds usable plaintext tokens. Persist `connection.id` and the identity summary only; never copy tokens into host tables, job args, logs, error reports, or responses.
- Read credentials at call time with `Tango.get_active_connection(connection_id, tenant_id, auto_refresh: true)` ([connections.md](connections.md)).
