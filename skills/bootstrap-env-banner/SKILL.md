---
name: bootstrap-env-banner
description: >
  Add a "non-production" environment banner to a Phoenix 1.8 app — a sticky bar
  at the top of every page that warns developers the app is not production.
  Adds a config entry for the production host, a reusable function component +
  helpers in the web Layouts module, and renders the banner in every root layout.
  Detection is host-based (or Mix-env based) and asks for configuration like the
  production host. Checks what already exists and only adds missing pieces.
  Use when the user says "env banner", "environment banner", "dev banner",
  "staging banner", "non-production bar", "not in production banner", or wants a
  warning bar shown everywhere except production.
---

# Bootstrap Environment Banner

Add a sticky bar at the top of every HTML page that makes it unmistakable when the
app is **not** running in production (e.g. local dev, or a non-production deployment).

## Prerequisites

Verify before starting:
1. Phoenix 1.8 app with HEEx layouts (a `*Web.Layouts` module embedding `layouts/*`)
2. At least one root layout (`root.html.heex`) with a `<body>` tag
3. Tailwind CSS (daisyUI optional — see Styling note in Step 2)

## App Name Detection

Detect from `mix.exs`:
- OTP app name (e.g., `my_app`) — used in config keys and `Application.get_env/2`
- Web module (e.g., `MyAppWeb`) — the module holding `Endpoint` and `Layouts`

Replace all `my_app` / `MyAppWeb` template references accordingly.

## Phase 0: Discovery

**CRITICAL: Before generating anything, audit the target app.**

1. **Existing banner** — `Grep("env_banner")` and `Grep("show_env_banner")` in `lib/`.
   If found: report what exists and skip.
2. **Layouts module** — Find the module that does `embed_templates("layouts/*")`
   (usually `lib/my_app_web/components/layouts.ex`). This is where helpers + the
   component go.
3. **Root layouts** — Find every root layout (`Grep("<body")` in
   `lib/**/components/layouts/*.html.heex`). There may be more than one
   (e.g. `root.html.heex`, `public_root.html.heex`). The banner must go in **each**.
4. **Fixed/sticky top chrome** — In layout templates, `Grep("inset-y-0")` and
   `Grep("sticky top-0")`. Any element fixed/sticky to the top will overlap a
   top banner and needs a top offset (see Step 4). Note their file + line.
5. **Production host** — Read `config/runtime.exs` / `fly.toml` / deploy config for
   `PHX_HOST`. Note the real production hostname to suggest as the default.
6. **Styling** — Check `assets/css/app.css` for `daisyui`. Note whether daisyUI
   semantic classes (`bg-warning`) are available or plain Tailwind is needed.

### Discovery Report

Present findings (app name, layouts module, every root layout, any fixed/sticky
top chrome, detected production host) and confirm before proceeding.

## Phase 1: Configuration

Ask the user (lead with the detected defaults):

1. **Detection strategy** — When should the banner show?
   - **Host-based (recommended)**: show unless the endpoint's configured host equals
     the production host. Correct when a prod release runs on multiple/non-prod hosts
     (e.g. a staging deploy running `MIX_ENV=prod`). Asks for the production host.
   - **Mix-env based**: show whenever `Application.get_env(:my_app, :env) != :prod`.
     Simpler, but hides the banner on any deployment built with `MIX_ENV=prod`
     (including staging). Requires `config :my_app, :env, config_env()` in `config.exs`.

2. **Production host** (host-based only) — The canonical production hostname.
   Default: the `PHX_HOST` found in Phase 0 (e.g. `example.com`).

3. **Banner label** — What text to show.
   Default: `"NON-PRODUCTION · <env> · <host>"` (env + endpoint host, computed at render).

4. **Dismissible?** — Default: **no** (always visible so it can't be accidentally hidden).

## Phase 2: Implementation

### Step 1: Add config

**Host-based** — add to `config/config.exs`:

```elixir
# Canonical production host. Used to decide whether to show the non-production
# banner (see MyAppWeb.Layouts.show_env_banner?/0).
config :my_app, :production_host, "example.com"
```

Optionally allow a runtime override by reading `System.get_env("PRODUCTION_HOST", "example.com")`
in `config/runtime.exs` instead — only if the host varies per deploy.

**Mix-env based** — ensure `config/config.exs` has (add if missing):

```elixir
config :my_app, :env, config_env()
```

### Step 2: Add helpers + component to the Layouts module

Add to `MyAppWeb.Layouts` (the module that does `embed_templates`), right after the
`embed_templates("layouts/*")` line:

```elixir
@doc """
Renders a sticky "non-production" warning bar at the top of every page.
Shown on every host except the canonical production host.
"""
def env_banner(assigns) do
  ~H"""
  <div
    :if={show_env_banner?()}
    class="sticky top-0 z-[100] flex h-7 w-full items-center justify-center gap-1.5 bg-warning text-warning-content text-xs font-semibold tracking-wide"
  >
    <.icon name="hero-exclamation-triangle-mini" class="size-3.5" />
    {env_banner_label()}
  </div>
  """
end

@doc "Whether the non-production environment banner should be shown."
@spec show_env_banner?() :: boolean()
def show_env_banner? do
  # HOST-BASED:
  MyAppWeb.Endpoint.host() != Application.fetch_env!(:my_app, :production_host)
  # MIX-ENV BASED (use this line instead):
  # Application.get_env(:my_app, :env) != :prod
end

@spec env_banner_label() :: String.t()
defp env_banner_label do
  env = Application.get_env(:my_app, :env)
  "NON-PRODUCTION · #{env} · #{MyAppWeb.Endpoint.host()}"
end
```

**`show_env_banner?/0` must be public** — fixed/sticky chrome in embedded layout
templates (Step 4) calls it. Keep `env_banner_label/0` private.

**Styling note:** `bg-warning` / `text-warning-content` are daisyUI classes. If the
app does not use daisyUI, swap them for plain Tailwind, e.g.
`bg-amber-400 text-black`. The `<.icon>` heroicon assumes the Phoenix default
`core_components` icon component; drop it if unavailable.

**Why host-based uses `Endpoint.host()`:** it returns the endpoint's *configured*
`:url` host — a fixed deployment-level value, NOT the request's `Host` header. So
custom domains / subdomains served by the production app all resolve to the
production host and stay hidden; on a non-prod deploy they all show the banner.

### Step 3: Render the banner in every root layout

In **each** root layout found in Phase 0, insert `<.env_banner />` as the **first
child of `<body>`**:

```heex
<body>
  <.env_banner />
  {@inner_content}
</body>
```

(If a layout already has content right after `<body>`, place `<.env_banner />`
before it.)

### Step 4: Offset fixed/sticky top chrome

The banner is pinned (`sticky top-0`, height `h-7` = 1.75rem). Any element from
Phase 0 that is fixed or sticky to the top of the viewport will sit *under* the
banner and must be offset by the banner height **only when the banner shows**.
Use a conditional class with `show_env_banner?/0`:

- **Fixed full-height sidebar** — replace `lg:inset-y-0` with:
  ```heex
  class={["...", if(show_env_banner?(), do: "lg:top-7 lg:bottom-0", else: "lg:inset-y-0")]}
  ```
- **Sticky top header/topbar** — replace `top-0` with:
  ```heex
  class={["...", if(show_env_banner?(), do: "top-7", else: "top-0")]}
  ```

Pick the offset (`top-7`) to match the banner's height class (`h-7`). Layouts with
only normal-flow content (public pages, auth pages) need no offset — the sticky
banner pins to the top and content flows beneath it.

### Step 5: Verify

1. `mix compile` — clean.
2. `mix phx.server`, open the app locally: the bar reads
   `NON-PRODUCTION · dev · localhost` on a public page, an auth page, and any
   dashboard/admin page. Confirm fixed/sticky chrome sits fully below the bar.
3. Host-based: temporarily set `:production_host` to `"localhost"` and confirm the
   bar disappears, then revert. Optionally add a test asserting
   `MyAppWeb.Layouts.show_env_banner?/0` is `false` when the endpoint host equals
   `:production_host`.
4. `mix format` and run the test suite.

## Summary of Changes

| File | Change |
|------|--------|
| `config/config.exs` | Add `:production_host` (host-based) or `:env` (mix-env) config |
| `lib/my_app_web/components/layouts.ex` | Add `env_banner/1`, `show_env_banner?/0`, `env_banner_label/0` |
| Each `*root*.html.heex` | Add `<.env_banner />` as first child of `<body>` |
| Layouts with fixed/sticky top chrome | Offset by `top-7` when `show_env_banner?/0` |

## Config Reference

| Key | Strategy | Meaning |
|-----|----------|---------|
| `:production_host` | host-based | Banner hidden only when `Endpoint.host()` equals this |
| `:env` (`config_env()`) | mix-env | Banner shown when `!= :prod` |
