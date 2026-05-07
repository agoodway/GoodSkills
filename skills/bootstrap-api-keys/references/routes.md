# Routes: Router Configuration

## LiveView Route

Add to the appropriate `live_session` block in `router.ex`:

```elixir
# Inside an authenticated live_session:
live "/api-keys", ApiKeyLive.Index, :index
```

### Example: Adding to an existing authenticated live_session

```elixir
live_session :authenticated,
  on_mount: [{MyAppWeb.UserAuth, :ensure_authenticated}] do
  # ... existing routes
  live "/api-keys", ApiKeyLive.Index, :index
end
```

### Example: Account-scoped route

```elixir
scope "/dashboard/accounts/:account_id", MyAppWeb do
  pipe_through [:browser, :require_authenticated_user, :load_account]

  live_session :account_scoped,
    on_mount: [
      {MyAppWeb.UserAuth, :ensure_authenticated},
      {MyAppWeb.UserAuth, :load_account_context}
    ] do
    live "/api-keys", ApiKeyLive.Index, :index
  end
end
```

## API Pipelines (for Bearer token auth)

Add these pipelines to the router if they don't already exist:

```elixir
pipeline :api do
  plug :accepts, ["json"]
end

pipeline :api_authenticated do
  plug MyAppWeb.Plugs.ApiAuth
end

# Only needed if using public/private key types
pipeline :api_write do
  plug MyAppWeb.Plugs.ApiAuth, :require_write_access
end
```

### API Route Usage Example

```elixir
scope "/api/v1", MyAppWeb.Api do
  pipe_through [:api, :api_authenticated]

  # Read-only endpoints (any key works)
  get "/things", ThingController, :index
  get "/things/:id", ThingController, :show
end

scope "/api/v1", MyAppWeb.Api do
  pipe_through [:api, :api_authenticated, :api_write]

  # Write endpoints (require private sk_* key)
  post "/things", ThingController, :create
  put "/things/:id", ThingController, :update
  delete "/things/:id", ThingController, :delete
end
```

## Sidebar Navigation

If using a sidebar layout, add an entry for API keys:

```elixir
# In your layout or sidebar component:
<.sidebar_link
  icon="hero-key"
  label="API Keys"
  to={~p"/api-keys"}
  active={@active_nav == :api_keys}
/>
```
