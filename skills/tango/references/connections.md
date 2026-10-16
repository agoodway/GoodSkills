# Connections

A `Tango.Schemas.Connection` holds a tenant's encrypted tokens for one provider. Loaded structs carry decrypted `access_token` / `refresh_token` in memory; keep them inside the function that calls the provider.

Useful fields: `id`, `tenant_id`, `provider_id`, `account_subject`, `status` (`:active | :revoked | :expired`), `expires_at`, `granted_scopes`, `token_type`, `last_used_at`, `auth_failures`, `refresh_exhausted`.

## Read

By ID (preferred after authorization completion, since host tables store `connection.id`):

```elixir
case Tango.get_active_connection(connection_id, tenant_id, auto_refresh: true) do
  {:ok, connection} -> call_provider(connection)
  {:error, :not_found} -> {:error, :reconnect_required}
  {:error, {:refresh_failed, _reason}} -> {:error, :reconnect_required}
end
```

By provider slug (latest active connection for the tenant):

```elixir
{:ok, connection} = Tango.get_connection_for_provider("github", tenant_id)
{:ok, connection} = Tango.get_connection_for_provider("github", tenant_id, auto_refresh: true)
```

List a tenant's active connections:

```elixir
connections = Tango.list_connections(tenant_id)
connections = Tango.list_connections(tenant_id, provider: "GitHub", preload: false)
```

The `:provider` filter matches the provider's `name` (display name such as `"GitHub"`), not its slug. Filter by slug in Elixir (`connection.provider.slug`) when unsure of the stored name. `preload` defaults to `true`.

`auto_refresh: true` refreshes when the token expires within five minutes. Refresh is row-locked, so concurrent callers reuse one refresh. A failed refresh still returns a still-valid token, but an expired one becomes `{:error, {:refresh_failed, reason}}`. A refresh that succeeds is kept even if writing its audit log fails (the error is logged). With `auto_refresh: false` (the default) the read takes no lock and returns the last committed row even while a refresh is in flight.

## Call a provider

```elixir
def fetch_repos(connection_id, tenant_id) do
  with {:ok, connection} <- Tango.get_active_connection(connection_id, tenant_id, auto_refresh: true) do
    headers = [{"authorization", "Bearer " <> connection.access_token}]

    case Req.get("https://api.github.com/user/repos", headers: headers) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        Tango.record_auth_success(connection)
        Tango.mark_connection_used(connection)
        {:ok, body}

      {:ok, %Req.Response{status: 401}} ->
        Tango.record_auth_failure(connection, "http_401", max_failures: 3)
        {:error, :unauthorized}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:http_error, status}}

      {:error, exception} ->
        {:error, exception}
    end
  end
end
```

Pass `connection_id` and `tenant_id` into background jobs, never the connection struct or tokens.

## Report provider auth outcomes

Tango cannot see calls made with its tokens, so a revoked credential stays `:active` until the host reports rejection.

- `Tango.record_auth_failure(connection, reason, opts)` increments `auth_failures`. At `max_failures` (default 3) the connection becomes `:expired` and lookups return `{:error, :not_found}`. Accepts a connection, or an ID plus `tenant_id: ...` (an ID without it returns `{:error, :tenant_id_required}`). Only active connections accept reports; others return `{:error, :not_found}`. A non-positive `max_failures` raises `ArgumentError`.
- `Tango.record_auth_success(connection, opts)` clears the streak so the count stays consecutive. Returns `:ok` (also for inactive or already clean connections); an ID without `tenant_id:` returns `{:error, :tenant_id_required}`.
- Report a 401, or a 403 whose provider-specific body confirms an invalid/revoked token. Do not report 403s for scope, resource policy, or quota.
- `max_failures` counts rejections, not time. Raise it for high-volume callers.

```elixir
Tango.record_auth_failure(connection_id, "http_401", tenant_id: tenant_id, max_failures: 10)
```

## Refresh

```elixir
{:ok, connection} = Tango.refresh_connection(connection)   # force refresh
{:ok, count} = Tango.refresh_expiring_connections()        # batch; size from :refresh_batch_size
```

`refresh_connection/1` reports a provider failure as `{:error, reason}` even while the current access token is still valid (`:no_refresh_token` and `:refresh_not_allowed` when the connection is not refreshable). Three consecutive refresh failures set `refresh_exhausted` and expire the connection. `refresh_expiring_connections/0` is not scheduled by Tango. Run it from the host job runner if proactive refresh is wanted; otherwise rely on `auto_refresh: true` at call time.

## Revoke

```elixir
{:ok, revoked} = Tango.revoke_connection(connection, tenant_id)
```

The tenant must match the connection's tenant or the call returns `{:error, :not_authorized}`. Both `:active` and `:expired` connections can be revoked; an already revoked one returns `{:error, :not_found}`. Revocation marks the row `:revoked` and writes an audit entry. It does not call the provider's revocation endpoint; do that separately if the provider supports it and the product needs it.

Bulk revocation lives on `Tango.Connection` (not delegated from `Tango`). Both cover `:active` and `:expired` rows and return `{:ok, revoked_count}`:

```elixir
{:ok, count} = Tango.Connection.revoke_tenant_connections(tenant_id)   # e.g. tenant offboarding
{:ok, count} = Tango.Connection.revoke_provider_connections("github")  # by slug; provider must still be active
```

`revoke_provider_connections/1` crosses tenants; call it only from trusted admin code. Run it before `Tango.delete_provider/1`, because it looks the provider up among active providers only.

`Tango.Connection.cleanup_expired_connections/0` deletes connections that have been `:expired` for more than 30 days; it is not scheduled either.

## Identity recheck

```elixir
{:ok, %{subject: subject, claims: claims}} =
  Tango.verify_connection_identity(connection_id, tenant_id, {MyApp.Integrations.ExampleVerifier, []})
```

Requires 0.2.0. The verifier must return `continuity: {:connection, connection_id}` (Tango passes it as `opts[:connection_id]`). Binds `account_subject` when absent; fails with `:account_mismatch` when the provider account changed, `:stale_connection` when the connection is not `:active`, and `:not_found` for an unknown or other-tenant ID.
