# Routes & Notifications

## Router

Add these routes inside the existing account-scoped `live_session` block in `lib/my_app_web/router.ex`.

Find the existing account-scoped live_session (created by `/bootstrap-accounts`):

```elixir
live_session :account_dashboard,
  on_mount: [
    {MyAppWeb.UserAuth, :ensure_authenticated},
    {MyAppWeb.UserAuth, :load_account_context}
  ],
  layout: {MyAppWeb.Layouts, :dashboard} do
  scope "/dashboard/accounts/:account_slug" do
    pipe_through [:load_account]

    live "/", DashboardLive, :index
    # Add user management routes here:
    live "/users", Admin.AccountUsersLive, :index
    live "/users/new", Admin.AccountUsersLive, :new
  end
end
```

## Sidebar Navigation

Add a "Users" entry to the sidebar navigation in `lib/my_app_web/components/layouts.ex`.

Find the existing nav items list and add:

```elixir
%{
  label: "Users",
  to: ~p"/dashboard/accounts/#{@current_account.slug}/users",
  icon: "hero-users",
  active: @active_nav == :account_users
}
```

Place it after the Dashboard entry and before Settings (or at the end if no Settings exists).

## Email Notification (Optional)

If you want to notify invited users, add a function to the existing `UserNotifier` module at `lib/my_app/accounts/user_notifier.ex`:

```elixir
@doc """
Delivers a notification email when a user is added to an account.
"""
def deliver_account_user_added_notification(user, account, dashboard_url) do
  deliver(user.email, "You've been added to #{account.name}", """

  ==============================

  Hi #{user.email},

  You've been added to the #{account.name} account.

  You can access the dashboard at:

    #{dashboard_url}

  ==============================
  """)
end
```

Then update `invite_user_to_account/3` in the Accounts context to call this after a successful invite:

```elixir
def invite_user_to_account(account_id, email, role) do
  result =
    Repo.transaction(fn ->
      with {:ok, user} <- find_or_create_user(email),
           {:ok, account_user} <- do_add_user_to_account(account_id, user, role) do
        Repo.preload(account_user, [:user])
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)

  case result do
    {:ok, account_user} ->
      account = Repo.get!(Account, account_id)
      dashboard_url = MyAppWeb.Endpoint.url() <> "/dashboard/accounts/#{account.slug}"

      UserNotifier.deliver_account_user_added_notification(
        account_user.user,
        account,
        dashboard_url
      )

      {:ok, account_user}

    error ->
      error
  end
end
```

## Verification

After adding routes, verify:

```bash
# Check routes exist
mix phx.routes | grep users

# Should show something like:
# GET /dashboard/accounts/:account_slug/users
# GET /dashboard/accounts/:account_slug/users/new
```

```bash
# Compile without warnings
mix compile --warnings-as-errors
```
