# MCP auth overlay

Keep `VaryOrigin`, `SSE`, `SSEConn`, `CacheBody`, `MCP.Transport`, and
`MCPServer` as the HttpPlug handler from `/bootstrap-mcp`. Replace API-key
identity with OAuth.

Replace `MyApp` / `MyAppWeb` with the detected names.

## Identity

`handler_opts` already pass assigns into `MCPServer.init/1`. AuthPlug
assigns:

```elixir
assign(conn, :mcp_user, user)
assign(conn, :mcp_account, account)
assign(conn, :mcp_scopes, granted_mcp_scopes)
```

Delete `RequestContext`, `AuthSessions`, and `SSEHub` if they are still
present. Tools must not take `account_id` — the route account is the tenant.

`Transport.principal_id/1` is the user id. `Transport.tenant_id/1` is the
account id. Native sessions bind to that pair.

## Authorization policy

`lib/my_app/mcp/authorization.ex` — one map of public tool name → exactly
one of `mcp:read`, `mcp:write`, `mcp:admin`. Admin does not imply read or
write.

- `initialize`, `tools/list`, notifications, session listen: any one granted
  MCP scope (none → 403 advertising all three)
- `resources/*`: `mcp:read`
- `tools/call`: the mapped tool scope; calling a filtered tool still 403s
  with that tool's scope
- `scope_mapper/1` returns a scope list or `:error`. Never `nil` (Hex would
  fall through to `mcp:tools:*`)

Inventory test: every frozen tool name has a mapping; every mapping names a
tool.

Filter `tools/list` in AuthPlug `register_before_send` (or in
`handle_list_tools/2`) so hidden tools are omitted. Handler still enforces
the same policy before mutation.

Example `example_*` mapping: `ping`/`example_list`/`example_get` →
`mcp:read`; `example_create` → `mcp:write`. Replace `with_scope("examples:…")`
that reads API key scopes.

## LoadAccount

`lib/my_app_web/mcp/load_account.ex` — resolve `account_slug` to an active
account, assign `:mcp_account`. Unknown/suspended → `Error.not_found/1`
(generic JSON 404). Run this **before** AuthPlug.

## Error

401/403 JSON `{error, error_description}` plus:

```
WWW-Authenticate: Bearer realm="my_app", error="…", error_description="…",
  resource_metadata="<issuer>/.well-known/oauth-protected-resource/accounts/<slug>/mcp",
  scope="mcp:write"
```

`scope=` is the exact missing scope(s), not `mcp:tools`.
`not_found/1` does **not** include `WWW-Authenticate`.
Add `Error.insufficient_scope/2`. Keep echoing an allowlisted Origin
(from `/bootstrap-mcp`); never `*`.

## OauthAdapter

`lib/my_app/mcp/oauth_adapter.ex` — request-scoped HttpPlug OAuth options.

Hex `oauth_enabled: true` only when `Oauth.https_issuer?/0`. Then set
`resource` to **this** account MCP URL, `authorization_servers: [issuer()]`,
`scopes_supported: Authorization.scopes()`, `scope_mapper`, and
`auth_config` pointing at `/oauth/introspect` with the confidential client.

HTTP localhost: `oauth_enabled: false`. AuthPlug still enforces scopes so
step-up is testable without giving `HttpPlug.init/1` an HTTP resource URL.

`ExMCP.HttpPlug.init/1` stores one resource. Always `init` per request
from the current `conn.assigns.mcp_account`.

## AuthPlug

Replace API-key verification. Phoenix cookies are ignored.

| Method | Auth |
|---|---|
| OPTIONS | VaryOrigin + HttpPlug (no Bearer; Host/Origin still run) |
| GET / POST / DELETE | Bearer access token + resource + MCP scope + membership |

GET SSE uses the `/bootstrap-mcp` Bandit wrapper **after** Bearer succeeds.
A session header is an extra native-session binding, never a replacement.

POST/DELETE/GET pipeline:

1. Extract `Bearer` token
2. `Boruta.Oauth.Authorization.AccessToken.authorize(value: token)`
3. `TokenResource.matches_value?(token, Oauth.account_mcp_url(slug))`
   — mismatch is `invalid_token`, not 404
4. Granted scopes include at least one of `mcp:read`/`mcp:write`/`mcp:admin`
   — else 403 advertising all three
5. Tool/resource methods need their mapped scope — else 403 with that scope
6. `sub` is a current user; full member of `conn.assigns.mcp_account`
   — non-member is generic 404
7. Assign user, account, scopes; `VaryOrigin`; Accept check; HttpPlug / SSE

On HTTPS issuers, optionally introspect again so Hex can emit a standards
`insufficient_scope` challenge. Timeouts and non-JSON become generic
`invalid_token` — do not echo upstream bodies.

## Router

Do not `pipe_through :api`.

```elixir
pipeline :mcp do
  plug :mcp_dns_rebinding
  plug MyAppWeb.MCP.LoadAccount
end

scope "/accounts/:account_slug" do
  pipe_through :mcp

  get "/mcp", MyAppWeb.MCP.AuthPlug, []
  post "/mcp", MyAppWeb.MCP.AuthPlug, []
  delete "/mcp", MyAppWeb.MCP.AuthPlug, []
  options "/mcp", MyAppWeb.MCP.AuthPlug, []
end
```

Remove the old `/mcp` routes from `/bootstrap-mcp`. Keep the host allow-list.
Empty plug opts; `OauthAdapter.plug_opts(conn)` merges onto
`Transport.plug_opts/0` per request.

## Tools

```elixir
case state do
  %{account: %{id: _} = account, user: user} -> # query scoped to account.id
  _ -> {:error, "Authentication required", state}
end
```

Reject an `account_id` argument if present. Visibility/not-found stays
generic.
