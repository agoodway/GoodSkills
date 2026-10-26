# Upgrade Tango

A dependency bump does not change the database. `mix tango.setup` generated an install migration that already ran; it will not rerun, and running setup again creates a second install migration whose `down` drops every Tango table. Add a new, version-pinned host migration whenever the target release bundles a newer schema than the database records.

## Release to schema

| Tango release | Bundled schema | DDL needed from the previous release |
|---------------|----------------|--------------------------------------|
| 0.1.0–0.1.1   | V01            | —                                    |
| 0.1.2–0.1.3   | V02            | V02                                  |
| 0.2.0         | V03            | V03 (authorization completion)       |
| 0.3.0         | V03            | none                                 |
| 0.4.0         | V04            | V04 (`tango_authorizations.provider_data`); required for every 0.4 install, whether or not a provider uses it |

Confirm against the installed release's `lib/tango/migration.ex` `versions:` list and `priv/repo/sql/versions/` when in doubt.

## Detect the current state

```bash
rg '"tango"' mix.lock              # Hex release; path/git deps have no Hex lock entry
rg '@version' deps/tango/mix.exs
```

```sql
SELECT obj_description('public.tango_providers'::regclass);
-- 'Tango version=3' on 0.2.0/0.3.0, 'Tango version=4' after V04
```

Use the configured `schema_prefix` instead of `public` when set. `Tango.Migration.migrated_version/1` reads the same marker but only inside a migration (it uses the migration runner's repo).

A local version string does not prove Hex publication. Verify the target is published before pinning `{:tango, "~> x.y.0"}`; otherwise use the explicitly chosen path/git source for provisional testing, never commit a temporary absolute path, and treat local results as provisional adoption. Publication, tags, pushes, and commits need their own authorization.

## Ordered procedure

There is no mixed-version rolling upgrade across a schema advance: 0.4 code selects `provider_data` and fails against V03.

1. Back up the database. Record the current release and schema marker.
2. Read the target section below and update host code the release changes (verifiers, error matches, provider metadata).
3. Generate a pinned migration for the target schema. Pin both directions so rollback returns to the previous version, not version 0.
4. Bump the dependency, run `mix deps.update tango`, and inspect the lock for the expected version and unrelated changes.
5. Run `mix ecto.migrate` before serving the new code.
6. Verify (below), then run focused consumer tests.

```bash
mix ecto.gen.migration upgrade_tango_v04
```

```elixir
defmodule MyApp.Repo.Migrations.UpgradeTangoV04 do
  use Ecto.Migration

  def up, do: Tango.Migration.up(version: 4)
  def down, do: Tango.Migration.down(version: 3)
end
```

`up(version: N)` applies every missing version from the recorded one, so a V02 database also receives V03. Pass `prefix: "..."` to both calls when the install used a non-default prefix and `schema_prefix` is not configured. From 0.1.x, a separate `UpgradeTangoV03` (`up(version: 3)` / `down(version: 2)`) lets rollback stop at V03, and the popup callback migration below is also required.

Without Ecto migrations, copy each missing `deps/tango/priv/repo/sql/versions/vNN/vNN_up.sql` into the host migration tool in order, replace `$SCHEMA$`, run the statements separated by `--SPLIT--`, and stamp the marker:

```sql
COMMENT ON TABLE "public".tango_providers IS 'Tango version=4';
```

## Upgrade 0.3.0 to 0.4.0

1. Apply V04. It adds `provider_data JSONB NOT NULL DEFAULT '{}'` and check `tango_authorizations_provider_data_check` (must be a JSON object). No backfill.
2. Verifiers: the credential is now `%{access_token:, granted_scopes:, provider_data:}`. Existing two-key patterns still match (map patterns are partial). `verify_connection_identity/3` always passes `provider_data: %{}` ([authorization.md](authorization.md)).
3. Token-response metadata: providers imported from the catalog before 0.4 lack `metadata["token_response_metadata"]`. Run `mix tango.providers.sync --update-metadata --only <slug>` or `Tango.update_provider/2` to add it ([providers.md](providers.md)).
4. Body client auth: a provider row whose metadata already holds `"authorization_method" => "body"` (set by hand, since the Nango catalog never uses `body`; 0.3 ignored it) now sends `client_id` and `client_secret` in the body with no Basic header, on exchange and refresh. Audit rows before deploying:

   ```sql
   SELECT slug, metadata->>'authorization_method', metadata->>'token_request_auth_method'
   FROM tango_providers;
   ```

5. Error handling: map the code-exchange errors `:invalid_token_response`, `:empty_access_token`, and (popup only) `:invalid_grant_metadata` ([debug.md](debug.md)). 3xx and 2xx-with-`error` responses now surface as `{:oauth_error, category}`.
6. `create_session/3` `:metadata` now drops every key matching `Tango.Validation.sensitive_key?/1` (names containing `token`, `secret`, `header`, `nonce`, `signature`, a standalone `code` segment, ...). Rename colliding host keys.
7. No host change for redaction: provider `client_secret` writes use the opaque SQL-log/telemetry placeholder tokens already used, and secret schema fields are `redact: true` for `inspect/1`.

Refresh error classes, connection info, generation locks, revoke, and `Tango.Testing` are unchanged.

## Upgrade 0.2.0 to 0.3.0

No DDL (stays V03). Do not restore 0.2.0 while keeping code that calls 0.3 APIs.

1. Replace refresh-string matching with `Tango.RefreshError.classify/1`; use `to_storage/1` at reporting boundaries ([refresh-errors.md](refresh-errors.md)). Client/request budget exhaustion is not proof of revoked consent.
2. Replace status/identity schema queries with connection-info reads, internal lock calls with `Tango.lock_connection_generations/3` (keep transaction-wide lock order), and adopt tenant-scoped id revocation where appropriate ([connections.md](connections.md)).
3. Migrate ordinary fixtures to `Tango.Testing`, preserving explicit nil fields and consumer-owned cleanup ([testing.md](testing.md)).

Old `last_refresh_failure` strings are not parsed or migrated. Expired/exhausted rows are not revived. A future `next_refresh_at` delays sweeps; 0.2.0 workers ignore it, so mixed refresh workers do not honor backoff consistently. Explicit/on-demand refresh ignores backoff. `record_auth_failure/3` and `record_auth_success/2` are unchanged.

## Migrate a 0.1.x popup callback to 0.2.0

0.1.x posted tokens to the browser; 0.2.0 posts only a completion handle. Apply V03, then work through every step; a partial migration leaves connect buttons broken or credential-handling code alive.

1. Configure `allowed_completion_origins` and pass `completion_origin` to every `Tango.Live.OAuthComponent` (now required).
2. Re-register the `TangoOAuth` hook from the updated `deps/tango/assets/tango_oauth_hook.js`; rebuild assets.
3. Write a verifier and a server-side `complete/3` that calls `Tango.verify_authorization/4` then `Tango.multi_finalize_authorization/5` ([authorization.md](authorization.md)).
4. `on_connect` messages are now `%{provider, tenant_id, completion_handle, intent_reference}`; take the tenant from the socket and call `complete/3`.
5. Custom JavaScript reads `completion_handle` and `intent_reference`, checks `event.origin` and `event.source`, and POSTs the handle to an authenticated endpoint.
6. Delete code that copied tokens from the browser or logged callback payloads.
7. Schedule `Tango.cleanup_expired_authorizations/0` before `Tango.cleanup_expired_sessions/0`.

```bash
rg -n "access_token|refresh_token|oauth_complete|include_token|exchange_code" lib assets
```

Each hit should be server-side use of a loaded connection, not browser or log handling.

0.2.0 behavior changes: `/callback` stages only `create_authorization_session/3` sessions; `POST /exchange` ignores `include_token` and rejects staged sessions; `exchange_code/4` returns `{:oauth_error, category}` instead of a raw `%OAuth2.Response{}`; callback audit rows store a state hash and category. Connections created before V03 have no `account_subject` or `oauth_client_id`; bind a subject with `Tango.verify_connection_identity/3`, and see [authorization.md](authorization.md) "Reauthorizing an existing connection" for refresh-token carry-forward.

## Verify

```sql
SELECT obj_description('public.tango_providers'::regclass);   -- 'Tango version=4'
SELECT conname FROM pg_constraint
WHERE conname = 'tango_authorizations_provider_data_check';   -- one row
```

Then run one popup authorization through verify and finalize, refresh one connection, and run `Tango.cleanup_expired_authorizations/0`; each touches the table or token-request path 0.4 changed. For a provider with `token_response_metadata`, assert the verifier receives the expected `provider_data` keys.

## Rollback

- V04 → V03: deploy 0.3.0 code first, then `mix ecto.rollback` the pinned migration; `down(version: 3)` drops the check and column and the marker returns to 3. Staged candidates lose retained fields; connections are untouched. Manual installs run `v04_down.sql` and restamp `'Tango version=3'`.
- 0.3.0 → 0.2.0: no DDL; remove code that calls 0.3 APIs first.
- V03 → V02: deploy 0.1.x code first; the rollback drops `tango_authorizations` and the binding columns. Pending candidates are lost; users re-authorize.
- Never roll back by reverting the install migration; its `down` drops every Tango table. Restore the backup if a forward fix is not possible.
