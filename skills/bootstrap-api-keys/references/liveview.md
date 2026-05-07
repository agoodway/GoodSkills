# LiveView: API Key Management UI

Create `lib/my_app_web/live/api_key_live/index.ex`:

```elixir
defmodule MyAppWeb.ApiKeyLive.Index do
  @moduledoc """
  LiveView for managing API keys.

  Supports listing, creating, and revoking API keys scoped to the
  current user (or account membership).
  """
  use MyAppWeb, :live_view

  alias MyApp.Accounts
  alias MyApp.Accounts.ApiKey

  # ADAPT: Remove rate limiting if not using it
  @key_create_limit 5
  @key_create_scale :timer.minutes(1)

  @impl true
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) ::
          {:ok, Phoenix.LiveView.Socket.t()} | {:ok, Phoenix.LiveView.Socket.t(), keyword()}
  def mount(_params, _session, socket) do
    # ADAPT: Get the parent record from socket assigns.
    # For user-scoped keys:
    user = socket.assigns.current_user
    # For account_user-scoped keys:
    # account_user = get_account_user(socket)

    {:ok,
     socket
     |> assign(
       page_title: "API Keys",
       # ADAPT: Change parent assign name
       parent: user,
       api_keys: list_keys(user),
       show_create_modal: false,
       raw_token: nil,
       form: to_form(ApiKey.changeset(%ApiKey{}, %{})),
       revoke_key_id: nil
     )}
  end

  @impl true
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-end justify-between">
        <div>
          <h1 class="text-xl font-bold tracking-tight text-base-content">API Keys</h1>
          <p class="mt-0.5 text-sm text-base-content/50">
            Manage API keys for programmatic access.
          </p>
        </div>
        <.button phx-click="show_create_modal">
          <.icon name="hero-plus" class="size-4 mr-1" /> Create Key
        </.button>
      </div>

      <%= if @api_keys == [] do %>
        <.empty_state />
      <% else %>
        <.key_table keys={@api_keys} />
      <% end %>
    </div>

    <.create_key_modal :if={@show_create_modal} form={@form} />
    <.token_display_modal :if={@raw_token} raw_token={@raw_token} />
    <.revoke_confirm_modal :if={@revoke_key_id} />
    """
  end

  # --- Components ---

  @spec empty_state(map()) :: Phoenix.LiveView.Rendered.t()
  defp empty_state(assigns) do
    ~H"""
    <div class="rounded-xl border border-base-300/60 bg-base-100 p-12 text-center">
      <.icon name="hero-key" class="mx-auto size-10 text-base-content/20" />
      <h3 class="mt-3 text-sm font-semibold text-base-content">No API keys</h3>
      <p class="mt-1 text-sm text-base-content/50">
        Create your first API key to start using the API.
      </p>
      <div class="mt-4">
        <.button phx-click="show_create_modal">
          <.icon name="hero-plus" class="size-4 mr-1" /> Create Key
        </.button>
      </div>
    </div>
    """
  end

  attr :keys, :list, required: true

  @spec key_table(map()) :: Phoenix.LiveView.Rendered.t()
  defp key_table(assigns) do
    ~H"""
    <div class="rounded-xl border border-base-300/60 bg-base-100 overflow-hidden">
      <table class="table">
        <thead>
          <tr>
            <th>Name</th>
            <th>Type</th>
            <th>Prefix</th>
            <th>Status</th>
            <th>Last Used</th>
            <th>Created</th>
            <th><span class="sr-only">Actions</span></th>
          </tr>
        </thead>
        <tbody>
          <tr :for={key <- @keys} id={"key-#{key.id}"}>
            <td class="font-medium">{key.name}</td>
            <td>
              <.type_badge type={key.type} />
            </td>
            <td>
              <code class="text-xs bg-base-200 px-1.5 py-0.5 rounded">{key.token_prefix}...</code>
            </td>
            <td>
              <.status_badge status={key.status} />
            </td>
            <td class="text-sm text-base-content/50">
              {format_datetime(key.last_used_at) || "Never"}
            </td>
            <td class="text-sm text-base-content/50">
              {format_datetime(key.inserted_at)}
            </td>
            <td>
              <button
                :if={key.status == :active}
                phx-click="confirm_revoke"
                phx-value-id={key.id}
                class="btn btn-ghost btn-xs text-error"
              >
                Revoke
              </button>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  attr :type, :atom, required: true

  @spec type_badge(map()) :: Phoenix.LiveView.Rendered.t()
  defp type_badge(assigns) do
    ~H"""
    <span class={[
      "badge badge-sm",
      if(@type == :private, do: "badge-warning", else: "badge-info")
    ]}>
      {if @type == :private, do: "Private", else: "Public"}
    </span>
    """
  end

  attr :status, :atom, required: true

  @spec status_badge(map()) :: Phoenix.LiveView.Rendered.t()
  defp status_badge(assigns) do
    ~H"""
    <span class={[
      "badge badge-sm",
      if(@status == :active, do: "badge-success", else: "badge-error")
    ]}>
      {if @status == :active, do: "Active", else: "Revoked"}
    </span>
    """
  end

  attr :form, :map, required: true

  @spec create_key_modal(map()) :: Phoenix.LiveView.Rendered.t()
  defp create_key_modal(assigns) do
    ~H"""
    <dialog
      id="create-key-modal"
      class="modal modal-open"
      phx-window-keydown="hide_create_modal"
      phx-key="Escape"
    >
      <div class="modal-box">
        <h3 class="text-lg font-bold">Create API Key</h3>
        <.form for={@form} id="create-key-form" phx-submit="create_key" class="mt-4 space-y-4">
          <.input
            field={@form[:name]}
            type="text"
            label="Key Name"
            placeholder="e.g. Production API"
            required
          />
          <.input
            field={@form[:type]}
            type="select"
            label="Key Type"
            options={[{"Public (read-only)", :public}, {"Private (read-write)", :private}]}
          />
          <.input field={@form[:expires_at]} type="datetime-local" label="Expiration (optional)" />
          <div class="modal-action">
            <button type="button" class="btn" phx-click="hide_create_modal">
              Cancel
            </button>
            <.button type="submit" variant="primary">Create Key</.button>
          </div>
        </.form>
      </div>
    </dialog>
    """
  end

  attr :raw_token, :string, required: true

  @spec token_display_modal(map()) :: Phoenix.LiveView.Rendered.t()
  defp token_display_modal(assigns) do
    ~H"""
    <dialog
      id="token-display-modal"
      class="modal modal-open"
      phx-window-keydown="dismiss_token"
      phx-key="Escape"
    >
      <div class="modal-box">
        <h3 class="text-lg font-bold">Your API Key</h3>
        <div class="mt-2">
          <div class="alert alert-warning">
            <.icon name="hero-exclamation-triangle" class="size-5" />
            <span class="text-sm">Copy this key now. You won't be able to see it again.</span>
          </div>
        </div>
        <div class="mt-4 flex items-center gap-2">
          <input
            id="token-value"
            type="text"
            value={@raw_token}
            readonly
            class="input input-bordered w-full font-mono text-sm"
          />
          <button
            id="copy-token-btn"
            type="button"
            phx-hook=".CopyToClipboard"
            data-copy-target="#token-value"
            class="btn btn-square btn-ghost"
            phx-update="ignore"
          >
            <.icon name="hero-clipboard-document" class="size-5" />
          </button>
        </div>
        <div class="modal-action">
          <button type="button" class="btn btn-primary" phx-click="dismiss_token">Done</button>
        </div>
      </div>
    </dialog>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".CopyToClipboard">
      export default {
        mounted() {
          this.el.addEventListener("click", () => {
            const target = document.querySelector(this.el.dataset.copyTarget);
            if (target) {
              navigator.clipboard.writeText(target.value).then(() => {
                this.el.classList.add("text-success");
                setTimeout(() => this.el.classList.remove("text-success"), 2000);
              }).catch(() => {
                this.el.classList.add("text-error");
                setTimeout(() => this.el.classList.remove("text-error"), 2000);
              });
            }
          });
        }
      }
    </script>
    """
  end

  @spec revoke_confirm_modal(map()) :: Phoenix.LiveView.Rendered.t()
  defp revoke_confirm_modal(assigns) do
    ~H"""
    <dialog
      id="revoke-confirm-modal"
      class="modal modal-open"
      phx-window-keydown="cancel_revoke"
      phx-key="Escape"
    >
      <div class="modal-box">
        <h3 class="text-lg font-bold">Revoke API Key</h3>
        <p class="mt-2 text-sm text-base-content/70">
          Are you sure you want to revoke this API key? This action cannot be undone.
          Any applications using this key will lose access immediately.
        </p>
        <div class="modal-action">
          <button type="button" class="btn" phx-click="cancel_revoke">Cancel</button>
          <button type="button" class="btn btn-error" phx-click="revoke_key">Revoke</button>
        </div>
      </div>
    </dialog>
    """
  end

  # --- Events ---

  @impl true
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("show_create_modal", _params, socket) do
    {:noreply, assign(socket, show_create_modal: true)}
  end

  @impl true
  def handle_event("hide_create_modal", _params, socket) do
    {:noreply,
     assign(socket,
       show_create_modal: false,
       form: to_form(ApiKey.changeset(%ApiKey{}, %{}))
     )}
  end

  @impl true
  def handle_event("create_key", %{"api_key" => params}, socket) do
    parent = socket.assigns.parent

    # ADAPT: Remove rate limiting block if not using rate limiting.
    # If using rate limiting, ensure you have a rate limiter module.
    # rate_key = "api_key_create:#{parent.id}"
    # with {:allow, _count} <- MyApp.RateLimiter.hit(rate_key, @key_create_scale, @key_create_limit),

    with {:ok, expires_at} <- parse_expires_at(params["expires_at"]) do
      attrs = %{
        name: params["name"],
        type: parse_type(params["type"]),
        expires_at: expires_at
      }

      case Accounts.create_api_key(parent, attrs) do
        {:ok, {_api_key, token}} ->
          {:noreply,
           socket
           |> assign(
             api_keys: list_keys(parent),
             raw_token: token,
             show_create_modal: false,
             form: to_form(ApiKey.changeset(%ApiKey{}, %{}))
           )}

        {:error, changeset} ->
          {:noreply, assign(socket, form: to_form(changeset))}
      end
    else
      {:error, :invalid_date} ->
        {:noreply, put_flash(socket, :error, "Invalid expiration date format.")}
    end
  end

  @impl true
  def handle_event("dismiss_token", _params, socket) do
    {:noreply, assign(socket, raw_token: nil)}
  end

  @impl true
  def handle_event("confirm_revoke", %{"id" => id}, socket) do
    with {:ok, uuid} <- Ecto.UUID.cast(id),
         true <- Enum.any?(socket.assigns.api_keys, &(&1.id == uuid)) do
      {:noreply, assign(socket, revoke_key_id: uuid)}
    else
      _ -> {:noreply, socket}
    end
  end

  @impl true
  def handle_event("cancel_revoke", _params, socket) do
    {:noreply, assign(socket, revoke_key_id: nil)}
  end

  @impl true
  def handle_event("revoke_key", _params, socket) do
    key = Enum.find(socket.assigns.api_keys, &(&1.id == socket.assigns.revoke_key_id))

    case key do
      nil ->
        {:noreply,
         socket
         |> assign(revoke_key_id: nil)
         |> put_flash(:error, "API key not found.")}

      key ->
        case Accounts.revoke_api_key(key) do
          {:ok, _revoked_key} ->
            {:noreply,
             socket
             |> assign(
               api_keys: list_keys(socket.assigns.parent),
               revoke_key_id: nil
             )
             |> put_flash(:info, "API key revoked successfully.")}

          {:error, _changeset} ->
            {:noreply,
             socket
             |> assign(revoke_key_id: nil)
             |> put_flash(:error, "Failed to revoke API key.")}
        end
    end
  end

  # --- Helpers ---

  @spec list_keys(struct()) :: [struct()]
  defp list_keys(parent) do
    parent
    |> Accounts.list_api_keys()
    |> Enum.sort_by(& &1.inserted_at, {:desc, NaiveDateTime})
  end

  @spec parse_type(String.t()) :: :public | :private
  defp parse_type("private"), do: :private
  defp parse_type(_), do: :public

  @spec parse_expires_at(String.t() | nil) :: {:ok, DateTime.t() | nil} | {:error, :invalid_date}
  defp parse_expires_at(nil), do: {:ok, nil}
  defp parse_expires_at(""), do: {:ok, nil}

  defp parse_expires_at(datetime_string) do
    case NaiveDateTime.from_iso8601(datetime_string) do
      {:ok, naive} -> {:ok, DateTime.from_naive!(naive, "Etc/UTC")}
      _ -> {:error, :invalid_date}
    end
  end

  @spec format_datetime(DateTime.t() | NaiveDateTime.t() | nil) :: String.t() | nil
  defp format_datetime(nil), do: nil

  defp format_datetime(datetime) do
    Calendar.strftime(datetime, "%b %d, %Y %H:%M")
  end
end
```

## If key types are NOT needed

Remove the type column from the table, the `type_badge` component, the type selector from the create modal, and the `parse_type/1` helper. Simplify the `create_key` handler to not pass `:type`.

## If NOT using DaisyUI

Replace DaisyUI classes with plain Tailwind equivalents:
- `badge badge-sm badge-success` → `inline-flex items-center px-2 py-0.5 text-xs font-medium rounded-full bg-green-100 text-green-800`
- `modal modal-open` → `fixed inset-0 z-50 flex items-center justify-center bg-black/50`
- `modal-box` → `bg-white rounded-lg p-6 max-w-md w-full shadow-xl`
- `btn` → `px-4 py-2 rounded-lg font-medium`
- `table` → `w-full text-sm text-left`
- `alert alert-warning` → `flex items-center gap-2 p-3 rounded-lg bg-amber-50 text-amber-800 border border-amber-200`
