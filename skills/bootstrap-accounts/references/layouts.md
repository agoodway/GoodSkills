# Layouts: Dashboard Layout & Layouts Module

## Layouts Module

Update `lib/my_app_web/components/layouts.ex`. Keep the existing `app/1` and `flash_group/1` from the generator and add:

```elixir
defmodule MyAppWeb.Layouts do
  use MyAppWeb, :html

  embed_templates "layouts/*"

  # Keep the existing app/1 and flash_group/1 from the generator

  # --- Sidebar ---

  attr :active_nav, :atom, required: true
  attr :current_scope, :map, required: true
  attr :current_account, :map, default: nil

  def sidebar_content(assigns) do
    assigns = assign(assigns, :account_base, account_dashboard_path(assigns[:current_account]))

    ~H"""
    <%!-- Logo --%>
    <div class="flex h-14 shrink-0 items-center px-5 border-b border-white/[0.06]">
      <.link href={~p"/dashboard"} class="flex items-center gap-2.5">
        <%!-- Replace with your logo --%>
        <span class="text-sm font-bold tracking-tight text-white/90">MyApp</span>
      </.link>
    </div>

    <%!-- Navigation --%>
    <nav class="flex flex-1 flex-col px-3 py-4">
      <ul role="list" class="flex flex-1 flex-col gap-y-5">
        <li>
          <p class="px-2 mb-2 text-[0.65rem] font-semibold uppercase tracking-widest text-white/30">
            Overview
          </p>
          <ul role="list" class="space-y-0.5">
            <.sidebar_nav_item
              href={@account_base}
              icon="hero-squares-2x2"
              label="Dashboard"
              active={@active_nav == :dashboard}
            />
          </ul>
        </li>

        <%!-- Add more nav groups here --%>
        <%!--
        <li>
          <p class="px-2 mb-2 text-[0.65rem] font-semibold uppercase tracking-widest text-white/30">
            Management
          </p>
          <ul role="list" class="space-y-0.5">
            <.sidebar_nav_item
              href={"#{@account_base}/resources"}
              icon="hero-folder"
              label="Resources"
              active={@active_nav == :resources}
            />
          </ul>
        </li>
        --%>

        <%!-- Bottom section --%>
        <li class="mt-auto">
          <ul role="list" class="space-y-0.5">
            <.sidebar_nav_item
              href={~p"/users/settings"}
              icon="hero-cog-6-tooth"
              label="Settings"
              active={@active_nav == :settings}
            />
          </ul>

          <%!-- User info --%>
          <div class="mt-3 pt-3 border-t border-white/[0.06]">
            <div class="flex items-center gap-2.5 px-2 py-1.5">
              <div class="flex h-7 w-7 shrink-0 items-center justify-center rounded-full bg-white/10 text-xs font-bold text-white/70">
                {String.first(@current_scope.user.email) |> String.upcase()}
              </div>
              <div class="min-w-0 flex-1">
                <p class="truncate text-xs font-medium text-white/70">
                  {@current_scope.user.email}
                </p>
              </div>
            </div>
          </div>
        </li>
      </ul>
    </nav>
    """
  end

  attr :href, :string, required: true
  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :active, :boolean, default: false

  def sidebar_nav_item(assigns) do
    ~H"""
    <li>
      <.link
        href={@href}
        class={[
          "group flex items-center gap-x-2.5 rounded-md px-2 py-1.5 text-[0.8125rem] font-medium transition-colors",
          if(@active,
            do: "bg-white/10 text-white",
            else: "text-white/60 hover:bg-white/[0.06] hover:text-white/80"
          )
        ]}
      >
        <.icon
          name={@icon}
          class={[
            "size-[1.125rem] shrink-0",
            if(@active,
              do: "text-primary",
              else: "text-white/30 group-hover:text-white/60"
            )
          ]}
        />
        {@label}
      </.link>
    </li>
    """
  end

  # --- Mobile Sidebar JS ---

  def show_mobile_sidebar do
    JS.show(
      to: "#mobile-sidebar-backdrop",
      transition: {"transition-opacity ease-linear duration-300", "opacity-0", "opacity-100"}
    )
    |> JS.show(
      to: "#mobile-sidebar-overlay",
      transition: {"transition-opacity ease-linear duration-300", "opacity-0", "opacity-100"}
    )
    |> JS.show(
      to: "#mobile-sidebar-panel",
      transition:
        {"transition ease-in-out duration-300 transform", "-translate-x-full", "translate-x-0"}
    )
    |> JS.focus_first(to: "#mobile-sidebar-panel")
  end

  def hide_mobile_sidebar do
    JS.hide(
      to: "#mobile-sidebar-panel",
      transition:
        {"transition ease-in-out duration-300 transform", "translate-x-0", "-translate-x-full"}
    )
    |> JS.hide(
      to: "#mobile-sidebar-overlay",
      transition: {"transition-opacity ease-linear duration-300", "opacity-100", "opacity-0"}
    )
    |> JS.hide(
      to: "#mobile-sidebar-backdrop",
      transition: {"transition-opacity ease-linear duration-300", "opacity-100", "opacity-0"},
      time: 300
    )
  end

  # --- Theme Toggle ---

  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button class="flex p-2 cursor-pointer w-1/3" phx-click={JS.dispatch("phx:set-theme")} data-phx-theme="system">
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button class="flex p-2 cursor-pointer w-1/3" phx-click={JS.dispatch("phx:set-theme")} data-phx-theme="light">
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button class="flex p-2 cursor-pointer w-1/3" phx-click={JS.dispatch("phx:set-theme")} data-phx-theme="dark">
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end

  defp account_dashboard_path(nil), do: "/dashboard"
  defp account_dashboard_path(account), do: "/dashboard/accounts/#{account.id}"
end
```

## Dashboard Layout Template

Create `lib/my_app_web/components/layouts/dashboard.html.heex`:

```heex
<%!-- Mobile sidebar backdrop + panel --%>
<div
  id="mobile-sidebar-backdrop"
  class="relative z-50 lg:hidden hidden"
  role="dialog"
  aria-modal="true"
>
  <div
    id="mobile-sidebar-overlay"
    class="fixed inset-0 bg-black/60 backdrop-blur-xs"
    phx-click={hide_mobile_sidebar()}
    phx-window-keydown={hide_mobile_sidebar()}
    phx-key="Escape"
  />

  <div class="fixed inset-0 flex">
    <div id="mobile-sidebar-panel" class="relative mr-16 flex w-full max-w-xs flex-1">
      <%!-- Close button --%>
      <div class="absolute top-0 left-full flex w-16 justify-center pt-5">
        <button type="button" class="-m-2.5 p-2.5" phx-click={hide_mobile_sidebar()}>
          <span class="sr-only">Close sidebar</span>
          <.icon name="hero-x-mark" class="size-6 text-white/80" />
        </button>
      </div>

      <%!-- Mobile sidebar content --%>
      <div class="sidebar-panel flex grow flex-col overflow-y-auto">
        <.sidebar_content
          active_nav={@active_nav}
          current_scope={@current_scope}
          current_account={assigns[:current_account]}
        />
      </div>
    </div>
  </div>
</div>

<%!-- Desktop sidebar --%>
<div class="hidden lg:fixed lg:inset-y-0 lg:z-50 lg:flex lg:w-64 lg:flex-col">
  <div class="sidebar-panel flex grow flex-col overflow-y-auto">
    <.sidebar_content
      active_nav={@active_nav}
      current_scope={@current_scope}
      current_account={assigns[:current_account]}
    />
  </div>
</div>

<%!-- Main content area --%>
<div class="lg:pl-64">
  <%!-- Top bar --%>
  <div class="sticky top-0 z-40 flex h-14 shrink-0 items-center gap-x-4 border-b border-base-300/50 bg-base-100/95 backdrop-blur-sm px-4 sm:gap-x-6 sm:px-6 lg:px-8">
    <%!-- Mobile hamburger --%>
    <button
      type="button"
      class="-m-2.5 p-2.5 text-base-content/60 hover:text-base-content lg:hidden"
      phx-click={show_mobile_sidebar()}
    >
      <span class="sr-only">Open sidebar</span>
      <.icon name="hero-bars-3" class="size-5" />
    </button>

    <%!-- Separator --%>
    <div class="h-5 w-px bg-base-300 lg:hidden" aria-hidden="true" />

    <div class="flex flex-1 gap-x-4 self-stretch lg:gap-x-6">
      <%!-- Breadcrumbs / Page title --%>
      <div class="flex items-center flex-1 min-w-0">
        <%= if assigns[:breadcrumbs] do %>
          <.breadcrumbs items={@breadcrumbs} />
        <% else %>
          <h1 class="text-sm font-semibold text-base-content/80">
            {assigns[:page_title] || "Dashboard"}
          </h1>
        <% end %>
      </div>
      <div class="flex items-center gap-x-3 lg:gap-x-4">
        <%!-- Account Switcher --%>
        <%= if assigns[:current_account] do %>
          <.live_component
            module={MyAppWeb.Components.AccountSwitcher}
            id="account-switcher"
            current_scope={@current_scope}
            current_account={@current_account}
          />

          <%!-- Separator --%>
          <div class="hidden lg:block lg:h-5 lg:w-px lg:bg-base-300" aria-hidden="true" />
        <% end %>

        <.theme_toggle />

        <%!-- Separator --%>
        <div class="hidden lg:block lg:h-5 lg:w-px lg:bg-base-300" aria-hidden="true" />

        <%!-- Profile dropdown --%>
        <div class="dropdown dropdown-end">
          <div
            tabindex="0"
            role="button"
            class="flex items-center gap-x-2 p-1 rounded-lg hover:bg-base-200 transition-colors"
          >
            <div class="avatar placeholder">
              <div class="bg-primary/15 text-primary w-7 h-7 rounded-full text-xs font-bold flex items-center justify-center">
                <span>
                  {String.first(@current_scope.user.email) |> String.upcase()}
                </span>
              </div>
            </div>
            <span class="hidden lg:flex lg:items-center">
              <span class="text-xs font-medium text-base-content/70">
                {@current_scope.user.email}
              </span>
              <.icon name="hero-chevron-down-micro" class="ml-1 size-4 text-base-content/40" />
            </span>
          </div>
          <ul
            tabindex="0"
            class="dropdown-content menu bg-base-100 rounded-lg z-[1] w-52 p-1 shadow-xl ring-1 ring-base-300/50 mt-1"
          >
            <li>
              <.link href={~p"/users/settings"} class="text-sm">
                <.icon name="hero-cog-6-tooth-mini" class="size-4" /> Settings
              </.link>
            </li>
            <li>
              <.link href={~p"/users/log-out"} method="delete" class="text-sm">
                <.icon name="hero-arrow-right-start-on-rectangle-mini" class="size-4" /> Sign out
              </.link>
            </li>
          </ul>
        </div>
      </div>
    </div>
  </div>

  <main class="min-h-[calc(100vh-3.5rem)]">
    <div class="px-4 py-6 sm:px-6 lg:px-8">
      <.flash_group flash={@flash} />
      {@inner_content}
    </div>
  </main>
</div>
```
