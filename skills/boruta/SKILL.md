---
name: boruta
description: "Add Boruta OAuth 2.0 and OpenID Connect provider to Phoenix apps. Dispatches subcommands via `/boruta [subcommand]`. Use when the user says '/boruta bootstrap', '/boruta help', 'add oauth', 'add openid', 'oauth provider', 'openid connect', 'boruta', or wants to set up OAuth 2.0 / OIDC in a Phoenix application."
---

# Boruta

Add a standards-compliant OAuth 2.0 and OpenID Connect provider to an existing Phoenix application using Boruta. Integrates non-intrusively with your existing authentication system (phx.gen.auth, Guardian, Pow, or custom).

## Subcommands

| Subcommand | Purpose |
|------------|---------|
| `bootstrap` | Add Boruta to a Phoenix app (deps, migrations, controllers, config, resource owners) |

### `/boruta help`

Display a list of all available subcommands. Output the following exactly:

```
/boruta subcommands:

  bootstrap   — Add OAuth 2.0 + OpenID Connect to your Phoenix app
  help        — Show this help message
```

If `/boruta` is invoked without a subcommand, default to `bootstrap`.

## Dispatch

1. Parse the subcommand from the user's invocation. Examples:
   - `/boruta` → default to `bootstrap`
   - `/boruta bootstrap` → subcommand `bootstrap`
   - `/boruta help` → show help
2. If the subcommand is unknown, list available subcommands and stop.
3. Follow the matching workflow below.

---

## `/boruta bootstrap`

Add Boruta OAuth 2.0 + OpenID Connect provider to an existing Phoenix application.

### Prerequisites

Before starting, verify:
- The project is a Phoenix app with Ecto (`mix.exs` has `:phoenix` and `:ecto_sql`)
- The app has an existing authentication system with a users table
- PostgreSQL is running

### Phase 1: Detect the app

1. Read `mix.exs` to find the app name, main module prefix (e.g., `MyApp`), web module (e.g., `MyAppWeb`), and Repo module.
2. Read `lib/<app>/application.ex` to understand the supervision tree.
3. Find the existing user schema — search for a module with `schema "users"`. Note:
   - The user module path (e.g., `MyApp.Accounts.User`)
   - The unique identifier field (usually `email`)
   - The password validation function (e.g., `valid_password?/2`)
4. Find the existing auth pipeline — look in `router.ex` for plugs like `:fetch_current_user`, `:require_authenticated_user`, or similar.
5. Find the login route — look for session-related routes (e.g., `/users/log_in`, `/session/new`).

### Phase 2: Add dependency

Add to `deps` in `mix.exs`:

```elixir
{:boruta, "~> 2.0"}
```

Run `mix deps.get`.

### Phase 3: Generate Boruta files

Run the Boruta generators:

```bash
mix boruta.gen.migration
mix ecto.migrate
mix boruta.gen.controllers
```

**Important:** Read the output of `mix boruta.gen.controllers` — it lists exact next steps for the app. The generator creates files under:
- `lib/<app_web>/controllers/oauth/` — token, revoke, introspect, authorize controllers
- `lib/<app_web>/controllers/openid/` — OpenID authorize controller

### Phase 4: Add routes

Add OAuth and OpenID routes to `lib/<app_web>/router.ex`. Place these after existing route scopes:

```elixir
# OAuth API endpoints (token exchange, revocation, introspection)
scope "/oauth", <AppWeb>.Oauth do
  pipe_through :api

  post "/token", TokenController, :token
  post "/revoke", RevokeController, :revoke
  post "/introspect", IntrospectController, :introspect
end

# OAuth authorization endpoint (user-facing, requires browser + auth)
scope "/oauth", <AppWeb>.Oauth do
  pipe_through [:browser, :fetch_current_user]

  get "/authorize", AuthorizeController, :authorize
end

# OpenID Connect authorization endpoint
scope "/openid", <AppWeb>.Openid do
  pipe_through [:browser, :fetch_current_user]

  get "/authorize", AuthorizeController, :authorize
end
```

Replace `:fetch_current_user` with whatever plug the app uses to load the current user into `conn.assigns.current_user`. If the app uses a different assign key, note it for the authorize controller update.

### Phase 5: Configure Boruta

Add to `config/config.exs`:

```elixir
config :boruta, Boruta.Oauth,
  repo: <App>.Repo,
  issuer: "http://localhost:4000"
```

Add to `config/runtime.exs` (for production):

```elixir
config :boruta, Boruta.Oauth,
  repo: <App>.Repo,
  issuer: System.get_env("BORUTA_ISSUER") || "http://localhost:4000",
  contexts: [
    resource_owners: <App>.ResourceOwners
  ]
```

Add to `.env.sample` (if it exists):

```
BORUTA_ISSUER=https://your-domain.com
```

### Phase 6: Create ResourceOwners module

This is the critical integration point — it bridges Boruta to the existing user system.

Create `lib/<app>/resource_owners.ex`:

```elixir
defmodule <App>.ResourceOwners do
  @behaviour Boruta.Oauth.ResourceOwners

  alias Boruta.Oauth.ResourceOwner
  alias <App>.<UserModule>
  alias <App>.Repo

  @impl true
  def get_by(username: username) do
    case Repo.get_by(<UserModule>, <identifier_field>: username) do
      %<UserModule>{id: id, <identifier_field>: identifier} ->
        {:ok, %ResourceOwner{sub: to_string(id), username: identifier}}

      _ ->
        {:error, "User not found"}
    end
  end

  @impl true
  def get_by(sub: sub) do
    case Repo.get(<UserModule>, sub) do
      %<UserModule>{id: id, <identifier_field>: identifier} ->
        {:ok, %ResourceOwner{sub: to_string(id), username: identifier}}

      _ ->
        {:error, "User not found"}
    end
  end

  @impl true
  def check_password(resource_owner, password) do
    user = Repo.get(<UserModule>, resource_owner.sub)

    if user && <UserModule>.valid_password?(user, password) do
      :ok
    else
      {:error, "Invalid credentials"}
    end
  end

  @impl true
  def authorized_scopes(_resource_owner), do: []

  @impl true
  def claims(_resource_owner, _scope), do: %{}
end
```

Replace placeholders:
- `<App>` — app module prefix (e.g., `MyApp`)
- `<UserModule>` — user schema module (e.g., `Accounts.User` or just `User`)
- `<identifier_field>` — the field used for login (usually `:email`)
- `valid_password?/2` — the actual password check function from the user schema

### Phase 7: Update authorize controllers

Update the generated authorize controllers to redirect unauthenticated users to the existing login page.

In `lib/<app_web>/controllers/oauth/authorize_controller.ex`, find or add:

```elixir
defp handle_unauthenticated(conn, _params) do
  redirect(conn, to: ~p"<login_path>")
end
```

Do the same in `lib/<app_web>/controllers/openid/authorize_controller.ex`.

Replace `<login_path>` with the app's actual login route (e.g., `/users/log_in`).

### Phase 8: Register ResourceOwners in config

Update the Boruta config in `config/config.exs` to include the contexts:

```elixir
config :boruta, Boruta.Oauth,
  repo: <App>.Repo,
  issuer: "http://localhost:4000",
  contexts: [
    resource_owners: <App>.ResourceOwners
  ]
```

### Phase 9: Verify

1. Start the app: `mix phx.server`
2. Check that existing auth still works (login, logout, protected pages).
3. Test the OAuth endpoints:
   - `POST /oauth/token` — should return 400 (missing params, proves route works)
   - `GET /oauth/authorize` — should redirect to login if not authenticated
4. Create a test client in IEx:
   ```elixir
   iex> Boruta.Ecto.Admin.create_client(%{name: "Test Client", redirect_uris: ["http://localhost:4001/callback"]})
   ```

### Phase 10: Summary

Tell the user what was added:
- Boruta dependency
- Database migrations for OAuth tables (clients, tokens, scopes)
- OAuth controllers (token, revoke, introspect, authorize)
- OpenID Connect authorize controller
- Routes for `/oauth/*` and `/openid/*`
- `ResourceOwners` module bridging Boruta to existing users
- Boruta configuration with issuer and resource owners context

Suggest next steps:
- Create OAuth clients for each application that needs to authenticate
- Customize scopes, token lifetimes, and claims in the ResourceOwners module
- Add rate limiting on `/oauth/token` for production
- Ensure the `issuer` URL matches the production domain and uses HTTPS
- Monitor the tokens table for growth — consider periodic cleanup
- Reference: https://hexdocs.pm/boruta/provider_integration.html

---

## Quick Reference

### Supported OAuth 2.0 Flows

| Flow | Use Case |
|------|----------|
| Authorization Code + PKCE | Web and mobile apps |
| Client Credentials | Machine-to-machine |
| Token Introspection | Validate tokens from resource servers |
| Token Revocation | Logout / invalidate tokens |

### Endpoints

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/oauth/authorize` | GET | User authorization (browser) |
| `/oauth/token` | POST | Token exchange |
| `/oauth/revoke` | POST | Token revocation |
| `/oauth/introspect` | POST | Token introspection |
| `/openid/authorize` | GET | OpenID Connect authorization |

### Key Modules

| Module | Purpose |
|--------|---------|
| `Boruta.Oauth` | Core OAuth 2.0 logic |
| `Boruta.Oauth.ResourceOwners` | Behaviour for user integration |
| `Boruta.Ecto.Admin` | Client and scope management |
| `<App>.ResourceOwners` | Your app's implementation bridging to existing users |

$ARGUMENTS
