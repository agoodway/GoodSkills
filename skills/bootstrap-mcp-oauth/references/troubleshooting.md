# MCP OAuth troubleshooting

## Inspector never shows a login

401 is missing `WWW-Authenticate` `resource_metadata=`. `Error.unauthorized/3`
must include the RFC 9728 URL for that slug. GET without Bearer must 401,
not 404.

## Metadata 404

Protected-resource path is
`/.well-known/oauth-protected-resource/accounts/:slug/mcp` (path-inserted).
Unknown or suspended slugs 404 on purpose.

## DCR `invalid_redirect_uri`

Inspector uses loopback HTTP (`http://127.0.0.1:<ephemeral>/callback`).
`allowed_redirect_uri?/1` must accept loopback HTTP with no fragment.
Vendor HTTPS callbacks are **exact** allowlist matches only (no ChatGPT
path prefix). Query and fragment must match the registered URI; only the
loopback port may differ.

## Authorize `invalid_target`

`resource` must be the **exact** `account_mcp_url(slug)` (issuer +
`/accounts/:slug/mcp`). Trailing slashes and HTTP/HTTPS mismatches fail.
The user must be a full member of that account.

## Authorize `invalid_scope`

A non-empty `scope` mixed supported and unsupported values. Defaults apply
only when `scope` is absent or empty. Do not silently drop unknowns.

## Token works on the wrong account

`oauth_tokens.resource` was not stamped, or AuthPlug skipped
`TokenResource.matches_value?/2`. Stamp the authorization **code** and the
access token. Match on every GET/POST/DELETE.

## Consent loops

`preauthorize_success` must persist `resource` on the session. Allow must
redirect back to `/oauth/authorize` with the same query so
`Consent.granted?` is true **and** the client has unique identity.
Shared loopback clients always re-prompt — that is required, not a bug.

## GET SSE 401

GET requires `Authorization: Bearer` plus a native session owned by that
user+account. EventSource-without-Authorization is unsupported.

## Write tool missing from `tools/list`

The token lacks `mcp:write`. Filtered discovery is required. Calling the
tool by name still returns 403 `insufficient_scope` with `scope="mcp:write"`.

## Hex `oauth_enabled` 500 on localhost

`HttpPlug.init/1` requires absolute HTTPS `:resource`. Keep
`oauth_enabled: false` for HTTP issuers and enforce scopes in AuthPlug.
Enable Hex OAuth only when `Oauth.https_issuer?/0`.

## Application boot races / overwrites OAuth clients

`ensure_local_client!()` ran from `Application.start/2`. Move it to
`Oauth.Provisioning` and a release task. Tests provision explicitly.

## `/mcp` still mounted at the root

Inspector must hit `/accounts/:slug/mcp`. Remove the unscoped `/mcp`
routes from `/bootstrap-mcp`.

## Tools still check API keys

`/bootstrap-mcp-oauth` replaced API-key identity. `handler_opts` holds
user+account+scopes. Remove `with_scope("examples:read", …)` that reads
`api_key.scopes`.
