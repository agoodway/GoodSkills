# Auth Plug: Bearer Token Authentication

Create `lib/my_app_web/plugs/api_auth.ex`:

```elixir
defmodule MyAppWeb.Plugs.ApiAuth do
  @moduledoc """
  Bearer token authentication for API requests.
  Validates API keys and loads user/account context.
  """
  import Plug.Conn
  import Phoenix.Controller

  alias MyApp.Accounts

  @doc "Initialize plug options."
  @spec init(any()) :: any()
  def init(opts), do: opts

  @doc "Main plug function — dispatches based on opts."
  @spec call(Plug.Conn.t(), any()) :: Plug.Conn.t()
  def call(conn, opts) do
    case opts do
      :require_write_access -> require_write_access(conn, [])
      _ -> require_api_auth(conn, opts)
    end
  end

  @doc """
  Requires API authentication via Bearer token.
  Extracts token from Authorization header, verifies it, and loads context.
  """
  @spec require_api_auth(Plug.Conn.t(), any()) :: Plug.Conn.t()
  def require_api_auth(conn, _opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, api_key} <- Accounts.verify_api_token(token) do
      # ADAPT: Touch the key asynchronously if you have a TaskSupervisor
      # Task.Supervisor.start_child(MyApp.TaskSupervisor, fn ->
      #   Accounts.touch_api_key(api_key)
      # end)

      # Or touch synchronously (simpler):
      Accounts.touch_api_key(api_key)

      conn
      |> assign(:current_api_key, api_key)
      # ADAPT: Assign the parent. For user-scoped keys:
      |> assign(:current_user, api_key.user)
      # For account_user-scoped keys:
      # |> assign(:current_account_user, api_key.account_user)
      # |> assign(:current_user, api_key.account_user.user)
      # |> assign(:current_account, api_key.account_user.account)
    else
      _ ->
        conn
        |> put_status(:unauthorized)
        |> put_view(json: MyAppWeb.ErrorJSON)
        |> render(:"401")
        |> halt()
    end
  end

  @doc """
  Requires write access (private API key with sk_ prefix).
  Must be used after require_api_auth in the pipeline.
  """
  @spec require_write_access(Plug.Conn.t(), any()) :: Plug.Conn.t()
  def require_write_access(conn, _opts) do
    api_key = conn.assigns[:current_api_key]

    if api_key && api_key.type == :private do
      conn
    else
      conn
      |> put_status(:forbidden)
      |> put_view(json: MyAppWeb.ErrorJSON)
      |> render(:"403")
      |> halt()
    end
  end
end
```

## If key types are NOT needed

Remove the `require_write_access/2` function entirely and simplify the `call/2` dispatch.

## If using async touch

Add a `TaskSupervisor` to the application supervision tree in `lib/my_app/application.ex`:

```elixir
children = [
  # ... existing children
  {Task.Supervisor, name: MyApp.TaskSupervisor},
]
```
