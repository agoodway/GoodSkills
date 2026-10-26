# Upgrade Tango

A dependency bump does not change the database. `mix tango.setup` generated an install migration that already ran; it will not rerun, and running setup again creates a second install migration whose `down` drops every Tango table. Add a new, version-pinned host migration whenever the target release bundles a newer schema than the database records. For 0.4.1, revised V04 also requires a physical schema check even when the marker is already 4.

## Release to schema

| Tango release | Bundled schema | DDL needed from the previous release                                                                                        |
| ------------- | -------------- | --------------------------------------------------------------------------------------------------------------------------- |
| 0.1.0-0.1.1   | V01            | -                                                                                                                           |
| 0.1.2-0.1.3   | V02            | V02                                                                                                                         |
| 0.2.0         | V03            | V03 (authorization completion)                                                                                              |
| 0.3.0         | V03            | none                                                                                                                        |
| 0.4.0         | original V04   | `tango_authorizations.provider_data` and its object check                                                                   |
| 0.4.1         | revised V04    | Adds completion mode columns/checks to sessions and candidates; marker remains 4, physical shape required for every install |

This map describes source/schema compatibility, not publication status. Confirm against the installed release's `lib/tango/migration.ex` `versions:` list and `priv/repo/sql/versions/` when in doubt.

## Detect the current state

```bash
rg '"tango"' mix.lock              # Inspect Hex/git resolution; path deps have no lock entry
rg '@version' deps/tango/mix.exs
```

```sql
SELECT obj_description('public.tango_providers'::regclass);
-- 'Tango version=3' on 0.2.0/0.3.0, 'Tango version=4' after V04
```

Use the configured `schema_prefix` instead of `public` when set. `Tango.Migration.migrated_version/1` reads the same marker but only inside a migration (it uses the migration runner's repo).

A local version string does not prove Hex publication. Verify the target is published before pinning a Hex dependency such as `{:tango, "~> 0.4.1"}`; otherwise use the explicitly chosen path/git source for provisional testing, never commit a temporary absolute path, and treat local results as provisional adoption. Publication, tags, pushes, and commits need their own authorization.

## Ordered procedure

Apply required DDL before serving the target code: 0.4 code selects `provider_data` and fails against V03; 0.4.1 also selects `completion_mode` and fails against original V04. Inspect the resolved API implementation and physical schema, even for connection-only consumers.

1. Back up the database. Record the current release and schema marker.
2. Read the target section below and update host code the release changes (verifiers, error matches, provider metadata).
3. For a database below V04, generate the pinned migration below. For marker 4, follow the revised V04 procedure instead. Pin both directions so rollback returns to the previous version, not version 0.
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

Without Ecto migrations, copy each missing `deps/tango/priv/repo/sql/versions/vNN/vNN_up.sql` into the host migration tool in order, replace `$SCHEMA$`, and execute the reviewed statements and marker in one transaction (with stop-on-error). Keep the `--SPLIT--` statements together transactionally, especially rollback guards and DDL. Stamp only after the DDL succeeds:

```sql
COMMENT ON TABLE "public".tango_providers IS 'Tango version=4';
```

## Upgrade to 0.4.1 and revised V04

Ordinary direct connections, staged connection finalization, refresh, and revoke remain supported. Connection completion stays the default. Optional one-time proofs select `completion_mode: :consume` at session creation and use the direct owning-module API `Tango.Authorization.multi_consume_authorization/5`; see [consumption.md](consumption.md). Confirm this function in resolved source before using it. Installing 0.4.1 alone applies no DDL and does not prove the feature is ready or published.

0.4.1 revises V04 in place under the explicitly authorized no-external-consumers exception for 0.4.0. There is no V05. Revised V04 retains `provider_data` and adds `completion_mode TEXT NOT NULL DEFAULT 'connection'` on `tango_oauth_sessions` and `tango_authorizations`, mode checks allowing only `connection`/`consume`, and checks forbidding connection bindings on consume rows. Existing rows default to connection mode. Every 0.4.1 installation requires this shape, even if it never uses consume mode.

- Fresh installs apply migrations through revised V04 using the resolved 0.4.1 source.
- Databases below V04 use the pinned up-to-4/down-to-3 wrapper above with the revised implementation. Missing earlier versions are applied in order.
- Already-stamped V04 databases need the [physical shape inspection](#verify) below. The applied wrapper does not rerun V04, and rerunning full V04 SQL is not a repair: its columns/checks are not all idempotent. If retaining data, reconcile only the missing DDL in a reviewed targeted host migration. A disposable developer database can instead be recreated fresh and migrated through revised V04.

The current V04 down migration cannot run on original V04: its guard queries the missing `completion_mode` columns before DDL. Current-wrapper down/up roundtripping is not a reconciliation path for that schema. Tango performs no automatic runtime repair; changing the version marker does not repair physical shape.

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

Read the marker and physical shape using the configured prefix (these examples use `public`):

```sql
SELECT obj_description('public.tango_providers'::regclass);

SELECT table_name, column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name IN ('tango_oauth_sessions', 'tango_authorizations')
  AND column_name IN ('completion_mode', 'provider_data')
ORDER BY table_name, column_name;

SELECT c.relname AS table_name, con.conname,
       pg_get_constraintdef(con.oid) AS definition
FROM pg_constraint con
JOIN pg_class c ON c.oid = con.conrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relname IN ('tango_oauth_sessions', 'tango_authorizations')
  AND con.contype = 'c'
ORDER BY c.relname, con.conname;
```

For 0.4.1 require marker 4, both text/NOT NULL/default `'connection'` mode columns, and both mode checks. `tango_oauth_sessions_consume_connection_check` must require a NULL `expected_connection_id` for consume sessions. `tango_authorizations_consume_connection_check` must require NULL `expected_connection_id` and `verified_connection_id` for consume candidates. Retain `provider_data` as JSONB/NOT NULL/default `'{}'` with `tango_authorizations_provider_data_check` requiring a JSON object. Compare definitions as well as constraint names with the resolved `priv/repo/sql/versions/v04/v04_up.sql`.

Then test one ordinary popup through verify/finalize, a connection refresh, and authorization cleanup. For configured metadata, assert the verifier receives the expected safe keys. For one-time proofs, also exercise the [offline consume tests](testing.md#consume-mode-tests), including host rollback/retry without another code exchange, replay, mode isolation, and credential erasure. Record dependency source/API, physical schema, and focused test results separately from publication or live-provider verification.

## Rollback

Revised V04 to V03 requires coordinated compatible host code and a pinned `down(version: 3)` migration. It first takes `ACCESS EXCLUSIVE` locks on `tango_oauth_sessions`, then `tango_authorizations`, held through DDL and migration completion. These locks block concurrent activity on both tables. Before any DDL, rollback refuses an unexpired consume session with no code exchange (`exchanged_at IS NULL`) or an unexpired consume candidate not yet consumed (`consumed_at IS NULL`).

Complete pending operations or let them expire, then run `Tango.cleanup_expired_authorizations/0` followed by `Tango.cleanup_expired_sessions/0` before retrying. Normal cleanup removes eligible consumed/expired temporary rows; active unexpired work must complete or expire. Revoking ordinary credential connections does not resolve this guard and must not be used to bypass it.

After the guard passes, rollback drops both completion-mode columns and their checks, plus `provider_data` and its object check, and returns the marker to 3. Assess the loss of staged metadata before proceeding; stored connections remain untouched. For manual rollback, execute every reviewed SQL statement and the `Tango version=3` marker together in one stop-on-error transaction, keeping the locks held through DDL.

This revised down SQL requires both `completion_mode` columns. It cannot run against original applied V04 or serve as its reconciliation path; follow [the targeted reconciliation procedure](#upgrade-to-041-and-revised-v04) for that shape.

- 0.3.0 → 0.2.0: no DDL; remove code that calls 0.3 APIs first.
- V03 → V02: deploy 0.1.x code first; the rollback drops `tango_authorizations` and the binding columns. Pending candidates are lost; users re-authorize.
- Never roll back by reverting the install migration; its `down` drops every Tango table. Restore the backup if a forward fix is not possible.
