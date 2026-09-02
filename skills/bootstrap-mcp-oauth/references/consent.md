# Consent LiveView

`/oauth/consent` is **not** an account picker. The authorize `resource`
already selected the account. The page asks: allow this client to use MCP
on **this** account?

`lib/my_app_web/live/oauth/consent_live.ex`

## Mount

Read `session["oauth_authorize_params"]`,
`session["oauth_original_redirect_uri"]`, and
`session["oauth_identity_basis"]`.

Redirect to login if no user. Redirect home when `client_id` is missing,
the client is unknown, the resource is not an active account, or the user
is not a full member.

Assign: client name, account name, `Oauth.account_mcp_url(slug)`, requested
scopes (`mcp:read` / `mcp:write` / `mcp:admin`), redirect hostname,
`loopback_only?` (every registered redirect is loopback HTTP).

## Allow

Re-check membership + `Oauth.valid_resource?/1`. Then
`Consent.grant!(user, client_id, scopes, resource, basis)` and redirect to
`/oauth/authorize?` + the stored query (put original redirect_uri back if
the loopback port was rewritten).

`grant!` may store the grant. Authorize still ignores remembered consent
when `unique_identity?` is false, so a shared loopback client re-prompts
every time.

## Deny

If `redirect_uri` is allowlisted, redirect there with `error=access_denied`
(keep `state`). Otherwise redirect home.

## UI

Show: signed-in identity, account name, MCP destination URL, requested
scopes, redirect hostname, a warning when the client is loopback-only.
Buttons `#oauth-consent-allow` and `#oauth-consent-deny` — tests click those
ids.

Use the existing app layout/components. Do not invent a second design system.

## Router

Inside the authenticated browser `live_session`:

```elixir
live "/oauth/consent", Oauth.ConsentLive, :show
```
