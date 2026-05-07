---
name: bootstrap-mcp
description: "Bootstrap MCP Server for Phoenix"
---

# Bootstrap MCP Server for Phoenix

Set up a Model Context Protocol (MCP) server in your Phoenix application using the [Anubis MCP](https://github.com/zoedsoupe/anubis-mcp) library. This includes:
- MCP server with Streamable HTTP transport
- Bearer token authentication via existing API keys
- Scope-based authorization
- Component-based tool registration
- Session store for Claude Code compatibility
- Base helpers for common patterns
- Example tool component

**Prerequisites:**
- Phoenix 1.7+ application with PostgreSQL
- **Run `/bootstrap-openapi` first** - This command requires:
  - `Accounts.authenticate_api_key/1` function
  - ApiKey struct with `id` and `scopes` fields

## What is MCP?

**Model Context Protocol (MCP)** is an open protocol that standardizes how AI applications provide context to Large Language Models (LLMs). It enables Claude (or other AI assistants) to interact with your application's data and operations in a structured, secure way.

### Key Concepts

- **Server**: The MCP server process that handles client connections
- **Frame**: Contains server state, registered tools, and request context
- **Session**: Per-client state that persists across requests
- **Components**: Tools, resources, and prompts that the server exposes
- **Transport**: Communication layer (Streamable HTTP, SSE, stdio, WebSocket)

**Tools**: Operations that the LLM can invoke (similar to function calling). Examples:
- `list_users` - Retrieve a paginated list of users
- `create_order` - Create a new order
- `search_documents` - Search through documents

### How It Works

```
Claude CLI → HTTP → Your Phoenix MCP Server → Your Business Logic → Response → Claude
```

1. Claude sends a request to your MCP server over HTTP
2. Your server authenticates the request using Bearer token
3. Claude invokes a tool (e.g., "list_users")
4. Your server validates permissions (scopes) and executes the operation
5. Results are returned as JSON and Claude uses them to respond to the user

## Architecture

```
Phoenix Application
├── lib/your_app_web/mcp/
│   ├── supervisor.ex         # Supervision tree
│   ├── server.ex             # MCP server implementation
│   ├── plug.ex               # HTTP authentication layer
│   ├── session_store.ex      # Session management for Claude Code
│   └── components/
│       ├── base.ex           # Shared utilities
│       └── [domain].ex       # Your business logic tools
└── lib/your_app/
    └── accounts.ex           # API key authentication (from bootstrap-openapi)
```

### Request Flow

```
1. HTTP Request with Bearer token
   ↓
2. MCP.Plug validates token early (rejects invalid requests)
   ↓
3. Anubis routes to MCP.Server
   ↓
4. Server.init/2 sets up frame with authentication
   ↓
5. Client sends tool call request
   ↓
6. Anubis routes to registered component
   ↓
7. Component validates scope via Base.with_scope/3
   ↓
8. Component executes business logic
   ↓
9. Response formatted and returned
```

## Design Decisions

### Why Two-Stage Authentication?

The Plug validates early to reject bad requests fast, but the MCP Server runs in a separate process and can't access the Plug's assigns. Each process must independently authenticate because:
- Process isolation: Can't share assigns across process boundaries
- Server might be restarted independently
- Security: Never trust external state in long-lived processes

### Why :rest_for_one Supervision?

When the MCP server crashes, we restart the registry too because:
- Old client sessions in the registry become stale
- Forces clients to reconnect and re-authenticate
- Ensures clean state after crashes
- Registry → Server dependency order is critical

### Why a Custom Session Store?

Claude Code (and some other MCP clients) may skip the standard MCP initialization handshake and jump directly to tool calls. The custom session store handles this by returning pre-initialized sessions for unknown session IDs.

### Why Compile-Time Component Registration?

Tools registered via the `component` macro are preferred over runtime registration because:
- They work even when clients skip initialization
- No need to maintain frame state across requests
- Tools are available immediately when the server starts

### Why Scope-Based Authorization?

Instead of role-based permissions, scopes provide:
- **Fine-grained control**: `users:read` vs `users:write` vs `users:delete`
- **API key flexibility**: Each key can have different capabilities
- **Audit trail**: Know exactly what each key can do
- **Least privilege**: Give keys only the scopes they need

## Phase 1: Add Anubis MCP Dependency

### 1.1 Update mix.exs

**File:** `mix.exs`

Add to the `deps/0` function:

```elixir
defp deps do
  [
    # ... existing deps
    {:anubis_mcp, "~> 0.17.0"}
  ]
end
```

Run:

```bash
mix deps.get
```

## Phase 2: Create Session Store

### 2.1 Create Session Store Module

This session store handles Claude Code clients that skip the MCP initialization sequence.

**File:** `lib/APP_NAME_web/mcp/session_store.ex`

```elixir
defmodule APP_NAMEWeb.MCP.SessionStore do
  @moduledoc """
  Custom session store for MCP that handles clients skipping initialization.

  Claude Code and some other MCP clients may not follow the standard
  initialization handshake, jumping directly to tool calls. This store
  returns pre-initialized sessions for unknown session IDs.
  """
  use GenServer
  @behaviour Anubis.Server.Session.Store

  @table_name :mcp_sessions
  @default_ttl :timer.minutes(30)

  # GenServer callbacks

  @impl GenServer
  def init(_opts) do
    table = :ets.new(@table_name, [:named_table, :public, :set])
    schedule_cleanup()
    {:ok, %{table: table}}
  end

  # Session Store callbacks

  @impl Anubis.Server.Session.Store
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl Anubis.Server.Session.Store
  def save(session_id, state, _opts \\ []) do
    expires_at = System.monotonic_time(:millisecond) + @default_ttl
    :ets.insert(@table_name, {session_id, state, expires_at})
    :ok
  end

  @impl Anubis.Server.Session.Store
  def load(session_id, _opts \\ []) do
    case :ets.lookup(@table_name, session_id) do
      [{^session_id, state, expires_at}] ->
        now = System.monotonic_time(:millisecond)

        if now < expires_at do
          # Ensure session is marked as initialized
          {:ok, Map.put(state, :initialized, true)}
        else
          :ets.delete(@table_name, session_id)
          {:error, :expired}
        end

      [] ->
        # Return pre-initialized session for new session IDs
        # This handles clients that skip the initialization sequence
        {:ok,
         %{
           id: session_id,
           initialized: true,
           log_level: "info",
           protocol_version: "2025-03-26",
           client_info: %{},
           client_capabilities: %{},
           pending_requests: %{}
         }}
    end
  end

  @impl Anubis.Server.Session.Store
  def delete(session_id, _opts \\ []) do
    :ets.delete(@table_name, session_id)
    :ok
  end

  @impl Anubis.Server.Session.Store
  def list_active(_opts \\ []) do
    now = System.monotonic_time(:millisecond)

    sessions =
      :ets.tab2list(@table_name)
      |> Enum.filter(fn {_id, _state, expires_at} -> now < expires_at end)
      |> Enum.map(fn {id, _state, _expires_at} -> id end)

    {:ok, sessions}
  end

  @impl Anubis.Server.Session.Store
  def update_ttl(session_id, ttl_ms, _opts \\ []) do
    case :ets.lookup(@table_name, session_id) do
      [{^session_id, state, _old_expires}] ->
        expires_at = System.monotonic_time(:millisecond) + ttl_ms
        :ets.insert(@table_name, {session_id, state, expires_at})
        :ok

      [] ->
        {:error, :not_found}
    end
  end

  @impl Anubis.Server.Session.Store
  def update(session_id, updates, _opts \\ []) do
    case :ets.lookup(@table_name, session_id) do
      [{^session_id, state, expires_at}] ->
        new_state = Map.merge(state, updates)
        :ets.insert(@table_name, {session_id, new_state, expires_at})
        :ok

      [] ->
        {:error, :not_found}
    end
  end

  @impl Anubis.Server.Session.Store
  def cleanup_expired(_opts \\ []) do
    now = System.monotonic_time(:millisecond)

    expired =
      :ets.tab2list(@table_name)
      |> Enum.filter(fn {_id, _state, expires_at} -> now >= expires_at end)

    Enum.each(expired, fn {id, _state, _expires_at} ->
      :ets.delete(@table_name, id)
    end)

    {:ok, length(expired)}
  end

  # Private

  @impl GenServer
  def handle_info(:cleanup, state) do
    cleanup_expired([])
    schedule_cleanup()
    {:noreply, state}
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, :timer.minutes(5))
  end
end
```

### 2.2 Configure Session Store

**File:** `config/config.exs` (NOT `dev.exs` — must be available in all environments)

Add the session store configuration:

```elixir
# MCP Session Store
config :anubis_mcp, :session_store,
  enabled: true,
  adapter: APP_NAMEWeb.MCP.SessionStore
```

**Important**: The `enabled: true` flag is required! Without it, Anubis won't use your session store. Place this in `config/config.exs` so it applies in dev, test, and prod.

## Phase 3: Create MCP Supervisor

### 3.1 Create Supervisor Module

**File:** `lib/APP_NAME_web/mcp/supervisor.ex`

```elixir
defmodule APP_NAMEWeb.MCP.Supervisor do
  @moduledoc """
  Supervisor for the MCP server subsystem.

  Uses :rest_for_one strategy so that if the MCP server crashes,
  the registry also restarts to clear stale sessions.
  """
  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children = [
      # Anubis registry for process naming
      Anubis.Server.Registry,

      # The MCP server
      {APP_NAMEWeb.MCP.Server,
       transport: :streamable_http,
       name: APP_NAMEWeb.MCP.Server}
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end

  @doc "Restart only the MCP server"
  def restart_server do
    Supervisor.terminate_child(__MODULE__, APP_NAMEWeb.MCP.Server)
    Supervisor.restart_child(__MODULE__, APP_NAMEWeb.MCP.Server)
  end

  @doc "Restart entire MCP subsystem"
  def restart_all do
    Supervisor.stop(__MODULE__, :normal)
  end
end
```

## Phase 4: Create Authentication Plug

### 4.1 Create MCP Plug

**File:** `lib/APP_NAME_web/mcp/plug.ex`

```elixir
defmodule APP_NAMEWeb.MCP.Plug do
  @moduledoc """
  Authenticates MCP requests using Bearer token.

  Validates early before forwarding to Anubis server.
  """
  import Plug.Conn

  alias Anubis.Server.Transport.StreamableHTTP.Plug, as: AnubisPlug
  alias APP_NAME.Accounts

  def init(opts), do: AnubisPlug.init(opts)

  def call(conn, opts) do
    with {:ok, token} <- extract_bearer_token(conn),
         {:ok, api_key} <- Accounts.authenticate_api_key(token) do
      conn
      |> assign(:api_key, api_key)
      |> put_resp_header("x-accel-buffering", "no")
      |> put_resp_header("cache-control", "no-cache, no-store, must-revalidate")
      |> AnubisPlug.call(opts)
    else
      {:error, :missing_auth} ->
        send_error(conn, 401, "Authorization header with Bearer token is required")

      {:error, :invalid_format} ->
        send_error(conn, 401, "Invalid Authorization header format. Expected: Bearer <token>")

      {:error, _reason} ->
        send_error(conn, 401, "Invalid or expired API key")
    end
  end

  defp extract_bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] when byte_size(token) > 0 ->
        {:ok, token}

      ["Bearer " <> _] ->
        {:error, :invalid_format}

      [_other] ->
        {:error, :invalid_format}

      [] ->
        {:error, :missing_auth}
    end
  end

  defp send_error(conn, status, message) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(%{error: message}))
    |> halt()
  end
end
```

## Phase 5: Create Base Component Helpers

### 5.1 Create Base Module

**File:** `lib/APP_NAME_web/mcp/components/base.ex`

```elixir
defmodule APP_NAMEWeb.MCP.Components.Base do
  @moduledoc """
  Shared utilities for all MCP tool components.
  """

  alias Anubis.Server.Response

  @doc """
  Unwraps Claude Code's properties wrapper.

  Claude Code wraps tool arguments in a `properties` key:
  - Sent: `{"properties": {"url": "...", "depth": 2}}`
  - Expected: `{"url": "...", "depth": 2}`
  """
  def unwrap_properties(%{properties: props}) when is_map(props), do: props
  def unwrap_properties(%{"properties" => props}) when is_map(props), do: props
  def unwrap_properties(params), do: params

  @doc "Wraps tool execution with scope validation"
  def with_scope(frame, required_scope, fun) do
    case validate_scope(frame, required_scope) do
      {:ok, api_key} ->
        try do
          fun.(api_key)
        rescue
          Ecto.NoResultsError ->
            {:reply, error_response("Resource not found"), frame}

          e ->
            require Logger
            Logger.error("Tool execution error: #{inspect(e)}")
            {:reply, error_response("Internal server error"), frame}
        end

      {:error, message} ->
        {:reply, error_response(message), frame}
    end
  end

  defp validate_scope(frame, required_scope) do
    case frame.assigns[:api_key] do
      nil ->
        {:error, "Authentication required"}

      api_key ->
        if required_scope in (api_key.scopes || []) do
          {:ok, api_key}
        else
          {:error, "Insufficient permissions. Required scope: #{required_scope}"}
        end
    end
  end

  @doc "Success response format"
  def success_response(data) do
    Response.tool()
    |> Response.text(Jason.encode!(%{success: true, data: data}))
  end

  @doc "List response with pagination metadata"
  def list_response(items, meta) do
    Response.tool()
    |> Response.text(Jason.encode!(%{success: true, data: items, meta: meta}))
  end

  @doc "Error response format"
  def error_response(message) do
    Response.tool()
    |> Response.text(Jason.encode!(%{success: false, error: message}))
    |> Map.put(:isError, true)
  end

  @doc "Format changeset errors"
  def changeset_error_response(changeset) do
    errors =
      Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
        Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
          opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
        end)
      end)

    error_response("Validation failed: #{Jason.encode!(errors)}")
  end

  @doc "Get pagination from arguments"
  def get_pagination(args) do
    args = unwrap_properties(args)
    page = Map.get(args, "page", 1) |> ensure_positive_integer(1)
    per_page = Map.get(args, "per_page", 50) |> ensure_positive_integer(50) |> min(250)
    {page, per_page}
  end

  @doc "Build pagination metadata"
  def build_meta(page, per_page, total_count) do
    total_pages = ceil(total_count / per_page)

    %{
      page: page,
      per_page: per_page,
      total_count: total_count,
      total_pages: total_pages,
      has_next: page < total_pages,
      has_prev: page > 1
    }
  end

  @doc "Escape LIKE wildcards to prevent SQL injection"
  def escape_like(nil), do: nil
  def escape_like(string) when is_binary(string) do
    string
    |> String.replace("\\", "\\\\")
    |> String.replace("%", "\\%")
    |> String.replace("_", "\\_")
  end

  defp ensure_positive_integer(value, _default) when is_integer(value) and value > 0, do: value
  defp ensure_positive_integer(_, default), do: default
end
```

## Phase 6: Create Your First Tool Component

### 6.1 Create Example Component

**File:** `lib/APP_NAME_web/mcp/components/example.ex`

```elixir
defmodule APP_NAMEWeb.MCP.Components.Example do
  @moduledoc """
  Example MCP tool component for listing examples.
  """
  use Anubis.Server.Component, type: :tool

  alias APP_NAMEWeb.MCP.Components.Base
  alias APP_NAME.YourContext

  @impl true
  def description, do: "List examples with pagination and search"

  # Define input schema using Peri DSL
  # Note: Include :properties field to handle Claude Code's wrapper
  schema do
    field :properties, :map
    field :page, :integer, doc: "Page number (1-indexed)"
    field :per_page, :integer, doc: "Results per page (max 250)"
    field :search, :string, doc: "Search query"
  end

  @impl true
  def execute(params, frame) do
    params = Base.unwrap_properties(params)

    Base.with_scope(frame, "examples:read", fn _api_key ->
      {page, per_page} = Base.get_pagination(params)
      search = Map.get(params, "search")

      {examples, total} = list_examples(page, per_page, search)
      data = Enum.map(examples, &serialize/1)
      meta = Base.build_meta(page, per_page, total)

      {:reply, Base.list_response(data, meta), frame}
    end)
  end

  # Private helpers

  defp list_examples(page, per_page, search) do
    import Ecto.Query

    query = from e in YourContext.Example

    query =
      if search do
        search_pattern = "%#{Base.escape_like(search)}%"
        where(query, [e], ilike(e.name, ^search_pattern))
      else
        query
      end

    total = APP_NAME.Repo.aggregate(query, :count)

    examples =
      query
      |> order_by([e], desc: e.inserted_at)
      |> limit(^per_page)
      |> offset(^((page - 1) * per_page))
      |> APP_NAME.Repo.all()

    {examples, total}
  end

  defp serialize(example) do
    %{
      id: example.id,
      name: example.name,
      description: example.description,
      inserted_at: DateTime.to_iso8601(example.inserted_at),
      updated_at: DateTime.to_iso8601(example.updated_at)
    }
  end
end
```

### 6.2 Create Example Get Component

**File:** `lib/APP_NAME_web/mcp/components/example_get.ex`

```elixir
defmodule APP_NAMEWeb.MCP.Components.ExampleGet do
  @moduledoc """
  MCP tool component for getting a single example.
  """
  use Anubis.Server.Component, type: :tool

  alias APP_NAMEWeb.MCP.Components.Base
  alias APP_NAME.YourContext

  @impl true
  def description, do: "Get a single example by ID"

  schema do
    field :properties, :map
    field :id, {:required, :string}, doc: "Example ID"
  end

  @impl true
  def execute(params, frame) do
    params = Base.unwrap_properties(params)

    Base.with_scope(frame, "examples:read", fn _api_key ->
      example = YourContext.get_example!(params["id"])
      {:reply, Base.success_response(serialize(example)), frame}
    end)
  end

  defp serialize(example) do
    %{
      id: example.id,
      name: example.name,
      description: example.description,
      inserted_at: DateTime.to_iso8601(example.inserted_at),
      updated_at: DateTime.to_iso8601(example.updated_at)
    }
  end
end
```

### 6.3 Create Example Create Component

**File:** `lib/APP_NAME_web/mcp/components/example_create.ex`

```elixir
defmodule APP_NAMEWeb.MCP.Components.ExampleCreate do
  @moduledoc """
  MCP tool component for creating examples.
  """
  use Anubis.Server.Component, type: :tool

  alias APP_NAMEWeb.MCP.Components.Base
  alias APP_NAME.YourContext

  @impl true
  def description, do: "Create a new example"

  schema do
    field :properties, :map
    field :name, {:required, :string}, doc: "Example name"
    field :description, :string, doc: "Example description"
  end

  @impl true
  def execute(params, frame) do
    params = Base.unwrap_properties(params)

    Base.with_scope(frame, "examples:write", fn _api_key ->
      case YourContext.create_example(params) do
        {:ok, example} ->
          {:reply, Base.success_response(serialize(example)), frame}

        {:error, changeset} ->
          {:reply, Base.changeset_error_response(changeset), frame}
      end
    end)
  end

  defp serialize(example) do
    %{
      id: example.id,
      name: example.name,
      description: example.description,
      inserted_at: DateTime.to_iso8601(example.inserted_at),
      updated_at: DateTime.to_iso8601(example.updated_at)
    }
  end
end
```

## Phase 7: Create MCP Server

### 7.1 Create Server Module

**File:** `lib/APP_NAME_web/mcp/server.ex`

```elixir
defmodule APP_NAMEWeb.MCP.Server do
  @moduledoc """
  MCP server implementation using Anubis.

  Authenticates clients via Bearer token and exposes tools.
  Tools are registered at compile-time using the component macro.
  """
  use Anubis.Server,
    name: "APP_NAME-mcp",
    version: "1.0.0",
    capabilities: [:tools]

  alias APP_NAME.Accounts
  alias Anubis.Server.Response

  # Register tool components at compile-time
  # This ensures tools are available even if clients skip initialization
  component APP_NAMEWeb.MCP.Components.Example, name: "example_list"
  component APP_NAMEWeb.MCP.Components.ExampleGet, name: "example_get"
  component APP_NAMEWeb.MCP.Components.ExampleCreate, name: "example_create"

  # Optional: Server initialization callback
  # Called after client sends notifications/initialized
  @impl true
  def init(client_info, frame) do
    # Extract and validate Bearer token
    case extract_and_authenticate(frame) do
      {:ok, api_key} ->
        # Store api_key in frame for component access
        frame = assign(frame, :api_key, api_key)
        frame = assign(frame, :client_name, client_info["name"])

        {:ok, frame}

      {:error, _reason} ->
        {:stop, :unauthorized}
    end
  end

  # Handle tool calls for any runtime-registered tools
  @impl true
  def handle_tool_call(tool_name, arguments, frame) do
    # This callback is for runtime-registered tools only
    # Compile-time components are handled automatically by Anubis
    require Logger
    Logger.warning("Unknown tool called: #{tool_name}")

    response =
      Response.tool()
      |> Response.text(Jason.encode!(%{success: false, error: "Unknown tool: #{tool_name}"}))
      |> Map.put(:isError, true)

    {:reply, response, frame}
  end

  # Private helpers

  defp extract_and_authenticate(frame) do
    with {:ok, auth_header} <- get_auth_header(frame),
         {:ok, token} <- extract_bearer_token(auth_header),
         {:ok, api_key} <- Accounts.authenticate_api_key(token) do
      {:ok, api_key}
    else
      error -> error
    end
  end

  defp get_auth_header(frame) do
    case frame.transport.req_headers do
      %{"authorization" => auth} -> {:ok, auth}
      %{"Authorization" => auth} -> {:ok, auth}
      _ -> {:error, :missing_auth}
    end
  end

  defp extract_bearer_token("Bearer " <> token) when byte_size(token) > 0 do
    {:ok, token}
  end
  defp extract_bearer_token(_), do: {:error, :invalid_format}
end
```

## Phase 8: Add to Application Supervisor

### 8.1 Update Application

**File:** `lib/APP_NAME/application.ex`

Add the MCP supervisor to the children list **unconditionally** — it must start in all environments (dev, test, and prod), not just when `dev_routes` is true. If it only starts in dev, production requests to `/mcp` will crash with `unknown registry: Anubis.Server.Registry`.

```elixir
def start(_type, _args) do
  children = [
    # ... your existing children
    APP_NAMEWeb.MCP.Supervisor  # Add this line — must NOT be inside a dev_routes guard
  ]

  opts = [strategy: :one_for_one, name: APP_NAME.Supervisor]
  Supervisor.start_link(children, opts)
end
```

**WARNING:** Do NOT wrap this in `if @dev_routes do`. The Anubis server registry and MCP server processes must be running for the `/mcp` route to work.

## Phase 9: Add Route

### 9.1 Update Router

**File:** `lib/APP_NAME_web/router.ex`

Add the MCP route **outside** the `dev_routes` conditional block so it's available in all environments including production. Place it after the dev routes block but before the authentication routes:

```elixir
if Application.compile_env(:APP_NAME, :dev_routes) do
  scope "/dev" do
    pipe_through :browser
    # ... dev-only routes (LiveDashboard, Swoosh mailbox, etc.)
  end
end

# MCP server endpoint (no browser pipeline — uses Bearer token auth)
forward "/mcp", APP_NAMEWeb.MCP.Plug,
  server: APP_NAMEWeb.MCP.Server

## Authentication routes
# ...
```

**WARNING:** Do NOT put the `/mcp` forward inside the `dev_routes` block. The `dev_routes` guard uses `Application.compile_env/2` which compiles away in production, making the route completely unavailable and returning 404.

## Phase 10: Write Tests

### 10.1 Create Plug Test

**File:** `test/APP_NAME_web/mcp/plug_test.exs`

```elixir
defmodule APP_NAMEWeb.MCP.PlugTest do
  use APP_NAMEWeb.ConnCase, async: true
  alias APP_NAMEWeb.MCP.Plug, as: MCPPlug

  setup do
    # Create test API key
    user = insert(:user)
    api_key = insert(:api_key, user: user, scopes: ["examples:read"])

    opts = MCPPlug.init(server: APP_NAMEWeb.MCP.Server)
    {:ok, opts: opts, api_key: api_key}
  end

  describe "authentication" do
    test "returns 401 when Authorization header is missing", %{conn: conn, opts: opts} do
      conn = MCPPlug.call(conn, opts)

      assert conn.status == 401
      assert conn.halted
      body = Jason.decode!(conn.resp_body)
      assert body["error"] == "Authorization header with Bearer token is required"
    end

    test "returns 401 for invalid API key", %{conn: conn, opts: opts} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer invalid_key")
        |> MCPPlug.call(opts)

      assert conn.status == 401
      assert conn.halted
    end

    test "forwards to Anubis with valid API key", %{conn: conn, opts: opts, api_key: api_key} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{api_key.key}")
        |> MCPPlug.call(opts)

      # Should forward to Anubis (which we can't test here without full setup)
      # But we can verify it didn't halt with 401
      assert conn.status != 401
    end
  end
end
```

### 10.2 Create Component Test

**File:** `test/APP_NAME_web/mcp/components/example_test.exs`

```elixir
defmodule APP_NAMEWeb.MCP.Components.ExampleTest do
  use APP_NAME.DataCase, async: true

  alias APP_NAMEWeb.MCP.Components.Example
  alias Anubis.Server.Frame

  describe "execute/2" do
    setup do
      # Create test data
      example1 = insert(:example, name: "Test 1")
      example2 = insert(:example, name: "Test 2")

      api_key = insert(:api_key, scopes: ["examples:read"])
      frame = %Frame{assigns: %{api_key: api_key}}

      {:ok, frame: frame, examples: [example1, example2]}
    end

    test "returns paginated list with valid scope", %{frame: frame} do
      assert {:reply, response, ^frame} = Example.execute(%{}, frame)

      assert response.content != []
      [content | _] = response.content
      data = Jason.decode!(content.text)

      assert data["success"] == true
      assert length(data["data"]) == 2
      assert data["meta"]["total_count"] == 2
    end

    test "returns error without valid scope" do
      frame = %Frame{assigns: %{api_key: %{scopes: []}}}

      assert {:reply, response, ^frame} = Example.execute(%{}, frame)

      [content | _] = response.content
      data = Jason.decode!(content.text)

      assert data["success"] == false
      assert data["error"] =~ "Insufficient permissions"
    end

    test "handles Claude Code properties wrapper", %{frame: frame} do
      # Claude Code wraps arguments in a properties key
      params = %{"properties" => %{"search" => "Test"}}

      assert {:reply, response, ^frame} = Example.execute(params, frame)

      [content | _] = response.content
      data = Jason.decode!(content.text)

      assert data["success"] == true
    end

    test "respects pagination parameters", %{frame: frame} do
      # Insert 10 more examples
      for i <- 1..10, do: insert(:example, name: "Example #{i}")

      assert {:reply, response, ^frame} =
        Example.execute(%{"page" => 1, "per_page" => 5}, frame)

      [content | _] = response.content
      data = Jason.decode!(content.text)

      assert length(data["data"]) == 5
      assert data["meta"]["page"] == 1
      assert data["meta"]["per_page"] == 5
      assert data["meta"]["has_next"] == true
    end

    test "handles search parameter", %{frame: frame} do
      insert(:example, name: "Findable Example")
      insert(:example, name: "Other")

      assert {:reply, response, ^frame} =
        Example.execute(%{"search" => "Findable"}, frame)

      [content | _] = response.content
      data = Jason.decode!(content.text)

      assert length(data["data"]) == 1
      assert hd(data["data"])["name"] =~ "Findable"
    end
  end
end
```

### 10.3 Create Session Store Test

**File:** `test/APP_NAME_web/mcp/session_store_test.exs`

```elixir
defmodule APP_NAMEWeb.MCP.SessionStoreTest do
  use ExUnit.Case, async: false

  alias APP_NAMEWeb.MCP.SessionStore

  setup do
    # Start fresh session store for each test
    start_supervised!(SessionStore)
    :ok
  end

  describe "load/2" do
    test "returns pre-initialized session for unknown session ID" do
      {:ok, session} = SessionStore.load("unknown_session")

      assert session.id == "unknown_session"
      assert session.initialized == true
      assert session.protocol_version == "2025-03-26"
    end

    test "returns saved session" do
      state = %{id: "test_session", initialized: true, custom: "data"}
      :ok = SessionStore.save("test_session", state)

      {:ok, loaded} = SessionStore.load("test_session")

      assert loaded.id == "test_session"
      assert loaded.custom == "data"
      assert loaded.initialized == true
    end
  end

  describe "save/3" do
    test "saves session state" do
      state = %{id: "session1", data: "test"}
      assert :ok = SessionStore.save("session1", state)

      {:ok, loaded} = SessionStore.load("session1")
      assert loaded.data == "test"
    end
  end

  describe "delete/2" do
    test "removes session" do
      SessionStore.save("to_delete", %{id: "to_delete"})
      assert :ok = SessionStore.delete("to_delete")

      # Should return pre-initialized session (not the saved one)
      {:ok, session} = SessionStore.load("to_delete")
      refute Map.has_key?(session, :data)
    end
  end
end
```

## Phase 11: Configure Claude CLI

### 11.1 Start Server

```bash
mix phx.server
```

### 11.2 Add MCP Server to Claude CLI (Development)

```bash
claude mcp add --transport http APP_NAME "http://localhost:4000/mcp" \
  --header "Authorization: Bearer YOUR_API_KEY_HERE"
```

### 11.3 Add MCP Server to Claude CLI (Production)

```bash
claude mcp add --transport http APP_NAME "https://your-app.fly.dev/mcp" \
  --header "Authorization: Bearer YOUR_API_KEY_HERE"
```

### 11.4 Alternative: Add to .mcp.json

**File:** `.mcp.json` (in your project root)

```json
{
  "mcpServers": {
    "APP_NAME": {
      "type": "http",
      "url": "http://localhost:4000/mcp",
      "headers": {
        "Authorization": "Bearer YOUR_API_KEY_HERE"
      }
    }
  }
}
```

For production, use the production URL instead:

```json
{
  "mcpServers": {
    "APP_NAME": {
      "type": "http",
      "url": "https://your-app.fly.dev/mcp",
      "headers": {
        "Authorization": "Bearer YOUR_API_KEY_HERE"
      }
    }
  }
}
```

## Phase 12: Test Your MCP Server

### Manual Testing with curl

```bash
# Initialize (optional with custom session store)
curl -X POST http://localhost:4000/mcp \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -d '{"jsonrpc":"2.0","method":"initialize","id":1,"params":{"clientInfo":{"name":"test"}}}'

# Call a tool
curl -X POST http://localhost:4000/mcp \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "mcp-session-id: session_123" \
  -d '{"jsonrpc":"2.0","method":"tools/call","id":2,"params":{"name":"example_list","arguments":{}}}'
```

### In Claude CLI

```bash
$ Can you list the examples?

# Claude will use your example_list tool
# You should see JSON response with your data
```

## Common Patterns

### Creating a New Tool Component

```elixir
defmodule APP_NAMEWeb.MCP.Components.MyTool do
  use Anubis.Server.Component, type: :tool

  alias APP_NAMEWeb.MCP.Components.Base

  @impl true
  def description, do: "Description of what the tool does"

  # Use Peri DSL for schema definition
  schema do
    field :properties, :map                           # For Claude Code wrapper
    field :required_field, {:required, :string}       # Required string
    field :optional_field, :integer                   # Optional integer
    field :list_field, {:list, :string}               # List of strings
    field :nested, :map                               # Nested object
  end

  @impl true
  def execute(params, frame) do
    params = Base.unwrap_properties(params)

    Base.with_scope(frame, "my_domain:read", fn _api_key ->
      # Your business logic here
      result = do_something(params)

      {:reply, Base.success_response(result), frame}
    end)
  end
end
```

### Registering the Component

Add to your server module:

```elixir
defmodule APP_NAMEWeb.MCP.Server do
  use Anubis.Server,
    name: "APP_NAME-mcp",
    version: "1.0.0",
    capabilities: [:tools]

  # Add your new component
  component APP_NAMEWeb.MCP.Components.MyTool, name: "my_tool"

  # ... rest of server
end
```

### Pagination

Always use `Base.get_pagination/1` and `Base.build_meta/3`:

```elixir
def execute(params, frame) do
  params = Base.unwrap_properties(params)

  Base.with_scope(frame, "domain:read", fn _api_key ->
    {page, per_page} = Base.get_pagination(params)
    {items, total} = your_paginated_query(page, per_page)
    meta = Base.build_meta(page, per_page, total)

    {:reply, Base.list_response(items, meta), frame}
  end)
end
```

### Search with LIKE

Always escape user input:

```elixir
search = Base.escape_like(params["search"])
where(query, [x], ilike(x.name, ^"%#{search}%"))
```

### Error Handling

Let `with_scope` catch exceptions:

```elixir
# Ecto.NoResultsError is automatically caught
# Returns: error_response("Resource not found")

# For validation errors, use changeset helper
case YourContext.create(params) do
  {:ok, record} ->
    {:reply, Base.success_response(serialize(record)), frame}

  {:error, changeset} ->
    {:reply, Base.changeset_error_response(changeset), frame}
end
```

## Scope Naming Convention

Use colon-separated format: `domain:action`

Examples:
- `examples:read` - List and view
- `examples:write` - Create and update
- `examples:delete` - Delete operations
- `examples:publish` - Special actions

## Production Considerations

1. **Rate Limiting**: Add rate limiting to the MCP plug
   ```elixir
   plug PlugAttack.RateLimit,
     name: "mcp:by_token",
     max: 100,
     period: 60_000,
     storage: {PlugAttack.Storage.Ets, MyApp.PlugAttack.Storage}
   ```

2. **Logging**: Log all MCP tool calls for audit trail
   ```elixir
   def execute(params, frame) do
     Logger.info("MCP tool called",
       tool: "my_tool",
       api_key_id: frame.assigns[:api_key].id,
       arguments: sanitize_for_logging(params)
     )
     # ... rest of handler
   end
   ```

3. **Monitoring**: Monitor tool execution times and errors
   - Track tool call duration with Telemetry
   - Alert on error rates > 5%
   - Monitor memory usage during large queries

4. **HTTPS Only**: Never expose MCP over plain HTTP in production

5. **Database Connection Pooling**: Increase pool size for MCP load
   ```elixir
   config :APP_NAME, APP_NAME.Repo,
     pool_size: 20  # Adjust based on expected concurrent MCP clients
   ```

6. **Session Store in Production**: Consider Redis or database-backed session store
   ```elixir
   # config/prod.exs
   config :anubis_mcp, :session_store,
     enabled: true,
     adapter: APP_NAMEWeb.MCP.RedisSessionStore
   ```

## Troubleshooting

### Production: 404 on `/mcp`

**Cause**: The `/mcp` route is inside the `dev_routes` conditional block in the router, which compiles away in production.

**Solution**: Move the `forward "/mcp"` line outside the `if Application.compile_env(:APP_NAME, :dev_routes) do` block. See Phase 9.

### Production: 500 with `unknown registry: Anubis.Server.Registry`

**Cause**: The MCP supervisor is only started when `dev_routes` is true. The route exists but the Anubis processes aren't running.

**Solution**: Remove the `dev_routes` guard from the MCP supervisor in `application.ex`. See Phase 8.

### Production: Connection hangs (Fly.io / reverse proxy)

**Cause**: Reverse proxies (Fly.io, nginx, etc.) buffer SSE responses by default. The Streamable HTTP transport uses SSE, and buffering prevents the response from being flushed to the client.

**Solution**: Add anti-buffering headers in the MCP plug before forwarding to Anubis:

```elixir
conn
|> put_resp_header("x-accel-buffering", "no")
|> put_resp_header("cache-control", "no-cache, no-store, must-revalidate")
|> AnubisPlug.call(opts)
```

These headers are already included in the plug template in Phase 4.

### "Server not initialized" Error

**Cause**: Client is calling tools without completing the MCP initialization handshake.

**Solution**: Ensure your session store is configured and returns pre-initialized sessions:

```elixir
# config/config.exs
config :anubis_mcp, :session_store,
  enabled: true,  # This is required!
  adapter: APP_NAMEWeb.MCP.SessionStore
```

### "No session store configured"

**Cause**: Missing `enabled: true` in session store config.

**Solution**: Add to your config:

```elixir
# config/config.exs (NOT dev.exs — needed in all envs)
config :anubis_mcp, :session_store,
  enabled: true,
  adapter: APP_NAMEWeb.MCP.SessionStore
```

### "Tool not found"

**Cause**: Tool not registered via `component` macro.

**Solution**: Add the component to your server module:

```elixir
component APP_NAMEWeb.MCP.Components.MyTool, name: "my_tool"
```

### Parameters have atom keys instead of string keys

**Cause**: Peri normalizes keys to atoms during validation.

**Solution**: Handle both in your unwrap function (already done in Base module):

```elixir
def unwrap_properties(%{properties: props}), do: props       # atom key
def unwrap_properties(%{"properties" => props}), do: props   # string key
def unwrap_properties(params), do: params
```

### "Authorization required" error

**Symptom**: 401 response or MCP connection fails immediately

**Diagnosis**:
- Check that Bearer token is being sent in Authorization header
- Verify API key exists in database
- Check API key is not revoked or expired

**Solution**:
```elixir
# Test your auth function directly
iex> APP_NAME.Accounts.authenticate_api_key("your_token")
{:ok, %ApiKey{...}}  # Should return api_key struct
```

### "Insufficient permissions" error

**Symptom**: Tool call succeeds but returns permission error

**Diagnosis**:
- Verify API key has required scope: `api_key.scopes`
- Check scope name matches exactly (case-sensitive)
- Verify component is checking correct scope

**Solution**:
```elixir
# Check API key scopes
iex> api_key = APP_NAME.Accounts.get_api_key_by_token!("token")
iex> api_key.scopes
["examples:read"]  # Make sure required scope is here
```

## Installation & Verification

After creating all files, run:

```bash
# Install dependencies
mix deps.get

# Start server
mix phx.server
```

## Checklist

After running this command, you should have:

- [ ] Anubis MCP dependency installed
- [ ] Session Store (`lib/APP_NAME_web/mcp/session_store.ex`)
- [ ] MCP Supervisor (`lib/APP_NAME_web/mcp/supervisor.ex`)
- [ ] MCP Plug (`lib/APP_NAME_web/mcp/plug.ex`)
- [ ] Base component helpers (`lib/APP_NAME_web/mcp/components/base.ex`)
- [ ] Example components (`lib/APP_NAME_web/mcp/components/example*.ex`)
- [ ] MCP Server (`lib/APP_NAME_web/mcp/server.ex`)
- [ ] Session store config in `config/dev.exs`
- [ ] Application supervisor updated
- [ ] Router updated with MCP route
- [ ] Tests created
- [ ] Claude CLI configured

## Placeholder Values to Update

Search and replace `APP_NAME` with your actual app name in:

- All MCP module files
- Test files
- Router configuration
- Config files
- `.mcp.json` (if used)

## Quick Reference Commands

```bash
# Development
mix phx.server              # Start server

# Testing
mix test test/APP_NAME_web/mcp/  # Run MCP tests

# Claude CLI
claude mcp list             # List configured servers
claude mcp remove APP_NAME  # Remove server
```

---

**Note:** This bootstrap creates a production-ready MCP server integrated with your existing Phoenix API key authentication. Ensure `/bootstrap-openapi` has been run first to set up the required `Accounts.authenticate_api_key/1` function.
