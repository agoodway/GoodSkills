# Router, DashboardLive & Seeds

## Router Setup

Add these to `lib/my_app_web/router.ex`:

### Pipeline

Add after the existing pipelines:

```elixir
pipeline :load_account do
  plug(MyAppWeb.Plugs.LoadAccount)
end
```

### Account-Scoped Dashboard Routes

Add the account-scoped live_session and the dashboard redirect:

```elixir
# Account-scoped dashboard (LiveView)
scope "/dashboard/accounts/:account_id", MyAppWeb do
  pipe_through([:browser, :require_authenticated_user])

  live_session :account_scoped,
    on_mount: [
      {MyAppWeb.UserAuth, :ensure_authenticated},
      {MyAppWeb.UserAuth, :load_account_context}
    ],
    layout: {MyAppWeb.Layouts, :dashboard} do
    live("/", DashboardLive, :index)
    # Add more routes here as needed:
    # live("/resources", ResourceLive.Index, :index)
    # live("/resources/new", ResourceLive.Index, :new)
    # live("/resources/:id", ResourceLive.Show, :show)
  end
end

# /dashboard redirect to default account
scope "/", MyAppWeb do
  pipe_through([:browser, :require_authenticated_user])
  get("/dashboard", DashboardRedirectController, :index)
end
```

## DashboardLive

Create `lib/my_app_web/live/dashboard_live.ex`:

```elixir
defmodule MyAppWeb.DashboardLive do
  @moduledoc """
  Dashboard LiveView — the authenticated user's home page.
  """
  use MyAppWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Dashboard",
       active_nav: :dashboard,
       breadcrumbs: [%{label: "Dashboard"}]
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-end justify-between">
        <div>
          <h1 class="text-xl font-bold tracking-tight text-base-content">{@current_account.name}</h1>
          <p class="mt-0.5 text-sm text-base-content/50">
            Welcome to your dashboard.
          </p>
        </div>
      </div>

      <%!-- Content cards go here --%>
      <div class="rounded-xl border border-base-300/60 bg-base-100">
        <div class="flex items-center justify-between border-b border-base-300/40 px-5 py-3.5">
          <h2 class="text-sm font-semibold text-base-content">Getting Started</h2>
        </div>
        <div class="p-5">
          <p class="text-sm text-base-content/60">Your dashboard is ready. Start building!</p>
        </div>
      </div>
    </div>
    """
  end
end
```

## Seeds

Update `priv/repo/seeds.exs` to create test data:

```elixir
alias MyApp.Accounts
alias MyApp.Repo

# Create test user
{:ok, user} =
  Accounts.register_user(%{
    email: "user@example.com",
    password: "password1234password1234"
  })

# Confirm the user (skip email confirmation)
user
|> Ecto.Changeset.change(%{confirmed_at: DateTime.utc_now() |> DateTime.truncate(:second)})
|> Repo.update!()

# Create two accounts
{:ok, account1} = Accounts.create_account(%{name: "Acme Corp"})
{:ok, account2} = Accounts.create_account(%{name: "Globex Industries"})

# Link user to both accounts
{:ok, _} = Accounts.create_account_user(%{user_id: user.id, account_id: account1.id, role: :owner})
{:ok, _} = Accounts.create_account_user(%{user_id: user.id, account_id: account2.id, role: :member})

IO.puts("Seeds created successfully!")
IO.puts("  User: user@example.com / password1234password1234")
IO.puts("  Accounts: Acme Corp (owner), Globex Industries (member)")
```
