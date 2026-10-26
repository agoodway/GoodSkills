---
name: tango
description: "Use when installing, configuring, upgrading, testing, or debugging Tango OAuth connections or one-time external identity proofs in Elixir/Phoenix, including refresh failures, tenant-scoped connection info, generation locks, or /tango requests. Not for user sign-in or OAuth servers."
---

# Tango

Tango stores per-tenant OAuth connections in the host Ecto repo. On verified 0.4.1 source with revised V04, staged consume mode can instead commit a one-time identity proof with host writes and erase the candidate credentials without creating a connection. Some releases require a new schema version before their code runs; [references/upgrading.md](references/upgrading.md) maps each release to its schema.

Inspect `mix.exs`, `mix.lock`, the resolved Tango source, and the schema marker before writing code. A local version string does not prove Hex publication; path dependencies have no Hex lock entry. Use the installed implementation when docs disagree, and do not write calls the installed release lacks.

## Route the request

Read only the references needed for the request:

| Request                                           | Reference                                                                                                         |
| ------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| Install, configure, first migration               | [references/bootstrap.md](references/bootstrap.md)                                                                |
| Providers: catalog, custom, request options       | [references/providers.md](references/providers.md)                                                                |
| Server-side redirect flow (no popup)              | [references/direct-flow.md](references/direct-flow.md)                                                            |
| Popup completion, verifier, finalize, cleanup     | [references/authorization.md](references/authorization.md)                                                        |
| One-time account link or organization admin proof | [references/consumption.md](references/consumption.md)                                                            |
| Mount the HTTP router, CORS, API key              | [references/api.md](references/api.md)                                                                            |
| LiveView connect button                           | [references/liveview.md](references/liveview.md), then [references/authorization.md](references/authorization.md) |
| Use, refresh, revoke, report auth failures        | [references/connections.md](references/connections.md)                                                            |
| Classify refresh errors, backoff, safe reporting  | [references/refresh-errors.md](references/refresh-errors.md)                                                      |
| Consumer test fixtures                            | [references/testing.md](references/testing.md)                                                                    |
| Upgrade, schema migration, rollback               | [references/upgrading.md](references/upgrading.md)                                                                |
| Debug errors                                      | [references/debug.md](references/debug.md)                                                                        |

For `/tango help` or an unknown/missing subcommand, list: `bootstrap`, `providers`, `flow`, `authorization`, `consume`, `api`, `liveview`, `connections`, `testing`, `upgrade`, `debug`, and `help`. `flow` maps to [references/direct-flow.md](references/direct-flow.md); `consume` maps to [references/consumption.md](references/consumption.md).

## Safety boundaries

- Take tenant ids from the authenticated server session, never browser input. Locking does not authorize access. Tenant ids match `^[a-zA-Z0-9_-]+$`, at most 255 bytes.
- Keep credentials server-side. Do not log loaded connection/authorization structs, provider bodies, codes, raw state, completion handles, or credential-bearing changesets. Persist connection ids and selected identity fields in host records; fetch tokens only for provider calls.
- Use connection-info reads for status/identity and `Tango.Testing` for ordinary test inserts. Host token writes bypass Tango's query/telemetry redaction.
- Use `RefreshError.classify/1` for decisions and `to_storage/1` for reporting. Outages and database failures do not prove revoked consent. Only genuine resource API credential rejections belong in `record_auth_failure/3`.
- Keep encryption/API keys in runtime secrets. Key rotation makes stored credentials unreadable. Never give the browser `TANGO_API_KEY`: the HTTP router trusts its caller's tenant header.
- For popup work, follow [authorization.md](references/authorization.md): exact allowed origins, popup source/origin/intent checks, server-owned verifier, tenant-scoped completion, and finalization or consumption on Tango's configured Repo. One-time proofs use `Tango.Authorization.multi_consume_authorization/5`; ordinary connections keep their existing lifecycle. Direct and staged sessions are not interchangeable.
- `mix tango.setup` is initial installation only. An upgrade that advances the schema needs a pinned host migration applied before the new code serves traffic. Tango schedules nothing; host cleanup runs authorizations before sessions.
- Verify APIs against installed source. Preserve the requested dependency source and distinguish local validation from published adoption. See [upgrading.md](references/upgrading.md) before release/dependency changes.

$ARGUMENTS
