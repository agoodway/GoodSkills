---
name: bootstrap-posthog
description: >
  Bootstrap PostHog analytics in a Phoenix 1.8 app. Adds the posthog hex dependency, server-side
  tracking module, analytics context, page view plug, LiveView helpers, client-side JS snippet with
  user identification, and config for dev/prod. Use when the user says "bootstrap posthog",
  "add posthog", "setup posthog", "posthog analytics", or wants to add PostHog event tracking
  to a Phoenix app.
---

# Bootstrap PostHog Analytics

Add full PostHog analytics to a Phoenix 1.8 app — server-side event tracking, automatic page view plug, LiveView helpers, and client-side JS with user identification.

## What Gets Created/Configured

1. **mix.exs** — `{:posthog, "~> 0.2"}` dependency
2. **config/config.exs** — PostHog config with `enabled: true` (uses env vars for API key)
3. **config/runtime.exs** — Production PostHog config with `System.fetch_env!`
4. **lib/<app>/analytics/posthog.ex** — Server-side PostHog wrapper module
5. **lib/<app>/analytics.ex** — Analytics context with domain event helpers
6. **lib/<app>_web/plugs/analytics.ex** — Automatic page view tracking plug
7. **lib/<app>_web/live/analytics_helpers.ex** — LiveView tracking helpers
8. **root.html.heex** — Client-side PostHog JS snippet with user identification
9. **assets/js/app.js** — `phx:track-analytics` event listener and `TrackView` hook
10. **.env.sample** — `POSTHOG_API_KEY` and `POSTHOG_API_URL` entries

## App Name Detection

Detect from `mix.exs`:
- **App module prefix** (e.g., `MyApp`) — the module namespace
- **OTP app name** (e.g., `:my_app`) — used in config atoms
- **Web module prefix** (e.g., `MyAppWeb`) — for web module references

Also detect:
- **Root layout file** — Look for `root.html.heex` in `lib/<app>_web/components/layouts/`
- **User schema** — Find the user schema module and its fields (email, id, is_admin, etc.)
- **Auth scope assign** — Check if the app uses `current_scope`, `current_user`, or similar
- **Existing PostHog config** — Check all config files for existing `:posthog` settings
- **Router pipelines** — Identify the browser pipeline for plug placement

## Phase 0: Discovery

**CRITICAL: Audit the target app before making any changes.**

### Discovery Checklist

1. **Root layout** — Locate `root.html.heex` in `lib/<app>_web/components/layouts/`
   - If missing: stop and notify user — the layout must exist

2. **Existing PostHog** — Search for `posthog` in mix.exs, config files, and layouts
   - If found: report what exists and skip those parts

3. **User schema** — Find the user module to determine:
   - Field names (email, id, is_admin, inserted_at, etc.)
   - The assign name used in templates (`@current_scope`, `@current_user`, etc.)

4. **Router** — Find the browser pipeline to know where to add the analytics plug

5. **app.js** — Check for existing PostHog listeners or hooks

6. **Existing config** — Check each config file:
   - `config/config.exs` — look for `:posthog` config
   - `config/runtime.exs` — look for `:posthog` in `if config_env() == :prod` block

7. **.env.sample** — Check for existing `POSTHOG_API_KEY` entry

### Discovery Report

Present findings to user. If PostHog is already fully configured, confirm and skip. Otherwise show what will be added/changed.

## Phase 1: Dependencies

### Step 1: Add Hex Dependency (mix.exs)

Add to the deps list if not present:
```elixir
{:posthog, "~> 0.2"}
```

Run `mix deps.get` after adding.

## Phase 2: Configuration

### Step 2: Base Config (config/config.exs)

Add if not present:
```elixir
# PostHog Analytics Configuration
config :posthog,
  api_key: System.get_env("POSTHOG_API_KEY"),
  api_url: System.get_env("POSTHOG_API_URL", "https://app.posthog.com")

# Optional: Configure for different environments
config :<otp_app>, :posthog,
  enabled: true,
  distinct_id_from_user: true
```

### Step 3: Runtime Config (config/runtime.exs)

Inside the `if config_env() == :prod do` block, add:
```elixir
  # PostHog Analytics Configuration for Production
  config :posthog,
    api_key: System.fetch_env!("POSTHOG_API_KEY"),
    api_url: System.get_env("POSTHOG_API_URL", "https://app.posthog.com")

  config :<otp_app>, :posthog,
    enabled: true,
    distinct_id_from_user: true
```

**Important:** Place this inside the existing `if config_env() == :prod do` block — do not create a duplicate conditional.

### Step 4: Environment File (.env.sample)

Add these entries if not already present:
```
# PostHog Analytics
POSTHOG_API_KEY=
POSTHOG_API_URL=https://app.posthog.com
```

## Phase 3: Server-Side Modules

### Step 5: PostHog Wrapper Module

Create `lib/<app>/analytics/posthog.ex`:

```elixir
defmodule <AppModule>.Analytics.PostHog do
  @moduledoc """
  Wrapper module for PostHog analytics integration.

  This module provides a centralized interface for tracking events,
  identifying users, and managing analytics with PostHog.
  """

  require Logger

  @doc """
  Tracks an event with PostHog.

  ## Examples

      track("user_signed_up", user_id, %{plan: "premium"})
      track("page_viewed", session_id, %{path: "/dashboard"})
  """
  @spec track(String.t(), String.t(), map()) :: :ok | {:error, term()}
  def track(event, distinct_id, properties \\ %{}) do
    if enabled?() do
      properties =
        properties
        |> Map.put(:timestamp, DateTime.utc_now() |> DateTime.to_iso8601())
        |> Map.put(:app_version, Application.spec(:<otp_app>, :vsn) |> to_string())

      case Posthog.capture(event, [distinct_id: distinct_id] ++ Map.to_list(properties)) do
        {:ok, _} ->
          Logger.debug("PostHog event tracked: #{event}")
          :ok

        {:error, reason} ->
          Logger.error("PostHog tracking failed: #{inspect(reason)}")
          {:error, reason}
      end
    else
      :ok
    end
  end

  @doc """
  Identifies a user with traits.

  ## Examples

      identify("user_123", %{email: "user@example.com", name: "Jane"})
  """
  @spec identify(String.t(), map()) :: :ok | {:error, term()}
  def identify(distinct_id, traits \\ %{}) do
    if enabled?() do
      track("$identify", distinct_id, traits)
    else
      :ok
    end
  end

  @doc """
  Creates an alias between two distinct IDs.
  Useful when a user signs up after browsing anonymously.

  ## Examples

      alias_user(anonymous_id, "user_123")
  """
  @spec alias_user(String.t(), String.t()) :: :ok | {:error, term()}
  def alias_user(from_distinct_id, to_distinct_id) do
    if enabled?() do
      track("$create_alias", from_distinct_id, %{alias: to_distinct_id})
    else
      :ok
    end
  end

  @doc """
  Tracks a page view event.
  """
  @spec track_page_view(String.t(), String.t(), map()) :: :ok | {:error, term()}
  def track_page_view(distinct_id, path, properties \\ %{}) do
    properties =
      Map.merge(properties, %{
        path: path,
        referrer: Map.get(properties, :referrer),
        user_agent: Map.get(properties, :user_agent)
      })

    track("$pageview", distinct_id, properties)
  end

  @doc """
  Checks if PostHog tracking is enabled.
  """
  @spec enabled?() :: boolean()
  def enabled? do
    Application.get_env(:<otp_app>, :posthog, [])
    |> Keyword.get(:enabled, true)
  end

  @doc """
  Gets the distinct ID for a user or session.
  """
  @spec get_distinct_id(Plug.Conn.t()) :: String.t()
  def get_distinct_id(conn) do
    case conn.assigns[:<current_user_assign>] do
      # ADAPT: Match the user struct shape in this app
      %{user: %{id: user_id}} -> "user_#{user_id}"
      %{id: user_id} -> "user_#{user_id}"
      _ -> get_or_create_anonymous_id(conn)
    end
  end

  defp get_or_create_anonymous_id(conn) do
    case Plug.Conn.get_session(conn, :anonymous_id) do
      nil ->
        anonymous_id = "anon_#{Ecto.UUID.generate()}"
        Plug.Conn.put_session(conn, :anonymous_id, anonymous_id)
        anonymous_id

      id ->
        id
    end
  end
end
```

**ADAPT `get_distinct_id/1`:** The pattern match on `conn.assigns` must match the app's auth system:
- If the app uses `current_scope` with a nested user: `conn.assigns[:current_scope] |> then(& &1.user)`
- If the app uses `current_user` directly: `conn.assigns[:current_user]`
- Check the router/auth plugs to determine the correct assign name and shape

### Step 6: Analytics Context Module

Create `lib/<app>/analytics.ex`:

```elixir
defmodule <AppModule>.Analytics do
  @moduledoc """
  The Analytics context for tracking user behavior and application metrics.
  """

  alias <AppModule>.Accounts.User
  alias <AppModule>.Analytics.PostHog

  @doc """
  Tracks user signup event.
  """
  @spec track_user_signup(User.t()) :: :ok | {:error, term()}
  def track_user_signup(%User{} = user) do
    PostHog.identify("user_#{user.id}", %{
      email: user.email,
      created_at: user.inserted_at
    })

    PostHog.track("user_signed_up", "user_#{user.id}", %{
      signup_method: "email"
    })
  end

  @doc """
  Tracks user login event.
  """
  @spec track_user_login(User.t(), String.t()) :: :ok | {:error, term()}
  def track_user_login(%User{} = user, method \\ "email") do
    PostHog.track("user_logged_in", "user_#{user.id}", %{
      login_method: method
    })
  end
end
```

**Note:** The analytics context starts minimal with signup/login tracking. The user should add domain-specific event tracking functions as needed (e.g., `track_order_placed/2`, `track_feature_used/2`).

### Step 7: Analytics Plug

Create `lib/<app>_web/plugs/analytics.ex`:

```elixir
defmodule <WebModule>.Plugs.Analytics do
  @moduledoc """
  Plug for tracking page view analytics events automatically.
  """

  import Plug.Conn
  alias <AppModule>.Analytics.PostHog

  @spec init(Keyword.t()) :: Keyword.t()
  def init(opts), do: opts

  @doc """
  Tracks page views for GET requests to non-static, non-admin routes.
  Runs asynchronously to avoid blocking the request.
  """
  @spec call(Plug.Conn.t(), Keyword.t()) :: Plug.Conn.t()
  def call(conn, _opts) do
    if conn.method == "GET" && should_track?(conn) do
      Task.start(fn ->
        distinct_id = PostHog.get_distinct_id(conn)

        PostHog.track_page_view(distinct_id, conn.request_path, %{
          referrer: get_req_header(conn, "referer") |> List.first(),
          user_agent: get_req_header(conn, "user-agent") |> List.first(),
          ip: to_string(:inet_parse.ntoa(conn.remote_ip))
        })
      end)
    end

    conn
  end

  @spec should_track?(Plug.Conn.t()) :: boolean()
  defp should_track?(conn) do
    !String.starts_with?(conn.request_path, ["/api", "/admin", "/dev"]) &&
      !String.contains?(conn.request_path, [".", "assets"])
  end
end
```

### Step 8: LiveView Analytics Helpers

Create `lib/<app>_web/live/analytics_helpers.ex`:

```elixir
defmodule <WebModule>.Live.AnalyticsHelpers do
  @moduledoc """
  Helper functions for tracking analytics in LiveView components.
  """

  import Phoenix.LiveView
  alias <AppModule>.Analytics.PostHog

  @doc """
  Tracks an event from a LiveView (server-side).
  """
  @spec track_event(Phoenix.LiveView.Socket.t(), String.t(), map()) :: Phoenix.LiveView.Socket.t()
  def track_event(socket, event, properties \\ %{}) do
    distinct_id = get_distinct_id(socket)

    Task.start(fn ->
      PostHog.track(event, distinct_id, properties)
    end)

    socket
  end

  @doc """
  Pushes a JavaScript event to track on the client side via PostHog JS.
  """
  @spec push_track_event(Phoenix.LiveView.Socket.t(), String.t(), map()) ::
          Phoenix.LiveView.Socket.t()
  def push_track_event(socket, event, properties \\ %{}) do
    push_event(socket, "track-analytics", %{
      event: event,
      properties: properties
    })
  end

  @spec get_distinct_id(Phoenix.LiveView.Socket.t()) :: String.t()
  defp get_distinct_id(socket) do
    # ADAPT: Match the app's auth assign shape
    case socket.assigns[:<current_user_assign>] do
      %{user: %{id: user_id}} -> "user_#{user_id}"
      %{id: user_id} -> "user_#{user_id}"
      _ -> "anon_#{socket.id}"
    end
  end
end
```

## Phase 4: Client-Side Integration

### Step 9: Root Layout JS Snippet (root.html.heex)

Add before the closing `</head>` tag:

```heex
<%= if Application.get_env(:<otp_app>, :posthog)[:enabled] do %>
  <script>
    !function(t,e){var o,n,p,r;e.__SV||(window.posthog=e,e._i=[],e.init=function(i,s,a){function g(t,e){var o=e.split(".");2==o.length&&(t=t[o[0]],e=o[1]),t[e]=function(){t.push([e].concat(Array.prototype.slice.call(arguments,0)))}}(p=t.createElement("script")).type="text/javascript",p.async=!0,p.src=s.api_host+"/static/array.js",(r=t.getElementsByTagName("script")[0]).parentNode.insertBefore(p,r);var u=e;for(void 0!==a?u=e[a]=[]:a="posthog",u.people=u.people||[],u.toString=function(t){var e="posthog";return"posthog"!==a&&(e+="."+a),t||(e+=" (stub)"),e},u.people.toString=function(){return u.toString(1)+".people (stub)"},o="capture identify alias people.set people.set_once set_config register register_once unregister opt_out_capturing has_opted_out_capturing opt_in_capturing reset isFeatureEnabled onFeatureFlags getFeatureFlag getFeatureFlagPayload reloadFeatureFlags group updateEarlyAccessFeatureEnrollment getEarlyAccessFeatures getActiveMatchingSurveys getSurveys".split(" "),n=0;n<o.length;n++)g(u,o[n]);e._i.push([i,s,a])},e.__SV=1)}(document,window.posthog||[]);
    posthog.init('<%= System.get_env("POSTHOG_API_KEY") %>',{
      api_host:'<%= System.get_env("POSTHOG_API_URL", "https://app.posthog.com") %>',
      <%%= if assigns[:<current_user_assign>] && <user_access_expression> do %>
      loaded: function(posthog) {
        posthog.identify('user_<%%= <user_id_expression> %>', {
          email: '<%%= <user_email_expression> %>'
        });
      }
      <%% end %>
    })
  </script>
<% end %>
```

**ADAPT the user identification block:**
- For `current_scope` with nested user: `@current_scope.user` / `@current_scope.user.id` / `@current_scope.user.email`
- For `current_user` directly: `@current_user` / `@current_user.id` / `@current_user.email`
- Add any extra traits relevant to the app (e.g., `is_admin`, `plan`, `organization`)

### Step 10: App.js Event Listener and Hook

Add to `assets/js/app.js` (near the top, before hooks):

```javascript
// PostHog Analytics Handler — receives events from LiveView server
window.addEventListener("phx:track-analytics", (e) => {
  if (typeof posthog !== 'undefined') {
    posthog.capture(e.detail.event, e.detail.properties);
  }
});
```

Add the `TrackView` hook to the hooks object:

```javascript
let Hooks = {
  TrackView: {
    mounted() {
      if (typeof posthog !== 'undefined') {
        posthog.capture('$pageview', {
          path: window.location.pathname
        });
      }
    }
  },
  // ... other hooks
};
```

**Important:** If the app already has a `Hooks` object or uses a different hook registration pattern, integrate into the existing structure rather than creating a new one.

## Phase 5: Router Integration

### Step 11: Add Analytics Plug to Browser Pipeline

In `lib/<app>_web/router.ex`, add the plug to the browser pipeline:

```elixir
pipeline :browser do
  plug :accepts, ["html"]
  plug :fetch_session
  plug :fetch_live_flash
  plug :put_root_layout, html: {<WebModule>.Layouts, :root}
  plug :protect_from_forgery
  plug :put_secure_browser_headers
  plug <WebModule>.Plugs.Analytics    # <-- Add this
end
```

**Placement:** Add after the standard Phoenix plugs but before any auth plugs. The analytics plug needs the session (for anonymous ID tracking) but should run before auth to track all visitors.

## Phase 6: Verification

1. Run `mix deps.get` to install the posthog dependency
2. Run `mix compile --warnings-as-errors` to verify everything compiles
3. Run `mix test` to ensure no regressions
4. Tell the user to:
   - Set `POSTHOG_API_KEY` in their `.env` file (find it in PostHog: Project Settings > API Key)
   - Optionally set `POSTHOG_API_URL` if using a self-hosted PostHog instance
   - Set `POSTHOG_API_KEY` in production environment (required — uses `fetch_env!`)

## Usage Examples

After bootstrapping, the user can track events like this:

### From Controllers
```elixir
alias MyApp.Analytics

def create(conn, params) do
  case Accounts.register_user(params) do
    {:ok, user} ->
      Analytics.track_user_signup(user)
      # ...
  end
end
```

### From LiveViews
```elixir
import MyAppWeb.Live.AnalyticsHelpers

def handle_event("submit", params, socket) do
  socket = track_event(socket, "form_submitted", %{form: "contact"})
  # ...
  {:noreply, socket}
end

# Or push to client-side JS:
def handle_event("upgrade", _params, socket) do
  socket = push_track_event(socket, "upgrade_clicked", %{plan: "pro"})
  {:noreply, socket}
end
```

### Adding Domain Events
Add new tracking functions to the Analytics context:
```elixir
def track_order_placed(order, user) do
  PostHog.track("order_placed", "user_#{user.id}", %{
    order_id: order.id,
    total: order.total,
    item_count: length(order.items)
  })
end
```

## Notes

- All server-side tracking runs in async `Task.start/1` — never blocks the request
- The posthog hex package handles HTTP communication with PostHog's API
- Anonymous users get a UUID-based ID stored in the session, aliased on signup
- The `enabled?()` check means tracking is a no-op when PostHog isn't configured
- Client-side JS snippet loads asynchronously and won't block page rendering
- The `TrackView` hook enables page view tracking for LiveView navigation (no full page reload)
- For GDPR compliance, consider adding a cookie consent mechanism — PostHog sets cookies by default
- To disable tracking in dev, set `enabled: false` in `config/dev.exs`:
  ```elixir
  config :<otp_app>, :posthog, enabled: false
  ```
