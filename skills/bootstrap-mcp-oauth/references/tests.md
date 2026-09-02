# Tests and clients

Replace `MyApp` / `MyAppWeb` with the detected names.

## MCPCase

Keep `/bootstrap-mcp` JSON-RPC helpers. Change the path to the account
MCP URL and add PKCE token exchange. Call
`MyApp.Oauth.Provisioning.provision/0` (or `ensure_local_client/0`) from
test setup — not from application boot.

```elixir
def mcp_path(%{slug: slug}), do: "/accounts/#{slug}/mcp"

def obtain_access_token(conn, user, opts \\ []) do
  account = Keyword.fetch!(opts, :account)
  scope = Keyword.get(opts, :scope, "mcp:read mcp:write mcp:admin")
  _ = MyApp.Oauth.Provisioning.ensure_local_client()
  {verifier, challenge} = pkce_pair()
  resource = MyApp.Oauth.account_mcp_url(account.slug)

  conn =
    conn
    |> recycle_if_sent()
    |> log_in_user(user)
    |> get("/oauth/authorize", %{
      "response_type" => "code",
      "client_id" => MyApp.Oauth.client_id(),
      "redirect_uri" => MyApp.Oauth.redirect_uri(),
      "code_challenge" => challenge,
      "code_challenge_method" => "S256",
      "scope" => scope,
      "resource" => resource
    })

  conn = maybe_allow_consent(conn)
  code = code_from_redirect(conn)

  conn =
    build_conn()
    |> put_req_header("content-type", "application/x-www-form-urlencoded")
    |> post("/oauth/token", %{
      "grant_type" => "authorization_code",
      "code" => code,
      "redirect_uri" => MyApp.Oauth.redirect_uri(),
      "client_id" => MyApp.Oauth.client_id(),
      "code_verifier" => verifier,
      "resource" => resource
    })

  json_response(conn, 200)["access_token"]
end
```

`maybe_allow_consent/1` — if redirected to `/oauth/consent`, LiveViewTest
click `#oauth-consent-allow`, then follow the authorize redirect.

`pkce_pair/0` — 32 random bytes, URL-safe verifier; S256 challenge
without padding.

Use the app's `log_in_user` helper from ConnCase.

## Required ConnTests

- Missing Bearer on POST `/accounts/:slug/mcp` → 401 `invalid_request` and
  `WWW-Authenticate` contains `resource_metadata=`
- Missing Bearer on GET → 401 (session id is not enough)
- Token issued for account A on account B's MCP URL → 401 `invalid_token`
- Token with no MCP scope → 403 `insufficient_scope` advertising all three
- Read token calling a write tool → 403 `mcp:write`; `tools/list` omits
  write tools
- Non-member / unknown slug → generic 404 (same body, no WWW-Authenticate)
- initialize → 200, `serverInfo.name` set, `mcp-session-id` issued
- `notifications/initialized` → 202 empty body
- `tools/list` with that session + token → 200
- mixed `scope=mcp:read not-a-scope` on authorize → `invalid_scope`
- DCR: oversize body, disallowed redirect, rate limit
- loopback redirect with a different query → mismatch
- Protected-resource metadata 200 for an active slug; 404 for unknown
- Introspect active token includes `aud` equal to the account MCP URL

`async: false` only if tests share global OAuth clients or rate-limit rows.

## Inspector

1. `mix phx.server`
2. MCP Inspector, transport **Streamable HTTP**
3. URL `http://localhost:4000/accounts/<slug>/mcp` (no Bearer — Inspector
   discovers OAuth from the 401 challenge)
4. Complete login + Allow
5. Echo `Mcp-Session-Id` after initialize
6. GET SSE still sends the Bearer token

Do not document API keys as the MCP credential after this overlay.
