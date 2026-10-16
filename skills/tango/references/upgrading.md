# Upgrade Tango

A dependency bump does not change the database. `mix tango.setup` generated a migration that already ran; it will not rerun, and running setup again would create a second install migration whose `down` drops every Tango table. Upgrade with a new, version-pinned host migration.

## Find the current state

```bash
grep '"tango"' mix.lock
```

```sql
SELECT obj_description('public.tango_providers'::regclass);
-- 'Tango version=2' before 0.2.0, 'Tango version=3' after V03
```

Use the configured `schema_prefix` instead of `public` when set. `Tango.Migration.migrated_version/1` reads the same marker but only works inside a migration (it uses the migration runner's repo).

| Tango release | Latest bundled schema |
|---------------|-----------------------|
| 0.1.0–0.1.1   | V01                   |
| 0.1.2–0.1.3   | V02                   |
| 0.2.0         | V03                   |

`Tango.Migration.up(version: 3)` applies every missing version from the recorded one, so a V01 database also receives V02. Check the release's `lib/tango/migration.ex` `versions:` list when in doubt.

## Pinned upgrade migration

```bash
mix ecto.gen.migration upgrade_tango_v03
```

```elixir
defmodule MyApp.Repo.Migrations.UpgradeTangoV03 do
  use Ecto.Migration

  def up, do: Tango.Migration.up(version: 3)
  def down, do: Tango.Migration.down(version: 2)
end
```

Pin both directions so rollback returns to the previous version instead of version 0. Pass `prefix: "..."` to both calls if the install used a non-default prefix and `schema_prefix` is not configured.

```bash
mix deps.update tango
mix ecto.migrate
```

Apply the migration before deploying code that calls authorization completion. V03 adds `tango_authorizations`, binding columns on `tango_oauth_sessions` (completion origin, intent reference, expected connection and subject, authorization params, OAuth client), and `account_subject` / `oauth_client_id` on `tango_connections`.

Without Ecto migrations, copy `deps/tango/priv/repo/sql/versions/v03/` into the host migration tool, replace `$SCHEMA$`, and stamp:

```sql
COMMENT ON TABLE "public".tango_providers IS 'Tango version=3';
```

## Migrate a 0.1.x popup callback to 0.2.0

0.1.x posted tokens and connection details to the browser. 0.2.0 posts only a completion handle. Work through every step; a partial migration leaves connect buttons broken or, worse, keeps credential-handling code alive.

1. Bump to `{:tango, "~> 0.2.0"}`, run `mix deps.update tango`, and apply the V03 migration above.
2. Configure `allowed_completion_origins` and pass `completion_origin` to every `Tango.Live.OAuthComponent` (now required).
3. Re-register the `TangoOAuth` hook from the updated `deps/tango/assets/tango_oauth_hook.js`; rebuild assets.
4. Write a verifier and a server-side `complete/3` that calls `Tango.verify_authorization/4` then `Tango.multi_finalize_authorization/5` ([authorization.md](authorization.md)).
5. Change `on_connect` handlers. The message is now `%{provider, tenant_id, completion_handle, intent_reference}`; take the tenant from the socket and call `complete/3`.
6. Replace custom JavaScript that read `connection` or token fields from `oauth_complete`. Read `completion_handle` and `intent_reference`, check `event.origin` and `event.source`, and POST the handle to an authenticated endpoint.
7. Delete code that copied tokens from the browser or logged callback payloads.
8. Schedule `Tango.cleanup_expired_authorizations/0` before `Tango.cleanup_expired_sessions/0`.

Search the host for leftovers before calling the migration done:

```bash
rg -n "access_token|refresh_token|oauth_complete|include_token|exchange_code" lib assets
```

Each hit should be server-side use of a loaded connection, not browser or log handling.

## Behavior changes in 0.2.0

- `/callback` only stages sessions created with `Tango.create_authorization_session/3`; legacy `create_session/3` sessions fail there.
- `POST /exchange` ignores `include_token`, never returns credentials, and rejects staged sessions. `Tango.exchange_code/4` also rejects staged sessions.
- `Tango.exchange_code/4` returns `{:oauth_error, category}` instead of a raw `%OAuth2.Response{}` on provider errors. Update pattern matches.
- Callback audit rows store a state hash and error category, not raw error text or state.
- Direct server-side flows (`create_session/3`, `authorize_url/2`, `exchange_code/4`) keep working.
- Connections created before V03 have no `account_subject` or `oauth_client_id`. Bind a subject with `Tango.verify_connection_identity/3`. Reauthorizing one succeeds, but finalize drops the old refresh token unless the provider issues a new one; with `require_refresh_token: true` it fails with `:client_changed`/`:account_mismatch` ([authorization.md](authorization.md), "Reauthorizing an existing connection").

## Rollback

Rolling back the V03 migration drops the authorization table and V03 columns. Roll back application code to 0.1.x first, then the migration. Pending candidates are lost; users re-authorize.
