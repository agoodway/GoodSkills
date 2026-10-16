---
name: tango
description: "Use when installing, configuring, upgrading, or debugging Tango in Elixir/Phoenix: the `:tango` dep, `mix tango.*` tasks, Nango catalog providers, per-tenant OAuth connections to third-party APIs, or invoking `/tango`. Not for user sign-in (Ueberauth, phx.gen.auth) or OAuth servers (Boruta)."
---

# Tango

Tango is an OAuth client library for Phoenix: provider configs from the Nango catalog, PKCE sessions, AES-GCM encrypted tokens in the host Ecto repo, and per-tenant connections. Version 0.2.0 adds credential-free popup completion (schema V03).

Inspect the consumer's installed Tango version before writing code (`mix.lock`, `deps/tango/mix.exs`). Path/git checkouts can expose APIs the published Hex package lacks; 0.1.x has no `create_authorization_session/3`, `verify_authorization/4`, `multi_finalize_authorization/5`, or `allowed_completion_origins`. When `deps/tango/docs/` and `deps/tango/lib/` disagree, follow `lib/`.

## Route the request

Read only the references needed for the request:

| Request                                          | Reference                                                                                       |
| ------------------------------------------------ | ----------------------------------------------------------------------------------------------- |
| Install, configure, first migration              | [references/bootstrap.md](references/bootstrap.md)                                              |
| Add or sync providers (Nango catalog, custom)    | [references/providers.md](references/providers.md)                                              |
| Server-side redirect flow (no popup)             | [references/direct-flow.md](references/direct-flow.md)                                          |
| Popup completion, verifier, finalize, cleanup    | [references/authorization.md](references/authorization.md)                                      |
| Mount the HTTP router, CORS, API key             | [references/api.md](references/api.md)                                                          |
| LiveView connect button                          | [references/liveview.md](references/liveview.md), then [references/authorization.md](references/authorization.md) |
| Use, refresh, revoke, report auth failures       | [references/connections.md](references/connections.md)                                          |
| Upgrade schema or migrate a legacy popup callback | [references/upgrading.md](references/upgrading.md)                                              |
| Debug errors                                     | [references/debug.md](references/debug.md)                                                      |

For `/tango help` or an unknown/missing subcommand, list: `bootstrap`, `providers`, `flow`, `authorization`, `api`, `liveview`, `connections`, `upgrade`, `debug`, and `help`. `flow` maps to [references/direct-flow.md](references/direct-flow.md). Then follow the matching reference.

Choose the flow before writing code: a browser popup connect button uses authorization completion ([references/authorization.md](references/authorization.md)); a server that receives the provider redirect itself uses the direct flow ([references/direct-flow.md](references/direct-flow.md)). The two session kinds are not interchangeable.

## Non-negotiable safety rules

- Keep tokens server-side. Never put access/refresh tokens, provider bodies, authorization codes, raw `state`, or completion handles into browser responses, `postMessage` payloads, rendered assigns, job args, logs, telemetry, or error reports. Persist only `connection.id` and the identity summary in host tables; read credentials at call time with `Tango.get_active_connection/3`.
- Take the tenant from the authenticated server session (`conn.assigns`, `socket.assigns`), never from browser input, query params, or the `on_connect` message, and pass it to every tenant-scoped call. Tenant IDs match `^[a-zA-Z0-9_-]+$` and are at most 255 bytes.
- Never ship `TANGO_API_KEY` to the browser. `Tango.API.Router` trusts the `X-Tenant-ID` header over `conn.assigns.current_tenant_id`, so anyone holding the key chooses the tenant. Call key-protected routes from server code only.
- Never `inspect`, log, or return in an error tuple a loaded `%Tango.Schemas.Connection{}` or `%Tango.Schemas.Authorization{}`: decrypted tokens are plain struct fields and the schemas do not redact `Inspect`. Never write Tango token columns with host `Repo` calls; Tango's own writes route them through `Tango.RedactedParams` so query logs and telemetry never see them.
- `config :tango, encryption_key:` comes from runtime secrets (32 raw bytes or base64 of 32 bytes), never committed. Rotating it makes every stored token and client secret unreadable.
- List every page origin in `config :tango, allowed_completion_origins: [...]` as an exact `scheme://host[:port]`: no trailing slash, path, or wildcard; `https` except `localhost`/`127.0.0.1`/`::1`. The callback posts nothing to an unlisted origin.
- In the opener page, accept a callback `message` only when `event.source` is the popup you opened, `event.origin` equals the origin serving `/callback`, and `intent_reference` matches the pending intent. The `TangoOAuth` hook does this; hand-written listeners must too.
- `state` is opaque and tenant-encoded: never build, parse, or log it. `redirect_uri` is bound at session creation and must equal, byte for byte, the URL registered with the provider; the direct flow's `exchange_code/4` must pass the same value.
- Verification and finalization are server-only. The verifier module and its options come from server code, never the browser. A verifier returns a stable subject and a small identity-claims allowlist, never tokens or raw payloads. Return `{:error, :network_error | :timeout | :temporarily_unavailable | :provider_unavailable}` for retryable failures; any other verifier error consumes the single-use completion handle.
- Run `Tango.multi_finalize_authorization/5` inside a Multi committed by the Repo in `config :tango, repo:`; any other Repo returns `{:error, :repo_mismatch}`. Link host records in the same Multi so the connection and app rows commit together.
- `mix tango.setup` is for the initial install only; its `down` drops every Tango table. Upgrade with a separate host migration pinning `Tango.Migration.up(version: N)` / `down(version: N - 1)`, applied before deploying code that needs it.
- Tango schedules nothing. Run `Tango.cleanup_expired_authorizations/0` before `Tango.cleanup_expired_sessions/0` from the host job runner.
- Report only real credential rejections (`401`, or a `403` whose body confirms an invalid/revoked token) with `Tango.record_auth_failure/3`. Do not blanket-report 403 scope, policy, or quota denials; repeated reports expire the connection.
- Do not invent Tango APIs. If a function is not in the installed `lib/tango/tango.ex` (or the module the reference names), say so instead of guessing.

$ARGUMENTS
