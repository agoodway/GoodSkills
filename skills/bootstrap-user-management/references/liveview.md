# LiveView: Account Users

## AccountUsersLive

Create `lib/my_app_web/live/admin/account_users_live.ex`:

```elixir
defmodule MyAppWeb.Admin.AccountUsersLive do
  @moduledoc """
  LiveView for managing users within an account.

  Displays account members in a table with add/remove actions.
  Add and delete controls are gated behind `AccountUser.admin?/1`.
  """
  use MyAppWeb, :live_view

  on_mount {MyAppWeb.UserAuth, :require_account_level_user}

  alias MyApp.Accounts
  alias MyApp.Accounts.AccountUser
  alias MyAppWeb.Shared.MemberDisplayHelpers

  @impl true
  def mount(_params, _session, socket) do
    account = socket.assigns.current_account
    user = socket.assigns.current_scope.user
    account_user = Accounts.get_account_user(user, account)

    {:ok,
     socket
     |> assign(:active_nav, :account_users)
     |> assign(:current_account_user, account_user)}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    account = socket.assigns.current_account
    members = Accounts.list_account_members(account.id)

    socket =
      socket
      |> assign(:user_count, length(members))
      |> stream(:account_users, members, reset: true)

    {:noreply, apply_action(socket, socket.assigns.live_action)}
  end

  defp apply_action(socket, :new) do
    account = socket.assigns.current_account

    if AccountUser.admin?(socket.assigns.current_account_user) do
      socket
      |> assign(:page_title, "Add User")
      |> assign(:breadcrumbs, [
        %{label: "Users", to: ~p"/dashboard/accounts/#{account.slug}/users"},
        %{label: "Add User"}
      ])
    else
      socket
      |> put_flash(:error, "You are not authorized to add users.")
      |> push_patch(to: ~p"/dashboard/accounts/#{account.slug}/users")
    end
  end

  defp apply_action(socket, :index) do
    socket
    |> assign(:page_title, "Users")
    |> assign(:breadcrumbs, [%{label: "Users"}])
  end

  @impl true
  def handle_info(
        {MyAppWeb.Admin.AccountUserFormComponent, {:saved, _account_user}},
        socket
      ) do
    {:noreply, socket}
  end

  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    user = socket.assigns.current_scope.user
    account = socket.assigns.current_account
    current_au = Accounts.get_account_user(user, account)

    if current_au && AccountUser.admin?(current_au) do
      do_delete(socket, current_au, id)
    else
      {:noreply, put_flash(socket, :error, "You are not authorized to remove users.")}
    end
  end

  defp do_delete(socket, current_au, id) do
    account = socket.assigns.current_account

    with {:ok, member} <- Accounts.get_account_member(account.id, id),
         :ok <- validate_not_self(member, current_au),
         :ok <- Accounts.delete_account_member(member) do
      {:noreply,
       socket
       |> stream_delete(:account_users, member)
       |> update(:user_count, &(&1 - 1))
       |> put_flash(:info, "User removed from account.")}
    else
      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "User not found.")}

      {:error, :self} ->
        {:noreply, put_flash(socket, :error, "You cannot remove yourself.")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Cannot remove the last owner.")}
    end
  end

  defp validate_not_self(member, current_au) do
    if member.user_id == current_au.user_id, do: {:error, :self}, else: :ok
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <%!-- Page header --%>
      <div class="flex items-end justify-between">
        <div>
          <h1 class="text-xl font-bold tracking-tight text-base-content">Users</h1>
          <p class="mt-0.5 text-sm text-base-content/50">
            {@user_count} {if @user_count == 1, do: "user", else: "users"} in this account.
          </p>
        </div>
        <div :if={AccountUser.admin?(@current_account_user)} class="flex items-center gap-2">
          <.button patch={users_new_path(@current_account)}>
            <.icon name="hero-plus-mini" class="size-4" /> Add User
          </.button>
        </div>
      </div>

      <%!-- Users table card --%>
      <div class="rounded-xl border border-base-300/60 bg-base-100">
        <div class="flex items-center justify-between border-b border-base-300/40 px-5 py-3.5">
          <h2 class="text-sm font-semibold text-base-content">Account Members</h2>
          <span class="text-xs text-base-content/40">{@user_count} total</span>
        </div>
        <div class="p-0">
          <.table id="account-users" rows={@streams.account_users}>
            <:col :let={{_id, au}} label="Email">
              <span class="font-medium">{au.user.email}</span>
            </:col>
            <:col :let={{_id, au}} label="Role">
              <span class="badge badge-sm badge-ghost gap-1 capitalize">
                {MemberDisplayHelpers.format_role(au.role)}
              </span>
            </:col>
            <:col :let={{_id, au}} label="Joined">
              <span class="text-xs">{MemberDisplayHelpers.format_date(au.inserted_at)}</span>
            </:col>
            <:action :let={{_id, au}}>
              <.link
                :if={
                  AccountUser.admin?(@current_account_user) &&
                    au.user_id != @current_account_user.user_id
                }
                phx-click="delete"
                phx-value-id={au.id}
                data-confirm="Are you sure you want to remove this user from the account?"
                class="inline-flex items-center gap-1.5 text-sm text-base-content/60 hover:text-error transition-colors"
              >
                <.icon name="hero-trash-mini" class="size-3.5" /> Remove
              </.link>
            </:action>
          </.table>
        </div>
      </div>
    </div>

    <.modal
      :if={@live_action == :new}
      id="account-user-modal"
      show
      on_cancel={JS.patch(users_path(@current_account))}
      box_class="modal-box bg-base-100 p-0 rounded-xl border border-base-300/60 shadow-xl max-w-md"
    >
      <.live_component
        module={MyAppWeb.Admin.AccountUserFormComponent}
        id={:new}
        title={@page_title}
        account={@current_account}
        current_account_user={@current_account_user}
        patch={users_path(@current_account)}
      />
    </.modal>
    """
  end

  defp users_path(account) do
    ~p"/dashboard/accounts/#{account.slug}/users"
  end

  defp users_new_path(account) do
    ~p"/dashboard/accounts/#{account.slug}/users/new"
  end
end
```

**Note on `current_scope`:** If your app uses Phoenix 1.8's `current_scope` pattern, access the user via `socket.assigns.current_scope.user`. If you use a simpler `current_user` assign, replace `socket.assigns.current_scope.user` with `socket.assigns.current_user` throughout.

**Note on `require_account_level_user`:** This on_mount hook should exist from `/bootstrap-accounts`. If your app uses a different hook name for account-level access control, update the `on_mount` declaration.

---

## AccountUserFormComponent

Create `lib/my_app_web/live/admin/account_user_form_component.ex`:

```elixir
defmodule MyAppWeb.Admin.AccountUserFormComponent do
  @moduledoc """
  Form component for adding a user to an account.

  Accepts email and role, validates input, and invites the user
  to the account via `Accounts.invite_user_to_account/3`.
  """
  use MyAppWeb, :live_component

  alias MyApp.Accounts
  alias MyApp.Accounts.AccountUser

  @impl true
  def update(assigns, socket) do
    current_account_user = assigns.current_account_user

    role_options =
      if AccountUser.owner?(current_account_user) do
        [{"Owner", "owner"}, {"Admin", "admin"}, {"Member", "member"}]
      else
        [{"Admin", "admin"}, {"Member", "member"}]
      end

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:role_options, role_options)
     |> assign_new(:form, fn -> to_form(%{"email" => "", "role" => "member"}) end)}
  end

  @impl true
  def handle_event("validate", %{"email" => _email, "role" => _role} = params, socket) do
    {:noreply, assign(socket, :form, to_form(params))}
  end

  def handle_event("save", %{"email" => email, "role" => role} = params, socket) do
    account = socket.assigns.account
    current_account_user = socket.assigns.current_account_user

    with {:ok, role_atom} <- Accounts.parse_member_role(role),
         :ok <- Accounts.authorize_role_assignment(current_account_user, role_atom),
         {:ok, _account_user} <-
           Accounts.invite_user_to_account(account.id, email, role_atom) do
      notify_parent({:saved, nil})

      {:noreply,
       socket
       |> put_flash(:info, "User added to account.")
       |> push_patch(to: socket.assigns.patch)}
    else
      {:error, :forbidden} ->
        {:noreply,
         assign(
           socket,
           :form,
           form_with_errors(params, role: {"only owners can assign the owner role", []})
         )}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, form_with_errors(params, build_errors(changeset)))}
    end
  end

  defp build_errors(changeset) do
    if duplicate_user_constraint?(changeset) do
      [email: {"This user is already a member of the account", []}]
    else
      changeset_to_form_errors(changeset)
    end
  end

  defp duplicate_user_constraint?(changeset) do
    Enum.any?(changeset.errors, fn
      {:user_id, {_msg, opts}} -> opts[:constraint] == :unique
      _ -> false
    end)
  end

  defp changeset_to_form_errors(changeset) do
    Enum.flat_map(changeset.errors, fn
      {:user_id, {msg, _}} -> [email: {msg, []}]
      {:email, {msg, _}} -> [email: {msg, []}]
      {:role, {msg, _}} -> [role: {msg, []}]
      {_field, {msg, _}} -> [base: {msg, []}]
    end)
  end

  defp form_with_errors(params, errors), do: to_form(params, errors: errors)

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <%!-- Modal header --%>
      <div class="relative overflow-hidden border-b border-base-300/40 px-6 py-5">
        <div class="absolute inset-0 bg-gradient-to-r from-primary/[0.04] to-transparent" />
        <div class="relative flex items-center justify-between">
          <div class="flex items-center gap-3.5">
            <div class="flex size-10 items-center justify-center rounded-xl bg-primary/10 ring-1 ring-primary/20">
              <.icon name="hero-user-plus-mini" class="size-5 text-primary" />
            </div>
            <div>
              <h3 class="text-base font-bold tracking-tight text-base-content">{@title}</h3>
              <p class="mt-0.5 text-xs text-base-content/50">
                Add a user to {@account.name}
              </p>
            </div>
          </div>
          <button
            phx-click={JS.exec("data-cancel", to: "#account-user-modal")}
            type="button"
            class="btn btn-sm btn-circle btn-ghost text-base-content/30 hover:text-base-content"
            aria-label="close"
          >
            <.icon name="hero-x-mark" class="size-4" />
          </button>
        </div>
      </div>

      <%!-- Modal body --%>
      <div class="px-6 py-5">
        <.form
          for={@form}
          id="account-user-form"
          phx-target={@myself}
          phx-change="validate"
          phx-submit="save"
        >
          <div class="space-y-4">
            <.input field={@form[:email]} type="email" label="Email address" required />
            <.input
              field={@form[:role]}
              type="select"
              label="Role"
              options={@role_options}
              required
            />

            <div class="rounded-lg bg-base-200/30 border border-base-300/40 px-4 py-3">
              <p class="text-[10px] font-semibold text-base-content/40 uppercase tracking-widest">
                What happens next
              </p>
              <p class="mt-1.5 text-xs text-base-content/60 leading-relaxed">
                If this email is already registered, they'll be added immediately.
                Otherwise, a new account will be created and they'll receive a login link.
              </p>
            </div>
          </div>

          <%!-- Modal footer --%>
          <div class="mt-6 flex items-center justify-end gap-3 border-t border-base-300/40 pt-4">
            <button
              type="button"
              class="btn btn-sm btn-ghost text-base-content/50 hover:text-base-content"
              phx-click={JS.exec("data-cancel", to: "#account-user-modal")}
            >
              Cancel
            </button>
            <.button
              type="submit"
              variant="primary"
              class="btn-sm gap-1.5"
              phx-disable-with="Adding..."
            >
              <.icon name="hero-paper-airplane-mini" class="size-4" /> Add User
            </.button>
          </div>
        </.form>
      </div>
    </div>
    """
  end
end
```
