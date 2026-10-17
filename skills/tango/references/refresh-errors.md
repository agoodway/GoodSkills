# Refresh errors and policy (0.3.0)

Read this when replacing legacy string matches, handling refresh failures, or debugging an outage. Confirm the installed Tango version first.

## Returned values

| Entry point | Failure |
| --- | --- |
| `Tango.refresh_connection/1` | `{:error, reason}`, even when the current token has time left |
| `Tango.Connection.refresh_if_needed/1` | `{:error, {:refresh_failed, reason}}`, unless valid-token fallback applies |
| `Tango.get_active_connection/3`, `Tango.get_connection_for_provider/3` with `auto_refresh: true` | Same on-demand envelope |
| `Tango.refresh_expiring_connections/0` | `{:ok, actual_success_count}`; failures do not count as success |

There is no `Tango.refresh_if_needed/1`. Missing or inactive connections return `{:error, :not_found}` outside the refresh reason union. Non-refreshing getters retain their existing contracts.

For an active row without a refresh token, explicit refresh returns `:no_refresh_token`. On-demand refresh checks expiry first: if refresh is needed but ineligible, its reason is `:refresh_not_allowed`, with still-valid-token fallback where allowed. An inactive fixture returns `:not_found` before either eligibility result.

## Closed reasons

`Tango.RefreshError.classify/1` accepts any term. Use the class for policy; never parse stored strings or create atoms from provider input.

| Reason | Class |
| --- | --- |
| `{:oauth_error, :invalid_grant}` | `:credential` |
| `{:oauth_error, :invalid_client \| :unauthorized_client}` | `:client` |
| `{:oauth_error, :invalid_request \| :invalid_scope \| :unsupported_grant_type}` | `:request` |
| `{:oauth_error, :temporarily_unavailable \| :server_error}` | `:transient` |
| `{:rate_limited, seconds_or_nil}` | `:transient`; seconds must be a nonnegative integer |
| `{:http_error, status}` | `:transient` for 408 or 5xx, otherwise `:request` |
| `{:transport_error, :timeout \| :network_error}` | `:transient` |
| `:no_refresh_token`, `:refresh_not_allowed`, `:provider_not_found`, `:invalid_config`, `:persistence_failed`, `:transaction_failed` | `:local` |
| Any unknown term, including legacy strings or malformed tagged tuples | `:local` |

`from_response(status, headers, body)` gives HTTP 429, 408 and 5xx precedence over an `invalid_grant` body. Other 4xx may produce an allowlisted OAuth code. A binary body is decoded once and accepted only as an object; HTML, scalars, double-encoded objects and unknown codes retain the HTTP status. `from_transport/1` maps `:timeout`/`:etimedout` to timeout, all other transport details to network error.

`Retry-After` uses the first case-insensitive header name and accepts only a complete decimal digit string, including zero. Dates, signs, floats and mixed text produce nil. The reason keeps the parsed value; `backoff_seconds/1` caps it at 3600 seconds, otherwise defaults to 300.

The refresh HTTP boundary rejects malformed/non-object successful bodies before storing tokens. Test through the actual token request, since OAuth2 can otherwise convert a raw binary response into an access token. Keep this behavior scoped to refresh; do not change exchange serialization or enable OAuth2 debug response logging.

## Persistence and fallback

- Credential failure increments once, immediately expires and exhausts the connection.
- Client/request failures consume attempts and expire/exhaust at three. Exhaustion does not prove the user revoked consent; subsequent active getters nevertheless return `:not_found`.
- Transient failure preserves attempts/status/exhaustion and schedules `next_refresh_at`. It does not erase earlier client/request attempts.
- Local configuration failures retain the explicit-attempt budget. Eligibility failures (`:no_refresh_token`, `:refresh_not_allowed`) do not write attempts. Persistence/transaction failures do not consume attempts or invalidate credentials.
- Recorded non-transient failures clear backoff. Success clears attempts, failure state, exhaustion, auth-failure streak and `next_refresh_at`. Failed refreshes never revive expired/revoked rows.

Fallback requires the persisted row to remain active and its access token to be unexpired (or have nil expiry). Credential, persistence and transaction failures never serve the old token. A provider may already have rotated its refresh token before a database write fails.

Returned token/bookkeeping changeset failures become `:persistence_failed`; returned transaction failures become `:transaction_failed`. Raw changesets never escape refresh paths. Persistence failure rolls back the refresh transaction. Raised database exceptions are not blanket-rescued. A success-audit failure stays best-effort and does not undo saved tokens. Do not assume a nested Ecto transaction provides savepoint isolation for a caller that catches an error.

`next_refresh_at` is sweep-only: explicit and on-demand refresh ignore it while retaining eligibility checks. Sweeps recheck status, eligibility, expiry and due time after locking. Skipped rows count as neither success nor failure; persistence/transaction errors count as failures. Thus on-demand requests can still hit an unavailable provider during backoff.

## Reporting and host decisions

```elixir
case Tango.get_active_connection(connection_id, tenant_id, auto_refresh: true) do
  {:ok, connection} ->
    call_provider(connection)

  {:error, {:refresh_failed, reason}} ->
    Logger.warning("OAuth refresh failed", reason: Tango.RefreshError.to_storage(reason))

    case Tango.RefreshError.classify(reason) do
      :credential -> {:error, :reauthorization_required}
      _other -> {:error, :connection_unavailable}
    end

  {:error, :not_found} ->
    {:error, :connection_unavailable}
end
```

The host decides how missing connections and named local eligibility failures affect its own workflow. `classify/1 == :local` is not proof of revoked consent.

`to_storage/1` emits allowlisted strings such as `"oauth_error:invalid_grant"`, `"http_error:503"`, `"rate_limited:30"`, and `"persistence_failed"`; unknown values become `"unknown_refresh_error"`. At each Logger/Sentry/JSON boundary, sanitize refresh envelopes inside the actual context structure, including nested error wrappers. Preserve unrelated error tuple contracts; do not globally stringify arbitrary errors. Never log raw provider bodies or credential-bearing structs.

Legacy `last_refresh_failure` strings remain informational, unparsed and unmigrated. The resource-call APIs `record_auth_failure/3` and `record_auth_success/2` are unchanged.
