# Connections

A `Tango.Schemas.Connection` holds a tenant's encrypted tokens for one provider. Loaded structs carry decrypted `access_token` / `refresh_token` in memory; keep them inside the function that calls the provider.

Useful fields: `id`, `tenant_id`, `provider_id`, `account_subject`, `status` (`:active | :revoked | :expired`), `expires_at`, `granted_scopes`, `token_type`, `last_used_at`, `auth_failures`, `refresh_exhausted`.

## Credential-free reads (0.3.0)

Use these for status, account subject, and ids:

```elixir
{:ok, info} = Tango.get_connection_info(connection_id, tenant_id)
infos = Tango.list_connection_infos(tenant_id, provider_slug: "records", status: :any)
```

`%Tango.ConnectionInfo{}` has exactly `id`, `tenant_id`, `provider_slug`, `status`, `account_subject`, `granted_scopes`, and `expires_at`. Subject, scopes and expiry may be nil. No provider id, config, metadata, retry counters, credentials, or raw payload are selected. There is no automatic JSON encoder; explicitly choose presentation fields.

The id read includes every status; missing and wrong-tenant ids return `{:error, :not_found}`. Listing defaults to active, accepts `:active | :expired | :revoked | :any` or a list of statuses, and sorts ascending by id. Empty status lists and unknown slugs return `[]`. Invalid options raise `ArgumentError`. Both include inactive providers, never refresh or lock, and make no guarantee that an active token is usable or unchanged.

## Credential reads for provider calls

```elixir
Tango.get_active_connection(connection_id, tenant_id, auto_refresh: true)
Tango.get_connection_for_provider("records", tenant_id, auto_refresh: true)
```

Prefer the exact connection id pinned in host records. The provider getter returns the latest active connection. Handle refresh failures using [refresh-errors.md](refresh-errors.md); a provider outage must not automatically request reauthorization.

`auto_refresh: true` refreshes within five minutes of expiry, under generation and row locks. Fallback requires an active, still-valid token and a non-credential/non-persistence/non-transaction error. Default `auto_refresh: false` returns the last committed row without waiting for an in-flight refresh.

Legacy `Tango.get_connection/2` and `Tango.list_connections/2` still return credentials. The legacy list's `provider:` filter matches display **name**, not slug; it preloads providers by default. Use connection-info APIs for ordinary status/identity reads instead of host queries against Tango schemas.

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

Explicit refresh returns a bare `{:error, reason}`; on-demand returns the refresh-failed envelope unless fallback applies. Credential, client/request, transient and local failures have different policies: see [refresh-errors.md](refresh-errors.md). Tango schedules nothing; the host owns any proactive sweep job.

## Generation locks (0.3.0)

```elixir
MyApp.Repo.transaction(fn ->
  with :ok <- Tango.lock_connection_generations(tenant_id, ["beta", "alpha"]),
       {:ok, connection} <- Tango.revoke_connection(connection_id, tenant_id) do
    connection.id
  else
    {:error, reason} -> MyApp.Repo.rollback(reason)
  end
end)
```

Use the Repo configured for Tango, in the calling process. Validate host authorization separately. The lock function validates options first, then checks `in_transaction?()`, returning `{:error, :not_in_transaction}` before provider lookup when outside a transaction. Even `[]` requires the transaction; inside it returns `:ok`.

Providers are resolved together, including inactive ones. Default `missing: :error` returns `{:error, {:provider_not_found, slug}}` for the first absent slug in input order **without taking any locks**. `missing: :skip` ignores absent slugs; invalid options raise `ArgumentError`. If the host requires an active provider, check that requirement before acquiring the full batch.

Tango sorts/deduplicates by `{provider_id, tenant_id}` in Elixir term order, using its existing advisory-lock namespace. Slug order is irrelevant. Acquire the full provider set before nested Tango calls. Locks last until the outer transaction ends; reacquiring held keys is safe, adding a lower key later can deadlock. There is no guarantee for arbitrary cross-tenant lock composition. Locks establish neither authorization nor connection status.

## Revoke

```elixir
Tango.revoke_connection(connection_id, tenant_id) # integer id; 0.3.0+
Tango.revoke_connection(connection, tenant_id)    # existing struct overload
```

The id overload returns `{:error, :not_found}` for missing, wrong-tenant and already-revoked rows. A struct tenant mismatch remains `{:error, :not_authorized}`. Active and expired generations can be revoked. Routing is tenant-scoped and state is rechecked under generation/row locks. Failed revoke audit rolls back revocation; this differs from best-effort refresh-success auditing.

When terminal/missing generations should be a no-op inside a larger transaction, precheck `get_connection_info/2` while holding the generation lock and call revoke only for active/expired rows. Do not assume a failing nested transaction leaves its caller usable.

Revocation does not call the provider's revocation endpoint; perform that separately only when the host workflow requires it.

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
