# Mount Tango.API.Router

`Tango.API.Router` is a `Plug.Router` that serves the popup `/callback` page and a key-protected session API. Mount it whenever the popup authorization flow is used, because the provider redirect must land on its `/callback`.

## Mount

```elixir
# lib/my_app_web/router.ex
scope "/api/oauth" do
  pipe_through :api
  forward "/", Tango.API.Router
end
```

With this mount, the provider redirect URI is `https://app.example.com/api/oauth/callback`. Register exactly that URL with each provider and pass it as `redirect_uri` / `callback_url`.

## Endpoints

| Route                                   | Auth    | Purpose                                                                                                        |
|-----------------------------------------|---------|----------------------------------------------------------------------------------------------------------------|
| `GET /callback`                         | none    | Popup callback. Stages the code and posts only the completion handle to the session's exact completion origin. |
| `GET /health`                           | none    | Health check JSON.                                                                                             |
| `POST /sessions`                        | API key | Direct-flow session (`Tango.create_session/3`). Body: `provider` (required), `redirect_uri`, `scopes`.         |
| `GET /authorize/:session_token`         | API key | Authorization URL. Query: `redirect_uri` (required), `scopes`.                                                 |
| `POST /exchange`                        | API key | Direct-flow code exchange. Body: `state`, `code`, `redirect_uri`. Returns provider, status, scopes, expiry; never credentials. Rejects staged sessions. |

`/callback` responds with a strict CSP, `cache-control: no-store`, `referrer-policy: no-referrer`, and `x-content-type-options: nosniff`. Do not wrap it in a pipeline that rewrites those headers or injects scripts.

## API key and tenant

```elixir
# config/runtime.exs
config :tango, api_key: System.fetch_env!("TANGO_API_KEY")
```

Key-protected routes accept `Authorization: Bearer <key>` or `X-API-Key: <key>` and compare with `Plug.Crypto.secure_compare/2`. If `api_key` is unset, every protected route returns 401. A missing tenant returns 401 `tenant_id_required`.

The tenant comes from the `X-Tenant-ID` header, falling back to `conn.assigns.current_tenant_id`. **The header wins.** Consequences:

- Never embed `TANGO_API_KEY` or a hard-coded tenant in browser JavaScript.
- Call `/sessions`, `/authorize`, and `/exchange` from server code, or skip them and call `Tango.create_session/3` / `Tango.exchange_code/4` directly ([direct-flow.md](direct-flow.md)).
- If the router must be reachable from an authenticated host pipeline, strip any client-supplied `x-tenant-id` header and assign `current_tenant_id` from the server session before forwarding:

```elixir
defmodule MyAppWeb.Plugs.TangoTenant do
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    conn
    |> delete_req_header("x-tenant-id")
    |> assign(:current_tenant_id, conn.assigns.current_scope.tenant_id)
  end
end
```

Adjust the assign source to the host's auth model. The API key is still required on those routes.

## CORS

Same-origin use needs no CORS. For a separate front-end origin:

```elixir
config :tango, :api,
  cors_origins: ["https://app.example.com"],
  cors_methods: ["GET", "POST", "DELETE", "OPTIONS"],
  cors_max_age: 86_400,
  cors_credentials: false
```

`cors_headers` overrides the allowed request headers. Keep `cors_credentials: false` unless a cookie-authenticated pipeline in front of the router requires it.

## Server-side call example

```elixir
Req.post!("https://app.example.com/api/oauth/sessions",
  headers: [
    {"authorization", "Bearer " <> Application.fetch_env!(:tango, :api_key)},
    {"x-tenant-id", tenant_id}
  ],
  json: %{provider: "github", redirect_uri: redirect_uri, scopes: ["repo"]}
)
```

Inside the same Phoenix app, prefer the Elixir functions over HTTP calls to yourself.
