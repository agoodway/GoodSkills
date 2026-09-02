# MCP troubleshooting

## Production 404 on `/mcp`

The route is inside the `dev_routes` block, which compiles away in prod.
Move `get/post/delete/options "/mcp"` outside that `if`.

## Production 500 / missing SessionManager

Do not start `MCPServer`. Do not call `ExMCP.HttpPlug.start_link/1`. The
`:ex_mcp` application owns the session registry. If SessionManager is
missing, `:ex_mcp` is not in the supervision tree — check `mix.exs` deps
and that the app starts Hex applications.

## Connection hangs (Fly.io / nginx)

Reverse proxies buffer SSE. The SSE wrapper already sets
`x-accel-buffering: no` and `cache-control: no-cache`. Confirm the proxy
does not override them.

## Bandit: `Adapter functions must be called by stream owner`

GET SSE went through `ExMCP.HttpPlug.SSEHandler` without `SSEConn` routing
chunks to the request process. Serve GET SSE from `MyAppWeb.MCP.SSE` and
set `conn_module: SSEConn`.

## Tools see no API key / "Authentication required"

`MCPServer.init/1` did not copy `handler_opts`. AuthPlug must assign
`:mcp_api_key` before `HttpPlug`. Tools read `state.api_key`, not
`Process.get`. Do not generate `RequestContext`.

## Notification is 200 with a body, or mints a session

A JSON-RPC notify has no `id`. ExMCP returns HTTP 202 with an empty body
and must not create a session. Delete any CorsPlug that intercepts
notifications or generates `mcp-session-id`.

## Phoenix parsers emptied the body / truncated JSON-RPC

Missing `CacheBody`, or `CacheBody` only stashed the final `{:ok, body}`
and dropped `{:more, chunk}` fragments. HttpPlug then sees `""` or a
suffix. Concatenate every chunk and cap with `body_limit`.

## Origin 403

The request `Origin` is not in `:mcp.allowed_origins`. CLI clients omit
Origin and must still succeed. Browser Inspector needs its origin
allowlisted (often `http://localhost:6274`). Do not use `*`.

## 406 Not Acceptable

POST needs `Accept: application/json` (Inspector sends
`application/json, text/event-stream`). GET SSE needs
`Accept: text/event-stream`.

## GET SSE is 401

GET requires `Authorization: Bearer`. A session id is not enough.
EventSource-without-Authorization is unsupported — use a header-capable
client or modern POST-owned streaming.

## Session 400 / 404 JSON-RPC

Missing/malformed/oversized session id → HTTP 400 JSON-RPC.
Unknown/expired/identity-mismatched session → HTTP 404 JSON-RPC.
Only missing/invalid Bearer is HTTP 401.

## 403 Invalid Host header

ConnTest host is `www.example.com`. Add it to `:mcp_allowed_hosts` in
`config/test.exs`. In prod, list only the real hosts.

## `/mcp` inside `:api` pipeline

`accepts ["json"]` rejects `Accept: text/event-stream`. Use the `:mcp`
pipeline from [integration.md](integration.md).

## Anubis leftovers

If the app still has `anubis_mcp`, `Anubis.Server`, or `session_store`
config, remove them; they fight ExMCP for `/mcp`.

## Fork leftovers

Delete `MCP.Handler`, `MCP.RequestHandler`, `MCP.RequestContext`,
`MCP.AuthSessions`, `MCP.SSEHub`, and any CorsPlug that mints sessions.
Hex 1.1 starts atom handlers as GenServers; the thin-handler dispatch
trick is invalid.
