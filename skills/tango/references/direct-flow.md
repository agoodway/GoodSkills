# Direct server-side flow

Use this when the host app receives the provider redirect itself: a full-page redirect to the provider and back to a host controller. For a popup connect button, use [authorization.md](authorization.md) instead. Sessions from `Tango.create_authorization_session/3` cannot be completed here, and sessions from `Tango.create_session/3` cannot be completed by the popup `/callback`.

## Flow

```
1. Tango.create_session(provider, tenant_id, redirect_uri:, scopes:)
2. Tango.authorize_url(session.session_token, redirect_uri:)   -> redirect the browser
3. Provider redirects to redirect_uri with ?state=...&code=...
4. Tango.exchange_code(state, code, tenant_id, redirect_uri:)  -> encrypted connection
```

Tango generates CSRF state (tenant-encoded and checked on exchange) and a PKCE challenge unless the provider's catalog metadata sets `disable_pkce`. The `redirect_uri` passed to `exchange_code/4` must equal the one bound in steps 1–2 and registered with the provider.

## Arity

`Tango.exchange_code/4` takes the tenant as the third argument; there is no `exchange_code/3`:

```elixir
Tango.exchange_code(state, code, tenant_id, redirect_uri: redirect_uri)
```

## Phoenix controller

Read the tenant from the authenticated connection, not from params. Replace `current_tenant_id/1` with however the host app resolves it.

```elixir
defmodule MyAppWeb.IntegrationController do
  use MyAppWeb, :controller

  @provider "github"
  @scopes ["user:email", "repo"]

  def connect(conn, _params) do
    tenant_id = current_tenant_id(conn)
    redirect_uri = url(~p"/integrations/github/callback")

    with {:ok, session} <-
           Tango.create_session(@provider, tenant_id,
             redirect_uri: redirect_uri,
             scopes: @scopes
           ),
         {:ok, auth_url} <-
           Tango.authorize_url(session.session_token, redirect_uri: redirect_uri) do
      redirect(conn, external: auth_url)
    else
      {:error, _reason} ->
        conn
        |> put_flash(:error, "Could not start the GitHub connection.")
        |> redirect(to: ~p"/integrations")
    end
  end

  def callback(conn, %{"state" => state, "code" => code}) do
    tenant_id = current_tenant_id(conn)
    redirect_uri = url(~p"/integrations/github/callback")

    case Tango.exchange_code(state, code, tenant_id, redirect_uri: redirect_uri) do
      {:ok, connection} ->
        # Store connection.id in host tables if needed; never the tokens.
        conn
        |> put_flash(:info, "GitHub connected.")
        |> redirect(to: ~p"/integrations")

      {:error, _reason} ->
        conn
        |> put_flash(:error, "GitHub connection failed.")
        |> redirect(to: ~p"/integrations")
    end
  end

  def callback(conn, %{"error" => _error}) do
    conn
    |> put_flash(:error, "GitHub connection was cancelled or denied.")
    |> redirect(to: ~p"/integrations")
  end
end
```

Route both actions through the authenticated browser pipeline so `current_tenant_id/1` resolves on the callback.

## Options and results

`Tango.create_session/3` options: `:redirect_uri`, `:scopes` (empty means `authorize_url/2` may supply them, else provider `default_scopes`), `:metadata` (sanitized map stored on the session). Returns `{:ok, %Tango.Schemas.OAuthSession{}}` or `{:error, :provider_not_found}` and validation atoms such as `:invalid_tenant_id`, `:invalid_scopes`, `:invalid_redirect_uri`, `:insecure_redirect_uri`.

`Tango.authorize_url/2` options: `:redirect_uri` (defaults to the session's), `:scopes` (used only when the session bound none). Returns `{:ok, url}`, or errors such as `:session_not_found`, `:session_expired`, `:invalid_redirect_uri`, and `:redirect_uri_mismatch` (a different URI than the one already bound to the session).

`Tango.exchange_code/4` returns `{:ok, %Tango.Schemas.Connection{}}` with plaintext tokens in memory. Errors include `:invalid_state`, `:invalid_state_parameter`, `:invalid_authorization_code`, `:invalid_tenant_id`, `:invalid_options`, `:session_not_found`, `:session_expired`, `:redirect_uri_mismatch`, `:redirect_uri_binding_violation` (session has a bound URI but none was passed), `:invalid_session` (a staged session from `create_authorization_session/3`), and sanitized `{:oauth_error, category}` for provider failures. A tenant that does not match the one encoded in `state` fails as `:invalid_state`. A successful exchange deletes the session and revokes the tenant's previous connection for that provider.

Look up a session by token with `Tango.get_session/1` when debugging.

## Do not

- Do not render or JSON-encode the returned connection. Return status and scopes only, the way `POST /exchange` in `Tango.API.Router` does.
- Do not log `state`, `code`, or the provider callback query string.
- Do not accept `tenant_id` from the callback params.
