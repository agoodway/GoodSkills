---
name: bootstrap-registration-toggle
description: >
  Add ENV-based registration toggle to a Phoenix 1.8 app. Adds runtime config,
  controller plug guard, and conditional UI for the signup link on the login page.
  Checks what already exists and only adds missing pieces.
  Use when the user says "toggle registrations", "disable registrations",
  "registration toggle", "close registrations", or wants ENV-controlled signup.
---

# Bootstrap Registration Toggle

Add the ability to enable/disable user registration via an environment variable in a Phoenix 1.8 app generated with `phx.gen.auth`.

## Prerequisites

Verify before starting:
1. Phoenix 1.8 app with `phx.gen.auth` completed
2. A registration controller exists (e.g., `UserRegistrationController`)
3. A login page exists with a "Sign up" link

## App Name Detection

Detect the app module name from `mix.exs` (e.g., `MyApp`) and the OTP app name (e.g., `my_app`). Replace all template references accordingly.

## Phase 0: Discovery

**CRITICAL: Before generating anything, audit the target app to understand what's already in place.**

### Discovery Checklist

1. **Registration controller** — Find the registration controller
   - `Grep("UserRegistrationController")` or `Grep("RegistrationController")`
   - Note the module name and file path

2. **Existing toggle** — Check if a registration toggle already exists
   - `Grep("registration_enabled")` in config/ and lib/
   - If found: report what exists and skip

3. **Runtime config** — Check for runtime.exs and existing boolean_env helper
   - `Read("config/runtime.exs")`
   - Note if `boolean_env` helper already exists (reuse it)

4. **Login page** — Find the login template with signup link
   - `Grep("register")` in the session HTML templates
   - Note the file path for conditional rendering

5. **Router** — Find registration routes
   - `Grep("register")` in the router
   - Note the scope and pipeline they're in

### Discovery Report

Present findings and confirm before proceeding.

## Phase 1: Configuration (only if no env var exists)

Ask the user:

1. **ENV var name** — What should the environment variable be called?
   Default: `{APP_NAME_UPPER}_USER_REGISTRATION_ENABLED` (e.g., `MY_APP_USER_REGISTRATION_ENABLED`)

2. **Default behavior** — Should registration be open or closed by default?
   Default: open in dev/test, closed in prod (`config_env() != :prod`)

3. **Flash message** — What message to show when registration is disabled?
   Default: `"New account registration is temporarily unavailable."`

4. **Redirect path** — Where to redirect when registration is disabled?
   Default: `/users/log-in`

## Phase 2: Implementation

### Step 1: Add boolean_env helper to runtime.exs (if not present)

If `config/runtime.exs` does not already have a `boolean_env` helper, add one near the top:

```elixir
boolean_env = fn name, default ->
  case System.get_env(name) do
    nil -> default
    val -> String.downcase(val) in ~w(true 1 yes)
  end
end
```

### Step 2: Add config entry to runtime.exs

Add the registration toggle config:

```elixir
config :my_app,
       :user_registration_enabled,
       boolean_env.("MY_APP_USER_REGISTRATION_ENABLED", config_env() != :prod)
```

This means:
- **dev/test**: registration enabled by default (override with `MY_APP_USER_REGISTRATION_ENABLED=false`)
- **prod**: registration disabled by default (override with `MY_APP_USER_REGISTRATION_ENABLED=true`)

### Step 3: Add controller plug guard

Add a private plug to the registration controller that checks the config:

```elixir
plug(:ensure_registration_enabled)

# ... existing actions ...

@spec ensure_registration_enabled(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
defp ensure_registration_enabled(conn, _opts) do
  if Application.get_env(:my_app, :user_registration_enabled, true) do
    conn
  else
    conn
    |> put_flash(:error, "New account registration is temporarily unavailable.")
    |> redirect(to: ~p"/users/log-in")
    |> halt()
  end
end
```

**Important:** The plug must be added BEFORE any action functions so it runs on every request.

### Step 4: Conditionally hide the signup link on the login page

Find the login template (typically `user_session_html/new.html.heex`) and wrap the "Sign up" / "Register" link in a conditional:

```heex
<%= if Application.get_env(:my_app, :user_registration_enabled, true) do %>
  <p class="...">
    Don't have an account?
    <.link navigate={~p"/users/register"} class="...">Sign up</.link>
  </p>
<% end %>
```

This prevents confusion — users won't see a signup link that leads to a redirect.

### Step 5: Add test coverage

Create or update tests for the registration controller:

```elixir
describe "registration toggle" do
  test "allows registration when enabled", %{conn: conn} do
    Application.put_env(:my_app, :user_registration_enabled, true)
    on_exit(fn -> Application.delete_env(:my_app, :user_registration_enabled) end)

    conn = get(conn, ~p"/users/register")
    assert html_response(conn, 200) =~ "Register"
  end

  test "redirects when registration is disabled", %{conn: conn} do
    Application.put_env(:my_app, :user_registration_enabled, false)
    on_exit(fn -> Application.delete_env(:my_app, :user_registration_enabled) end)

    conn = get(conn, ~p"/users/register")
    assert redirected_to(conn) == "/users/log-in"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "unavailable"
  end
end
```

**Note:** These tests must NOT be `async: true` since they modify application env.

### Step 6: Verify

Run `mix test` to ensure nothing is broken.

## Summary of Changes

| File | Change |
|------|--------|
| `config/runtime.exs` | Add `boolean_env` helper (if needed) + registration config |
| Registration controller | Add `ensure_registration_enabled` plug |
| Login template | Wrap signup link in registration-enabled conditional |
| Registration controller test | Add toggle on/off test cases |

## ENV Variable Reference

| Variable | Values | Default |
|----------|--------|---------|
| `{APP}_USER_REGISTRATION_ENABLED` | `true`/`1`/`yes` or `false`/`0`/`no` | `true` in dev/test, `false` in prod |
