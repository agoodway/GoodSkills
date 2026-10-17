# Debug Tango

Diagnose read-only first. Do not delete Tango rows, reset counters by SQL, or rerun `mix tango.setup` to "fix" state.

## Gather facts

1. Installed version: `rg '"tango"' mix.lock` and `deps/tango/mix.exs`.
2. Schema version: `SELECT obj_description('public.tango_providers'::regclass);` (adjust the prefix).
3. Config at runtime (`iex -S mix` or a remote console). Print presence, not secrets:

```elixir
Application.get_env(:tango, :repo)
Application.get_env(:tango, :allowed_completion_origins)
is_binary(Application.get_env(:tango, :api_key))
is_binary(Application.get_env(:tango, :encryption_key))
Tango.list_providers() |> Enum.map(& &1.slug)
```

4. Identify the failing operation and bounded error. For 0.3 refresh failures, log `Tango.RefreshError.to_storage(reason)`; never dump arbitrary nested reasons, raw provider bodies, tokens, codes, state, or handles.

## Symptom → cause

| Symptom                                                                  | Likely cause and fix                                                                                                                                         |
|--------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `ArgumentError` "Tango encryption key not configured" / "Key must be 32 bytes..." | `encryption_key` missing or wrong size. Use `openssl rand -base64 32` and set it in runtime config.                                                   |
| `UndefinedFunctionError` for `Tango.create_authorization_session/3`, `verify_authorization/4`, `multi_finalize_authorization/5` | Installed Tango is 0.1.x. Upgrade ([upgrading.md](upgrading.md)) or use the direct flow.                                    |
| `UndefinedFunctionError` for `Tango.exchange_code/3`                     | Call is missing `tenant_id`. Use `Tango.exchange_code(state, code, tenant_id, redirect_uri: uri)`.                                                           |
| Postgres "relation tango_authorizations does not exist" / missing column  | V03 migration not applied. Add the pinned upgrade migration.                                                                                                |
| `{:error, :provider_not_found}`                                          | No active provider with that slug. `Tango.get_provider/1`, then `mix tango.providers.create`.                                                               |
| `{:error, :invalid_tenant_id}` / `:tenant_id_too_long`                   | Tenant must match `^[a-zA-Z0-9_-]+$`, max 255 bytes. Emails and IDs with `.`/`:` fail; use a UUID or slug.                                                  |
| `{:error, :invalid_completion_origin}` on session start                  | `completion_origin` not exactly in `allowed_completion_origins` (trailing slash, port, `http` on non-localhost, wrong host).                                 |
| Popup completes but nothing happens                                      | Callback posted to an unlisted origin (it posts nothing), `TangoOAuth` hook not registered, `callback_url` origin differs from where `/callback` is served, or a popup blocker killed `window.open`. Check the browser console. |
| Provider says redirect URI mismatch                                      | Registered redirect differs from `redirect_uri` / `callback_url`. Must be the exact Tango `/callback` URL, including path prefix.                           |
| Callback posts `oauth_error` with `"invalid_session"`                   | Staged session expired (`session_timeout`), already claimed (double callback), or its bound redirect URI differs from the callback URL. A session from `create_session/3` produces no message at all (see "Popup completes but nothing happens"). |
| `{:error, :invalid_completion}`                                          | Handle unknown, malformed, for another tenant, or wrong `:provider` option. Confirm the tenant comes from the same server session that started the flow.     |
| `{:error, :completion_consumed}`                                         | Handle reused (double submit, LiveView reconnect replay) or a non-transient verifier error consumed it. Start a new flow.                                    |
| `{:error, :expired_completion}`                                          | More than ten minutes between callback and finalize.                                                                                                       |
| `{:error, :verification_required}`                                       | Finalize ran without a successful `verify_authorization/4` for this handle (verify failed, was skipped, or ran with a different handle).                     |
| `{:error, :stale_connection}`                                            | An active connection already exists for this provider/tenant on an initial authorization, or the expected connection was replaced. Reauthorize with `expected_connection_id`, or revoke first. |
| `{:error, :account_mismatch}`                                            | Reauthorization signed into a different provider account than `expected_subject`, or the verifier returned the wrong `continuity` (`:initial` vs `{:connection, id}` from `opts[:connection_id]`). At finalize it fires only when both stored and new subjects exist and differ; a pre-V03 connection with no stored subject drops its refresh token instead (unless `require_refresh_token: true`). |
| `{:error, :reserved_auth_parameter}` on session start                    | `auth_params` sets a protocol key (`state`, `redirect_uri`, `client_id`, `response_type`, `scope`, `code_challenge*`). Pass those through options instead. |
| `{:error, :missing_scopes}`                                              | User deselected scopes, or `required_scopes` lists a protocol hint like `offline_access`. Remove hints; request consent again.                             |
| `{:error, :refresh_token_required}`                                      | Provider issued no refresh token. Request offline access (e.g. Google `auth_params: %{"access_type" => "offline", "prompt" => "consent"}`) or drop the requirement. |
| `{:error, :repo_mismatch}`                                               | Multi committed via a different Repo (read replica, second repo, dynamic repo). Use the repo in `config :tango, repo:`.                                     |
| `{:error, :client_changed}`                                              | At finalize: either the provider client ID changed since the session started (restart the flow), or `require_refresh_token: true` was used to reauthorize a connection that has a refresh token but no recorded `oauth_client_id` (pre-V03 or `exchange_code/4`); drop `require_refresh_token` or revoke and connect fresh. The callback can also post `oauth_error` `"client_changed"`. |
| `{:error, {:oauth_error, category}}`                                     | Sanitized provider failure (denied consent, bad code, bad client secret). Check provider app config; the raw body is intentionally not returned.            |
| `{:error, {:refresh_failed, reason}}`                                    | In 0.3, classify the typed reason using [refresh-errors.md](refresh-errors.md). Credential failure requires reauthorization; HTTP outages and persistence/transaction failures do not. Legacy strings are not credential proof.                 |
| `{:error, :not_found}` for a connection that existed                     | Connection revoked or expired by `record_auth_failure/3` reaching `max_failures`. Check `status` and `last_auth_failure`.                                   |
| 401 from `Tango.API.Router`                                              | `api_key` unset, or request lacks `Authorization: Bearer` / `X-API-Key`. `/callback` and `/health` need no key.                                            |
| LiveView crashes with `FunctionClauseError` in `handle_info/2`           | Missing `{:tango_log, _}` or `on_error` clause.                                                                                                            |
| `tango_authorizations` / `tango_oauth_sessions` keep growing              | Cleanup not scheduled. Run `cleanup_expired_authorizations/0` then `cleanup_expired_sessions/0`.                                                           |

## Inspect rows safely

On 0.3 use `Tango.get_connection_info(id, tenant_id)` or `Tango.list_connection_infos(tenant_id, status: :any)` for status/identity. These include inactive providers without fetching credentials or refreshing tokens. For retry-state diagnosis not exposed by info, select only non-secret columns. Never `SELECT *` from `tango_connections` or `tango_authorizations` into logs or chat.

```sql
SELECT id, tenant_id, provider_id, status, account_subject, expires_at,
       auth_failures, last_auth_failure, refresh_exhausted, last_used_at
FROM tango_connections
WHERE tenant_id = $1
ORDER BY inserted_at DESC;
```

Tango writes audit rows without tokens, codes, raw state, or handles; use them to reconstruct a timeline.

## Report

State the installed version, schema version, the failing step (session start, callback, verify, finalize, call-time read), the error atom, and the evidence-based fix. If a mutation is needed, name the public function (`Tango.revoke_connection/2`, `Tango.update_provider/2`, `Tango.refresh_connection/1`) and its effect before running it.
