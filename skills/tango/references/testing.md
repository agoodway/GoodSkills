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


## Consume-mode tests

Use offline stub token/account/membership endpoints and the public staged flow on the configured test Repo. `Tango.Testing` still has no candidate helper; keep candidate inspection and exact-id cleanup in host support. All provider/subject/organization data must be synthetic. Test these observable results:

- Start with `completion_mode: :consume`, stage once, and verify through a host-selected verifier. The verify result has seven keys; `results.proof` after consumption has exactly the five keys in [consumption.md](consumption.md).
- Append a host step returning an error. Assert consumed state and verification remain unchanged and staged credentials remain present using booleans or safe field allowlists, without dumping candidate structs. Retry the consume Multi without another verifier/provider call or code exchange; assert the host write commits once.
- After commit, assert no new Tango connection, NULL candidate access/refresh tokens, empty `provider_data`, and consumed state. Use structural assertions, never print credentials or credential-bearing structs on failure.
- Assert replay/concurrent completion allows one committed host write and produces `:completion_consumed` while the candidate remains (`:invalid_completion` after cleanup). Assert unrelated existing connections remain unchanged and do not block the proof.
- Exercise optional subject binding, wrong tenant/provider/intent, missing scopes, malformed options, and mode mismatch. Consume accepts only provider, intent, and optional required scopes. Exercise retryable versus permanent verifier failures.
- For organization administration, stub active admin, inactive admin, active non-admin, wrong organization, and malformed identity responses. Recheck host permission/cancellation/version state inside the Multi and prove host rejection rolls back consumption.

Keep ordinary connection/refresh tests in place. A dependency version string, passing connection test, or schema marker 4 does not prove consumption readiness; inspect revised V04 columns/checks and run the consume path.
