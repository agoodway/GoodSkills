---
name: bootstrap-mcp
description: >
  Bootstrap a Streamable HTTP MCP server in a Phoenix app using ExMCP 1.1
  (https://github.com/azmaveth/ex_mcp). Use when the user says "bootstrap mcp",
  "/bootstrap-mcp", "add MCP", "MCP server", "ExMCP", "HttpPlug", or wants
  Claude/Inspector to call Phoenix tools over HTTP with Bearer auth.
---

# Bootstrap MCP Server for Phoenix

Add a production Streamable HTTP MCP endpoint with Hex ExMCP 1.1, Bearer
auth on every protected method, and the Phoenix/Bandit adapters proven in
goodviews.

Do **not** use Anubis. Do **not** use `use ExMCP.Server` / `deftool` (removed
fork DSL). Do **not** generate a thin Handler, RequestHandler, RequestContext,
AuthSessions, SSEHub, or a CorsPlug that intercepts notifications. Target
`{:ex_mcp, "~> 1.1.1"}` from [azmaveth/ex_mcp](https://github.com/azmaveth/ex_mcp).

## Prerequisites

- Phoenix 1.7+ (1.8 preferred) with PostgreSQL
- API keys already exist (`/bootstrap-api-keys` or `/bootstrap-openapi`):
  - `Accounts.verify_api_token/1` or `Accounts.authenticate_api_key/1`
  - An `ApiKey` with either `scopes` or `type` (`:public` / `:private`)
- Bandit (Phoenix default). Cowboy does not need the SSE stream-owner adapter.

## App Name Detection

Detect OTP app and modules from `mix.exs`. Replace `MyApp` / `my_app` /
`MyAppWeb` / `my_app_web` in every reference template.

## Architecture (required)

Copy this layout. A naive `forward "/mcp", ExMCP.HttpPlug, handler: MyServer`
looks simpler and fails under Inspector, Bandit SSE, Phoenix parsers, and
per-request auth.

```
lib/my_app/mcp_server.ex              # DSL tools; not in the supervisor
lib/my_app/mcp/transport.ex           # HttpPlug opts, handler_opts, principal/tenant
lib/my_app_web/mcp/auth_plug.ex       # Bearer, then VaryOrigin + HttpPlug/SSE
lib/my_app_web/mcp/vary_origin.ex     # Vary: Origin + expose session headers
lib/my_app_web/mcp/sse.ex             # Bandit-safe GET SSE owner loop
lib/my_app_web/mcp/sse_conn.ex        # chunk/2 on the request process
lib/my_app_web/mcp/error.ex           # JSON 401/403
lib/my_app_web/plugs/cache_body.ex    # stash complete raw body for HttpPlug
```

Request flow:

```
POST/GET/DELETE /mcp
  → Host allow-list (403 before auth)
  → AuthPlug (Bearer on GET, POST, DELETE; OPTIONS is credential-free)
  → assigns.mcp_api_key
  → VaryOrigin
  → ExMCP.HttpPlug (handler: MCPServer, handler_opts from assigns)
  → GET SSE: MCP.SSE chunks on the request process
  → MCPServer.init/1 state (temporary per-request GenServer)
```

### Why this shape

| Decision | Why |
|---|---|
| `handler: MCPServer`, not a thin Handler | ExMCP 1.1 starts atom handlers as temporary request-local GenServers. A module without `start_link/1` is no longer a valid direct-dispatch trick. |
| Identity in `handler_opts` → `init/1` state | Tools read `state.api_key`. Process-dictionary identity is invisible to the handler GenServer. |
| `principal_id` / `tenant_id` callbacks | Native sessions bind to the authenticated subject. A session header is an extra binding, never a substitute credential. |
| `CacheBody` concatenates `{:more, chunk}` | Phoenix consumes the adapter body; HttpPlug reads `assigns[:raw_body]`. The last chunk alone is not the document. |
| No `:api` / `accepts ["json"]` pipeline | SSE uses `Accept: text/event-stream`. POST requires `application/json`. |
| Native CORS + `VaryOrigin` | ExMCP validates Origin and echoes an allowlisted value. It does not set `Vary: Origin` or expose `mcp-session-id`. Never `Access-Control-Allow-Origin: *` on authenticated MCP. |
| Bandit-safe SSE wrapper | `ExMCP.HttpPlug.SSEHandler` still owns the session; the app only `chunk/2`s on the stream owner. |
| `protocol_mode: :legacy_only` | Production default until clients are proven. `:prefer_modern` is a runtime canary, not the scaffold default. |
| Compile-time `tool` DSL | Tools exist even when a client skips the handshake. |
| Bearer on GET | EventSource-without-Authorization is not supported. Disable GET SSE rather than weaken auth. |

## Phase 0: Discovery

Before writing files, record:

1. App modules from `mix.exs`
2. Existing MCP (`Grep("ExMCP|Anubis|/mcp")`) — adapt, do not duplicate
3. API key verify function and whether keys have `scopes` or `type`
4. Endpoint `Plug.Parsers` options
5. Whether `accounts` exist (optional tenant on handler state)

Present:

```
Existing: …
Missing: …
Auth: verify_api_token | authenticate_api_key; scopes | public/private
```

Ask before overwriting an existing MCP stack.

## Implementation Order

Execute in this order. Read the linked file before writing those modules.

### Phase 1: Dependency
Read [references/integration.md](references/integration.md)

1. Add `{:ex_mcp, "~> 1.1.1"}` and `mix deps.get`
2. Confirm `:ex_mcp` starts (Hex application). Do **not** call
   `ExMCP.HttpPlug.start_link/1`. Do **not** start `MCPServer`.

### Phase 2: Parsers + transport
Read [references/http.md](references/http.md) (CacheBody) and
[references/integration.md](references/integration.md) (Transport, config).

3. `CacheBody` body_reader on the endpoint parsers (concatenate every chunk)
4. `MyApp.MCP.Transport` (`plug_opts/0`, `handler_opts/1`, principal/tenant)
5. `:mcp` and `:mcp_allowed_hosts` config (`:legacy_only`, Origin allowlist)

### Phase 3: Server + HTTP
Read [references/server.md](references/server.md) then the plug templates in
[references/http.md](references/http.md)

6. `MyApp.MCPServer` with DSL tools (`ping`, `example_list`, `example_get`,
   `example_create`). Identity from `init/1` state. Customize example tools
   to a real context.
7. `Error`, `VaryOrigin`, `SSEConn`, `SSE`, `AuthPlug`

### Phase 4: Router
Read [references/integration.md](references/integration.md)

8. `:mcp` pipeline (host allow-list only — no `:api`)
9. `GET/POST/DELETE/OPTIONS /mcp` → `AuthPlug` **outside** `dev_routes`
10. `mcp_allowed_hosts` includes `www.example.com` in test

### Phase 5: Tests + clients
Read [references/tests.md](references/tests.md)

11. `MCPCase` + ConnTest handshake (initialize, notify 202, tools/list, ping)
12. Point Claude CLI / Inspector at `/mcp` with the API key **and** Bearer
    on every method, including GET SSE

## Adding a tool later

In `MCPServer`:

```elixir
tool "my_tool", "One-line description the model sees" do
  title("My Tool")

  input_schema(%{
    type: "object",
    properties: %{id: %{type: "string"}},
    required: ["id"],
    additionalProperties: false
  })

  run(fn args, state ->
    MyApp.MCPServer.with_scope("my_domain:read", state, fn _api_key ->
      id = arg(args, :id)
      {:ok, %{content: [json(%{ok: true, id: id})]}, state}
    end)
  end)
end
```

Register nothing else. Compile-time `tool` is the registration. Let ExMCP
emit `InitializeResult` — do not special-case `initialize`.

## Scope names

`domain:action` — `examples:read`, `examples:write`, `examples:delete`.

If `ApiKey` has no `scopes`, map `:public` → read, `:private` → read+write.

## Production

- HTTPS only. `mcp_allowed_hosts` is the public host(s) only.
- Keep `protocol_mode: :legacy_only` until Inspector/Claude/Cursor (and any
  advertised client) complete a handshake against the deployed endpoint.
  Flip to `:prefer_modern` as a **runtime** canary (`MCP_PROTOCOL_MODE`), not
  in the same change that scaffolds the handler.
- ExMCP sessions and SSE streams are **node-local**. Launch with one
  MCP-serving instance. Do not describe ETS/Registry/DNSCluster as a shared
  session store. Horizontal scale needs a later affinity or distributed-store
  design.
- Reverse proxies: `x-accel-buffering: no` is already on the SSE path.
- Log tool name + `api_key.id` (or user/account ids), result class, protocol
  version. Never log access tokens, API keys, raw `mcp-session-id`, or
  unrestricted tool arguments.
- Do not put `/mcp` behind `dev_routes`.

The goodviews runbook is the production reference for topology, canary
gates, and telemetry: `app/docs/mcp-production-runbook.md`. Copy the
constraints, not the PageFoo module names.

## Troubleshooting

Read [references/troubleshooting.md](references/troubleshooting.md) when a
client fails handshake, returns 404 in prod, hangs on SSE, gets Origin 403,
or tools see no API key.

## Checklist

- [ ] `{:ex_mcp, "~> 1.1.1"}` in mix.exs (not `anubis_mcp`, not `fire/ex-mcp`)
- [ ] `CacheBody` concatenates `{:more, chunk}` on endpoint parsers
- [ ] `MCP.Transport` builds HttpPlug opts; MCPServer **not** in the supervisor
- [ ] `MCPServer.init/1` copies `handler_opts` into state; tools read state
- [ ] `AuthPlug` → `VaryOrigin` → `HttpPlug` / Bandit SSE wrapper
- [ ] Bearer required on GET, POST, DELETE; OPTIONS credential-free
- [ ] `/mcp` GET/POST/DELETE/OPTIONS outside `dev_routes` and outside `:api`
- [ ] Host allow-list 403 + `allowed_origins` (no wildcard on authenticated MCP)
- [ ] `protocol_mode: :legacy_only`, `legacy_http_sse: true`
- [ ] ConnTest: initialize, notify 202, tools/list, ping, missing Bearer 401
- [ ] Claude CLI or Inspector pointed at `/mcp` with a Bearer key

OAuth 2.1 + PKCE for Inspector/Claude (account-scoped resource, DCR, consent):
`/bootstrap-mcp-oauth`.
