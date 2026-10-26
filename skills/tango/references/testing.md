# Consumer fixtures (0.3.0+)

`Tango.Testing` is compiled in all environments but intended for consumer tests. It exposes two helpers (attribute maps default to `%{}`):

```elixir
provider = Tango.Testing.insert_provider!(%{slug: "records", name: "Records"})

connection =
  Tango.Testing.insert_connection!(provider, "tenant-123", %{
    refresh_token: nil,
    granted_scopes: [],
    account_subject: "record-owner",
    status: :active
  })

{:ok, info} = Tango.get_connection_info(connection.id, "tenant-123")
{:error, :no_refresh_token} = Tango.refresh_connection(connection)
```

Supply atom-key attributes. Defaults include unique example.test provider endpoints, `records.read` scopes and random dummy tokens. The connection's `oauth_client_id` defaults from provider config. Passed provider/tenant arguments own routing; attributes cannot override them.

Explicit nil `refresh_token`, `granted_scopes`, `account_subject` and `expires_at` stay nil; omitted refresh tokens become dummy tokens. Set `refresh_token: nil` when testing missing-token behavior. Explicit nil access token fails. Active/expired/revoked statuses are supported; normal encryption and database constraints still apply. Invalid changesets raise `Ecto.InvalidChangesetError`; do not log that exception's credential-bearing changeset.

The host supplies configured Repo/encryption, sandbox or other test ownership, and cleanup. Helpers do not change config, start services, own a sandbox, make HTTP requests, or delete data. Keep candidate creation, row aging, and exact-id cleanup in the consumer test support; there is no public candidate/aging/delete helper.

Sandbox ownership is not a transaction: `Tango.lock_connection_generations/3` returns `{:error, :not_in_transaction}` in a test unless the call runs inside an explicit `Repo.transaction/1` on Tango's Repo.

To test token-response metadata or body client auth, pass provider `metadata`, e.g. `insert_provider!(%{metadata: %{"token_response_metadata" => ["instance_url"], "authorization_method" => "body"}})`, and stub the token endpoint (Bypass or similar) in the host suite; invalid values raise `Ecto.InvalidChangesetError`. Assert the verifier's `provider_data` through a stub verifier on the popup path; `exchange_code/4` never retains it.
