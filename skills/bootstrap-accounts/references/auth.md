# Auth Integration: UserAuth, LoadAccount Plug, Redirect Controller

## UserAuth: Preserve last_account_id in Session

Find `renew_session/2` in `lib/my_app_web/user_auth.ex` and replace it:

```elixir
defp renew_session(conn, _user) do
  delete_csrf_token()
  last_account_id = get_session(conn, :last_account_id)

  conn =
    conn
    |> configure_session(renew: true)
    |> clear_session()

  if last_account_id do
    put_session(conn, :last_account_id, last_account_id)
  else
    conn
  end
end
```

## UserAuth: Add :load_account_context on_mount

Add this new `on_mount` clause to `lib/my_app_web/user_auth.ex`:

```elixir
def on_mount(:load_account_context, params, _session, socket) do
  account_id = params["account_id"]
  user = socket.assigns.current_scope.user

  case MyApp.AccountContext.get_account_for_user(user, account_id) do
    {:ok, account} ->
      socket =
        socket
        |> Phoenix.Component.assign(:current_account, account)

      {:cont, socket}

    {:error, :not_found} ->
      socket =
        socket
        |> Phoenix.LiveView.put_flash(:error, "Unable to access this account.")
        |> Phoenix.LiveView.redirect(to: "/dashboard")

      {:halt, socket}
  end
end
```

## LoadAccount Plug

Create `lib/my_app_web/plugs/load_account.ex`:

```elixir
defmodule MyAppWeb.Plugs.LoadAccount do
  @moduledoc """
  Plug to load and validate account context from URL parameters.
  Must be used after :require_authenticated_user pipeline.
  """
  import Plug.Conn

  alias MyApp.AccountContext

  def init(opts), do: opts

  def call(conn, _opts) do
    account_id = conn.params["account_id"]
    user = conn.assigns.current_scope.user

    case AccountContext.get_account_for_user(user, account_id) do
      {:ok, account} ->
        conn
        |> assign(:current_account, account)
        |> put_session(:last_account_id, account.id)

      {:error, :not_found} ->
        conn
        |> Phoenix.Controller.put_flash(:error, "Unable to access this account")
        |> Phoenix.Controller.redirect(to: "/dashboard")
        |> halt()
    end
  end
end
```

## Dashboard Redirect Controller

Create `lib/my_app_web/controllers/dashboard_redirect_controller.ex`:

```elixir
defmodule MyAppWeb.DashboardRedirectController do
  @moduledoc """
  Redirects /dashboard to /dashboard/accounts/:default_account_id
  """
  use MyAppWeb, :controller

  alias MyApp.AccountContext

  def index(conn, _params) do
    user = conn.assigns.current_scope.user

    case AccountContext.get_default_account(user, get_session(conn)) do
      {:ok, account} ->
        redirect(conn, to: "/dashboard/accounts/#{account.id}")

      {:error, :no_accounts} ->
        conn
        |> put_flash(:error, "You don't have access to any accounts. Please contact support.")
        |> redirect(to: "/")
    end
  end
end
```
