# Authorize, token, DCR, metadata, CORS, introspect

Replace `MyApp` / `MyAppWeb` with the detected names. Overlay the controllers
`/boruta bootstrap` generated; do not generate a second set.

## OauthCors

`lib/my_app_web/plugs/oauth_cors.ex` — discovery/DCR/token are public
browser-called endpoints. Echo an allowlisted Origin when present; `*` is
acceptable here (these routes are not the authenticated MCP resource).
Methods `GET, POST, OPTIONS`, headers `content-type, authorization`.
OPTIONS returns 200 and halts.

Router pipeline:

```elixir
pipeline :oauth_public do
  plug MyAppWeb.Plugs.OauthCors
end
```

## Metadata (RFC 9728 + RFC 8414)

`lib/my_app_web/controllers/oauth/metadata_controller.ex`

- `GET /.well-known/oauth-protected-resource/accounts/:account_slug/mcp`
  → `Oauth.protected_resource_metadata(slug)` for an **active** account;
  unknown slug → generic JSON 404
- `GET /.well-known/oauth-authorization-server` → `authorization_server_metadata/0`
- Also serve the path-inserted AS URL
  `/.well-known/oauth-authorization-server/accounts/:slug/mcp` and the
  suffix form `/accounts/:slug/mcp/.well-known/oauth-authorization-server`
  (Inspector probes both)
- OPTIONS on each of those paths

Mount under `pipe_through :oauth_public`.
`scopes_supported` is `mcp:read mcp:write mcp:admin`.

## Register (RFC 7591)

`POST /oauth/register` → `Oauth.register_dynamic_client(params, conn: conn)`.
201 + `client_registration_response/1`. 400
`invalid_client_metadata` / `invalid_redirect_uri`. 429 when rate limited.
OPTIONS 200.

## Authorize

Require, in order:

1. Logged-in user (Boruta `:unauthorized` → session `user_return_to` + login)
2. `Oauth.canonicalize_redirect_uri/1` and `canonicalize_scope/1`
3. If `conn.assigns.oauth_invalid_scope` → `invalid_scope` (do not keep
   supported members)
4. `response_type == "code"`
5. `code_challenge_method == "S256"`
6. `resource` resolves to an active account (`fetch_account_resource/1`)
7. User is a full member of that account; otherwise `invalid_target` (do not
   leak membership)
8. If `Oauth.unique_identity?(basis)` **and**
   `Consent.granted?(user, client_id, scopes, resource)` →
   `Boruta.Oauth.authorize/3`
9. Else `preauthorize` → store `authorize_param_keys` + original redirect +
   identity basis on the session → redirect `/oauth/consent`

On `authorize_success`, `TokenResource.stamp_value(response.code, resource)`
before redirecting. If stamp fails, delete the code and `invalid_request`.
Restore the ephemeral-port redirect with `Oauth.restore_redirect_url/2`.

## Token

1. Canonicalize loopback redirect (port-agnostic; query/fragment must match)
2. `resource` must be a valid account MCP URL
3. `authorization_code` → stamped code resource must equal `resource`
4. `refresh_token` → stamped refresh resource must equal `resource`
5. Else `invalid_target`
6. On success, `TokenResource.stamp_value(access_token, resource)`
7. JSON includes the granted `scope` string
8. Cache-Control `no-store`

Reject other grant types for this MCP client.

## Introspect / revoke

Keep Boruta-generated controllers. Active introspection JSON **must**
include `iss`, `scope`, `exp`, and `aud` set to the stamped account MCP
resource. Incomplete/unknown subjects and unbound tokens are
`{"active": false}`.
