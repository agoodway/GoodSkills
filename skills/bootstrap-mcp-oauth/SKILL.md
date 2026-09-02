---
name: bootstrap-mcp-oauth
description: >
  Overlay OAuth 2.1 + PKCE on a Phoenix ExMCP 1.1 server (account-scoped
  resource, RFC 9728 metadata, DCR, consent, token-resource binding). Use when
  the user says "bootstrap mcp oauth", "/bootstrap-mcp-oauth", "MCP OAuth",
  "Inspector OAuth", "mcp:read", "protected resource metadata", or wants
  Claude/Inspector to authenticate to /accounts/:slug/mcp without API keys.
---

# Bootstrap MCP OAuth

Replace API-key MCP auth with the goodviews OAuth 2.1 + PKCE stack: the token
is bound to **one account MCP URL**, Inspector discovers the authorization
server from RFC 9728 metadata, and GET still requires Bearer.

This skill does **not** scaffold ExMCP HTTP or a generic OAuth provider.
Those are `/bootstrap-mcp` and `/boruta bootstrap`.

Keep Cors-less native ExMCP transport, `VaryOrigin`, `CacheBody`, and the
Bandit SSE wrapper from `/bootstrap-mcp`. Overlay auth, routes, and identity.

## Prerequisites

Verify before writing files:

1. `/bootstrap-mcp` HTTP stack exists: `AuthPlug`, `VaryOrigin`, `SSE`,
   `SSEConn`, `CacheBody`, `MCP.Transport`, `MCPServer` as the HttpPlug handler
2. `/boruta bootstrap` (or equivalent): `Boruta.Oauth`, token/authorize
   controllers, `ResourceOwners`
3. `/bootstrap-accounts`: `accounts.slug`, membership, active-account lookup
4. `phx.gen.auth` session login

If any of these are missing, run that skill first and stop.

If the app still has `RequestContext`, `AuthSessions`, `SSEHub`, a thin
`Handler`/`RequestHandler`, or a CorsPlug that intercepts notifications,
finish the `/bootstrap-mcp` 1.1 rewrite first.

## App Name Detection

Detect OTP app and modules from `mix.exs`. Replace `MyApp` / `my_app` /
`MyAppWeb` / `my_app_web` in every reference template.

## What changes

```
GET  /.well-known/oauth-protected-resource/accounts/:slug/mcp
GET  /.well-known/oauth-authorization-server
POST /oauth/register
GET  /oauth/authorize          # login → consent → code (PKCE S256)
POST /oauth/token              # code/refresh; resource must match
GET|POST|DELETE|OPTIONS /accounts/:slug/mcp
```

```
Inspector
  → 401 + WWW-Authenticate resource_metadata=…
  → GET protected-resource metadata
  → DCR (loopback PKCE client)
  → authorize + consent
  → token (resource = account MCP URL)
  → GET/POST /accounts/:slug/mcp  Authorization: Bearer
```

| Rule | Why |
|---|---|
| Resource = `issuer/accounts/:slug/mcp` | RFC 8707. A token for account A cannot call account B. |
| Scopes `mcp:read` `mcp:write` `mcp:admin` | Independent least privilege. Admin does not imply read or write. |
| PKCE S256 only | Public MCP clients (Inspector, Claude, Cursor). |
| Cookies never accepted on `/mcp` | EventSource cannot send Bearer; GET still requires Bearer plus a native session. |
| Guests / strangers → generic 404 | Do not leak whether the account exists. |
| Consent remembered only for unique client identity | Shared loopback client always re-prompts. |
| Hex `oauth_enabled` only on HTTPS issuers | 1.1.1 `HttpPlug.init/1` requires absolute HTTPS `:resource`. HTTP localhost keeps step-up in AuthPlug. |

## Phase 0: Discovery

Record:

1. App modules, issuer host, login path
2. Existing `/mcp` route and `AuthPlug` (API key vs already OAuth)
3. Boruta controllers and `ResourceOwners` module
4. Account lookup (`get_active_account_by_slug/1` or equivalent)
5. Membership check (`full_member?` / role in `owner|admin|member`)
6. Whether `oauth_tokens` already has `resource`

Present `Existing` / `Missing` / `Account lookup`. Ask before replacing a
working OAuth MCP stack.

## Implementation Order

Execute in this order. Read the linked file before writing those modules.

### Phase 1: Config + data
Read [references/oauth-core.md](references/oauth-core.md)

1. `:my_app, :oauth` config (issuer, seeded public client, three MCP scopes,
   DCR allowlist + limits)
2. Migration: `oauth_tokens.resource` (nullable), `oauth_consents` unique on
   `[:user_id, :client_id, :resource]`, `oauth_rate_limits`
3. `MyApp.Oauth.TokenResource` and `MyApp.Oauth.Consent`
4. `MyApp.Oauth` (URLs, metadata, DCR, resource validation, strict
   `parse_scope/1`)
5. `MyApp.Oauth.Provisioning` — idempotent scopes + optional local client.
   Call it from a **release task or test setup**, not `Application.start/2`

### Phase 2: Authorization server
Read [references/endpoints.md](references/endpoints.md)

6. Overlay Boruta authorize: require `response_type=code`,
   `code_challenge_method=S256`, valid `resource`, full membership, then
   consent or `authorize`. Remembered consent only when
   `Oauth.unique_identity?/1`
7. Overlay token: reject when `resource` does not match the stamped code/refresh
8. `POST /oauth/register` (RFC 7591, exact vendor redirects, loopback except
   port, rate limits, body limit)
9. RFC 9728 + RFC 8414 metadata (path-inserted and root)
10. Introspect JSON includes `iss`, `scope`, `exp`, `aud` = bound resource
11. `OauthCors` on discovery, DCR, and token

### Phase 3: Consent
Read [references/consent.md](references/consent.md)

12. `Oauth.ConsentLive` at `/oauth/consent` (not an account picker — the
    `resource` query already selected the account)

### Phase 4: MCP overlay
Read [references/mcp-auth.md](references/mcp-auth.md)

13. `LoadAccount` plug (unknown slug → generic 404)
14. Rewrite `AuthPlug`: Bearer access token on GET/POST/DELETE, resource
    match, at least one MCP scope, membership; GET SSE still uses the
    Bandit wrapper after Bearer
15. `MCP.Authorization` tool-to-scope policy; filter `tools/list`
16. `MCP.OauthAdapter` — per-request Hex OAuth opts (HTTPS only)
17. `RequestContext` is gone — `handler_opts` pass user+account+scopes
18. `Error` `WWW-Authenticate` includes `resource_metadata` and the exact
    missing scope(s)
19. Move routes from `/mcp` to `/accounts/:account_slug/mcp`
20. Tools read `state.account` / `state.user` (no `account_id` arg)

### Phase 5: Tests + clients
Read [references/tests.md](references/tests.md)

21. `MCPCase.obtain_access_token/3` (authorize + consent Allow + PKCE)
22. ConnTest: 401 challenge, GET without Bearer, wrong-account token,
    missing scope, initialize, notify 202
23. Point Inspector at `http://localhost:4000/accounts/<slug>/mcp`

## Production

Same transport constraints as `/bootstrap-mcp` (one MCP-serving node,
`:legacy_only` until clients are proven, privacy-safe logs). Plus:

- Issuer and MCP URLs must be HTTPS in production
- DCR allowlist is exact URIs (plus loopback HTTP). Do not allow `*` or
  prefix matches
- Stamp `resource` on every code and access token; never skip the match
- Provision scopes/clients through `mix`/release, not application boot
- Shared loopback client is **dev/test only** (`provision_local_client: true`
  in those envs). Production startup must not create it
- Log `sub` + account slug, not access tokens

See goodviews `app/docs/mcp-production-runbook.md` for topology, canary
gates, and DCR rate-limit alerts.

## Troubleshooting

Read [references/troubleshooting.md](references/troubleshooting.md) when
Inspector cannot discover OAuth, tokens work on the wrong account, GET SSE
is 401, or a write tool is hidden from `tools/list`.

## Checklist

- [ ] `/bootstrap-mcp` 1.1 stack, `/boruta bootstrap`, `/bootstrap-accounts` in place
- [ ] `oauth_tokens.resource` + `oauth_consents` unique on user+client+resource
- [ ] RFC 9728 + RFC 8414 metadata routes
- [ ] DCR allowlist + loopback HTTP except port; PKCE S256 required
- [ ] Authorize stamps the code; token stamps the access token; both match `resource`
- [ ] Consent LiveView `#oauth-consent-allow` / `#oauth-consent-deny`; loopback never remembered
- [ ] `/accounts/:slug/mcp` (old `/mcp` removed)
- [ ] AuthPlug: Bearer on GET/POST/DELETE + resource + MCP scopes + membership
- [ ] `handler_opts` is user+account+scopes; tools do not take `account_id`
- [ ] `mcp:read` / `mcp:write` / `mcp:admin`; no production `mcp:tools`
- [ ] Provisioning outside `Application.start/2`
- [ ] ConnTest: 401 challenge, GET Bearer, wrong-account token, initialize
- [ ] Inspector Streamable HTTP against `/accounts/<slug>/mcp`
