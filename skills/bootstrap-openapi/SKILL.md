---
name: bootstrap-openapi
description: "Bootstrap OpenAPI for Phoenix"
---

# Bootstrap OpenAPI for Phoenix

Set up OpenAPI documentation with authentication and authorization in a Phoenix project using `open_api_spex`. This includes:
- OpenAPI 3.0 specification with Swagger UI
- User authentication via `phx.gen.auth`
- Multi-tenant accounts with User many-to-many relationship
- API key authentication (pk_/sk_ tokens) scoped to user+account
- Read/write access control
- CORS configuration
- TypeScript type generation support

**Prerequisites:** This command assumes you have an existing Phoenix project. If not, run `/bootstrap-phoenix` first.

## Phase 1: Generate User Authentication

### 1.1 Run phx.gen.auth

```bash
mix phx.gen.auth Accounts User users
```

This generates:
- `User` schema with email/password/hashed_password
- `UserToken` schema for sessions
- Authentication plugs and helpers
- Login/registration LiveViews
- Email verification support

### 1.2 Run the migration

```bash
mix ecto.migrate
```

### 1.3 Update User schema for account associations

**File:** `lib/APP_NAME/accounts/user.ex`

Add these associations after the existing fields:

```elixir
# Add after the existing fields, before timestamps()
has_many :account_users, APP_NAME.Accounts.AccountUser
has_many :accounts, through: [:account_users, :account]
```

## Phase 2: Add Dependencies

### 2.1 Update mix.exs

**File:** `mix.exs`

Add to the `deps/0` function:

```elixir
defp deps do
  [
    # ... existing dependencies ...

    # OpenAPI Documentation
    {:open_api_spex, "~> 3.21"},

    # CORS support (optional but recommended for frontend APIs)
    {:cors_plug, "~> 3.0"}
  ]
end
```

Run `mix deps.get` after updating.

## Phase 3: Account Schema

### 3.1 Create Account Schema

**File:** `lib/APP_NAME/accounts/account.ex`

```elixir
defmodule APP_NAME.Accounts.Account do
  @moduledoc """
  Schema for accounts (organizations/tenants).
  Users can belong to multiple accounts.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "accounts" do
    field :name, :string
    field :slug, :string
    field :status, Ecto.Enum, values: [:active, :suspended], default: :active

    has_many :account_users, APP_NAME.Accounts.AccountUser
    has_many :users, through: [:account_users, :user]

    timestamps()
  end

  def changeset(account, attrs) do
    account
    |> cast(attrs, [:name, :slug, :status])
    |> validate_required([:name])
    |> unique_constraint(:slug)
    |> maybe_generate_slug()
  end

  defp maybe_generate_slug(changeset) do
    case get_field(changeset, :slug) do
      nil ->
        name = get_field(changeset, :name)
        if name do
          slug = name |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "-")
          put_change(changeset, :slug, slug)
        else
          changeset
        end
      _ ->
        changeset
    end
  end
end
```

### 3.2 Create AccountUser Join Schema

**File:** `lib/APP_NAME/accounts/account_user.ex`

```elixir
defmodule APP_NAME.Accounts.AccountUser do
  @moduledoc """
  Join schema for User <-> Account many-to-many relationship.
  Includes role for authorization within the account.
  API keys belong to this membership (user+account pair).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "account_users" do
    field :role, Ecto.Enum, values: [:owner, :admin, :member], default: :member

    belongs_to :user, APP_NAME.Accounts.User
    belongs_to :account, APP_NAME.Accounts.Account
    has_many :api_keys, APP_NAME.Accounts.ApiKey

    timestamps()
  end

  def changeset(account_user, attrs) do
    account_user
    |> cast(attrs, [:role, :user_id, :account_id])
    |> validate_required([:user_id, :account_id])
    |> unique_constraint([:user_id, :account_id])
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:account_id)
  end

  @doc "Check if this membership has admin-level access"
  def admin?(%__MODULE__{role: role}), do: role in [:owner, :admin]

  @doc "Check if this membership is the account owner"
  def owner?(%__MODULE__{role: :owner}), do: true
  def owner?(_), do: false
end
```

## Phase 4: API Key Schema

### 4.1 Create API Key Schema

**File:** `lib/APP_NAME/accounts/api_key.ex`

```elixir
defmodule APP_NAME.Accounts.ApiKey do
  @moduledoc """
  Schema for API keys used for programmatic authentication.
  Supports public (read-only) and private (read/write) keys.
  Keys are scoped to a user's membership in an account.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "api_keys" do
    field :name, :string
    field :type, Ecto.Enum, values: [:public, :private], default: :public
    field :token_prefix, :string  # First 12 chars of token
    field :token_hash, :string    # SHA256 hash of full token
    field :status, Ecto.Enum, values: [:active, :revoked], default: :active
    field :last_used_at, :utc_datetime
    field :expires_at, :utc_datetime

    belongs_to :account_user, APP_NAME.Accounts.AccountUser

    timestamps()
  end

  @doc "Check if API key can perform write operations"
  def can_write?(%__MODULE__{type: :private}), do: true
  def can_write?(_), do: false

  @doc "Generate a new API key token"
  def generate_token(type) do
    prefix = if type == :private, do: "sk_", else: "pk_"
    random_bytes = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
    prefix <> random_bytes
  end

  @doc "Hash a token for storage"
  def hash_token(token) do
    :crypto.hash(:sha256, token) |> Base.encode64()
  end

  def changeset(api_key, attrs) do
    api_key
    |> cast(attrs, [:name, :type, :expires_at, :account_user_id])
    |> validate_required([:name, :type, :account_user_id])
    |> foreign_key_constraint(:account_user_id)
  end
end
```

## Phase 5: Migrations

### 5.1 Create Accounts Migration

```bash
mix ecto.gen.migration create_accounts
```

**File:** `priv/repo/migrations/TIMESTAMP_create_accounts.exs`

```elixir
defmodule APP_NAME.Repo.Migrations.CreateAccounts do
  use Ecto.Migration

  def change do
    create table(:accounts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :slug, :string
      add :status, :string, null: false, default: "active"

      timestamps()
    end

    create unique_index(:accounts, [:slug])
  end
end
```

### 5.2 Create AccountUsers Migration

```bash
mix ecto.gen.migration create_account_users
```

**File:** `priv/repo/migrations/TIMESTAMP_create_account_users.exs`

```elixir
defmodule APP_NAME.Repo.Migrations.CreateAccountUsers do
  use Ecto.Migration

  def change do
    create table(:account_users, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :role, :string, null: false, default: "member"
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :account_id, references(:accounts, type: :binary_id, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:account_users, [:user_id])
    create index(:account_users, [:account_id])
    create unique_index(:account_users, [:user_id, :account_id])
  end
end
```

### 5.3 Create API Keys Migration

```bash
mix ecto.gen.migration create_api_keys
```

**File:** `priv/repo/migrations/TIMESTAMP_create_api_keys.exs`

```elixir
defmodule APP_NAME.Repo.Migrations.CreateApiKeys do
  use Ecto.Migration

  def change do
    create table(:api_keys, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :type, :string, null: false, default: "public"
      add :token_prefix, :string, null: false
      add :token_hash, :string, null: false
      add :status, :string, null: false, default: "active"
      add :last_used_at, :utc_datetime
      add :expires_at, :utc_datetime
      add :account_user_id, references(:account_users, type: :binary_id, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:api_keys, [:account_user_id])
    create index(:api_keys, [:token_prefix])
    create unique_index(:api_keys, [:token_hash])
    create index(:api_keys, [:status])
  end
end
```

Run migrations:

```bash
mix ecto.migrate
```

## Phase 6: Accounts Context

### 6.1 Add Account and API Key Functions

Add these functions to your `lib/APP_NAME/accounts.ex` context (alongside the generated auth functions):

```elixir
defmodule APP_NAME.Accounts do
  # ... existing phx.gen.auth code ...

  alias APP_NAME.Accounts.{Account, AccountUser, ApiKey}
  alias APP_NAME.Repo
  import Ecto.Query

  # ============================================
  # Account Functions
  # ============================================

  @doc "Get an account by ID"
  def get_account(id), do: Repo.get(Account, id)

  @doc "Get an account by slug"
  def get_account_by_slug(slug), do: Repo.get_by(Account, slug: slug)

  @doc "Create a new account with the given user as owner"
  def create_account(user, attrs) do
    Repo.transaction(fn ->
      with {:ok, account} <- %Account{} |> Account.changeset(attrs) |> Repo.insert(),
           {:ok, _account_user} <- add_user_to_account(account, user, :owner) do
        account
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  @doc "List all accounts for a user"
  def list_user_accounts(user) do
    from(a in Account,
      join: au in AccountUser, on: au.account_id == a.id,
      where: au.user_id == ^user.id,
      select: {a, au.role}
    )
    |> Repo.all()
  end

  # ============================================
  # AccountUser (Membership) Functions
  # ============================================

  @doc "Get a user's membership in an account"
  def get_account_user(user, account) do
    Repo.get_by(AccountUser, user_id: user.id, account_id: account.id)
  end

  @doc "Get account_user by ID with preloads"
  def get_account_user!(id) do
    AccountUser
    |> Repo.get!(id)
    |> Repo.preload([:user, :account])
  end

  @doc "Add a user to an account with a role"
  def add_user_to_account(account, user, role \\ :member) do
    %AccountUser{}
    |> AccountUser.changeset(%{
      account_id: account.id,
      user_id: user.id,
      role: role
    })
    |> Repo.insert()
  end

  @doc "Remove a user from an account"
  def remove_user_from_account(account, user) do
    case get_account_user(user, account) do
      nil -> {:error, :not_found}
      account_user -> Repo.delete(account_user)
    end
  end

  @doc "Update a user's role in an account"
  def update_account_user_role(account_user, role) do
    account_user
    |> AccountUser.changeset(%{role: role})
    |> Repo.update()
  end

  # ============================================
  # API Key Functions
  # ============================================

  @doc "Verify an API token and return the key with account_user preloaded"
  def verify_api_token(token) do
    prefix = String.slice(token, 0, 12)
    hash = ApiKey.hash_token(token)

    query =
      from k in ApiKey,
        where: k.token_prefix == ^prefix and k.token_hash == ^hash,
        where: k.status == :active,
        where: is_nil(k.expires_at) or k.expires_at > ^DateTime.utc_now(),
        preload: [account_user: [:user, :account]]

    case Repo.one(query) do
      nil -> {:error, :invalid_token}
      api_key -> {:ok, api_key}
    end
  end

  @doc "Update last_used_at timestamp"
  def touch_api_key(api_key) do
    api_key
    |> Ecto.Changeset.change(last_used_at: DateTime.utc_now() |> DateTime.truncate(:second))
    |> Repo.update()
  end

  @doc "Create a new API key for an account_user (membership)"
  def create_api_key(account_user, attrs) do
    type = attrs[:type] || :public
    token = ApiKey.generate_token(type)
    prefix = String.slice(token, 0, 12)
    hash = ApiKey.hash_token(token)

    changeset =
      %ApiKey{account_user_id: account_user.id}
      |> ApiKey.changeset(Map.put(attrs, :account_user_id, account_user.id))
      |> Ecto.Changeset.put_change(:token_prefix, prefix)
      |> Ecto.Changeset.put_change(:token_hash, hash)

    case Repo.insert(changeset) do
      {:ok, api_key} -> {:ok, {api_key, token}}
      error -> error
    end
  end

  @doc "List API keys for an account_user"
  def list_api_keys(account_user) do
    from(k in ApiKey, where: k.account_user_id == ^account_user.id)
    |> Repo.all()
  end

  @doc "Revoke an API key"
  def revoke_api_key(api_key) do
    api_key
    |> Ecto.Changeset.change(status: :revoked)
    |> Repo.update()
  end
end
```

## Phase 7: API Spec Module

### 7.1 Create API Specification

**File:** `lib/APP_NAME_web/api_spec.ex`

```elixir
defmodule APP_NAMEWeb.ApiSpec do
  @moduledoc """
  OpenAPI specification for the API.
  Provides auto-generated documentation and request/response validation.
  """
  alias APP_NAMEWeb.{Endpoint, Router}
  alias OpenApiSpex.{Components, Info, OpenApi, Paths, SecurityScheme, Server}
  @behaviour OpenApi

  @impl OpenApi
  def spec do
    %OpenApi{
      servers: [
        Server.from_endpoint(Endpoint)
      ],
      info: %Info{
        title: "APP_NAME API",
        version: "1.0.0",
        description: """
        Your API description here.

        ## Authentication
        All API endpoints require authentication using API keys.

        ### API Key Types
        - **Public Keys** (`pk_...`): Read-only access
        - **Private Keys** (`sk_...`): Full read/write access

        ### How to Authenticate
        1. Log in to your account and create an API key
        2. Click the "Authorize" button in Swagger UI
        3. Enter your API key: `Bearer <your_api_key>`

        All requests must include the `Authorization` header.

        ### Multi-tenant Access
        API keys are scoped to your membership in a specific account.
        To access multiple accounts, create separate API keys for each.
        """
      },
      paths: Paths.from_router(Router),
      components: %Components{
        securitySchemes: %{
          "bearerAuth" => %SecurityScheme{
            type: "http",
            scheme: "bearer",
            bearerFormat: "API Key",
            description: """
            Enter your API key: `pk_...` (read-only) or `sk_...` (read/write)
            """
          }
        }
      },
      # Apply security globally to all endpoints
      security: [
        %{"bearerAuth" => []}
      ]
    }
    |> OpenApiSpex.resolve_schema_modules()
  end
end
```

## Phase 8: Authentication Plug

### 8.1 Create API Auth Plug

**File:** `lib/APP_NAME_web/plugs/api_auth.ex`

```elixir
defmodule APP_NAMEWeb.Plugs.ApiAuth do
  @moduledoc """
  Bearer token authentication for API requests.
  Validates API keys and loads user/account context.
  """
  import Plug.Conn
  import Phoenix.Controller

  alias APP_NAME.Accounts

  def init(opts), do: opts

  @doc """
  Main plug function - dispatches based on opts.
  """
  def call(conn, opts) do
    case opts do
      :require_write_access -> require_write_access(conn, [])
      _ -> require_api_auth(conn, opts)
    end
  end

  @doc """
  Requires API authentication via bearer token.
  Extracts token from Authorization header, verifies it, and loads context.
  """
  def require_api_auth(conn, _opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, api_key} <- Accounts.verify_api_token(token),
         :ok <- check_user_confirmed(api_key.account_user.user),
         :ok <- check_account_active(api_key.account_user.account) do
      # Update last_used_at timestamp (async in prod, sync in test)
      if Mix.env() == :test do
        Accounts.touch_api_key(api_key)
      else
        Task.start(fn -> Accounts.touch_api_key(api_key) end)
      end

      conn
      |> assign(:current_api_key, api_key)
      |> assign(:current_account_user, api_key.account_user)
      |> assign(:current_user, api_key.account_user.user)
      |> assign(:current_account, api_key.account_user.account)
    else
      _ ->
        conn
        |> put_status(:unauthorized)
        |> put_view(json: APP_NAMEWeb.ErrorJSON)
        |> render(:"401")
        |> halt()
    end
  end

  @doc """
  Requires write access (private API key with sk_ prefix).
  Must be used after require_api_auth/2.
  """
  def require_write_access(conn, _opts) do
    api_key = conn.assigns[:current_api_key]

    if api_key && api_key.type == :private do
      conn
    else
      conn
      |> put_status(:forbidden)
      |> put_view(json: APP_NAMEWeb.ErrorJSON)
      |> render(:"403")
      |> halt()
    end
  end

  defp check_user_confirmed(%{confirmed_at: nil}), do: {:error, :unconfirmed}
  defp check_user_confirmed(_user), do: :ok

  defp check_account_active(%{status: :active}), do: :ok
  defp check_account_active(_), do: {:error, :account_suspended}
end
```

## Phase 9: Router Configuration

### 9.1 Update Router with API Pipelines

**File:** `lib/APP_NAME_web/router.ex`

Add these pipelines and routes (keep existing phx.gen.auth routes):

```elixir
defmodule APP_NAMEWeb.Router do
  use APP_NAMEWeb, :router

  import APP_NAMEWeb.UserAuth  # Generated by phx.gen.auth

  # ... existing pipelines from phx.gen.auth ...

  # Base API pipeline - no auth, just JSON + OpenAPI spec injection
  pipeline :api do
    plug :accepts, ["json"]
    plug CORSPlug
    plug OpenApiSpex.Plug.PutApiSpec, module: APP_NAMEWeb.ApiSpec
  end

  # Authenticated API - requires valid API key
  pipeline :api_authenticated do
    plug :accepts, ["json"]
    plug CORSPlug
    plug OpenApiSpex.Plug.PutApiSpec, module: APP_NAMEWeb.ApiSpec
    plug APP_NAMEWeb.Plugs.ApiAuth, :require_api_auth
  end

  # Write access - requires private API key (sk_...)
  pipeline :api_write do
    plug :accepts, ["json"]
    plug CORSPlug
    plug OpenApiSpex.Plug.PutApiSpec, module: APP_NAMEWeb.ApiSpec
    plug APP_NAMEWeb.Plugs.ApiAuth, :require_api_auth
    plug APP_NAMEWeb.Plugs.ApiAuth, :require_write_access
  end

  # ============================================
  # Web UI Routes (phx.gen.auth session-based)
  # ============================================
  # Keep all routes generated by phx.gen.auth here

  # ============================================
  # OpenAPI Documentation (no auth required)
  # ============================================
  scope "/api/v1" do
    pipe_through :api

    get "/openapi", OpenApiSpex.Plug.RenderSpec, []
    get "/docs", OpenApiSpex.Plug.SwaggerUI, path: "/api/v1/openapi"
  end

  # ============================================
  # API Routes - Read (authenticated)
  # ============================================
  scope "/api/v1", APP_NAMEWeb.Api.V1, as: :api_v1 do
    pipe_through :api_authenticated

    # Add your read-only routes here
    # get "/resources", ResourceController, :index
    # get "/resources/:id", ResourceController, :show
  end

  # ============================================
  # API Routes - Write (authenticated + write access)
  # ============================================
  scope "/api/v1", APP_NAMEWeb.Api.V1, as: :api_v1 do
    pipe_through :api_write

    # Add your write routes here
    # post "/resources", ResourceController, :create
    # patch "/resources/:id", ResourceController, :update
    # delete "/resources/:id", ResourceController, :delete
  end
end
```

## Phase 10: Error Handling

### 10.1 Create Fallback Controller

**File:** `lib/APP_NAME_web/controllers/fallback_controller.ex`

```elixir
defmodule APP_NAMEWeb.FallbackController do
  @moduledoc """
  Translates controller action results into valid Plug.Conn responses.
  """
  use APP_NAMEWeb, :controller

  def call(conn, {:error, :not_found}) do
    conn
    |> put_status(:not_found)
    |> put_view(json: APP_NAMEWeb.ErrorJSON)
    |> render(:"404")
  end

  def call(conn, {:error, :forbidden}) do
    conn
    |> put_status(:forbidden)
    |> put_view(json: APP_NAMEWeb.ErrorJSON)
    |> render(:"403")
  end

  def call(conn, {:error, :unauthorized}) do
    conn
    |> put_status(:unauthorized)
    |> put_view(json: APP_NAMEWeb.ErrorJSON)
    |> render(:"401")
  end

  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(json: APP_NAMEWeb.ChangesetJSON)
    |> render(:error, changeset: changeset)
  end
end
```

### 10.2 Create Error JSON View

**File:** `lib/APP_NAME_web/controllers/error_json.ex`

```elixir
defmodule APP_NAMEWeb.ErrorJSON do
  @moduledoc """
  Renders error responses as JSON.
  """

  def render("401.json", _assigns) do
    %{errors: %{detail: "Unauthorized - valid API key required"}}
  end

  def render("403.json", _assigns) do
    %{errors: %{detail: "Forbidden - insufficient permissions"}}
  end

  def render("404.json", _assigns) do
    %{errors: %{detail: "Not Found"}}
  end

  def render(template, _assigns) do
    %{errors: %{detail: Phoenix.Controller.status_message_from_template(template)}}
  end
end
```

### 10.3 Create Changeset JSON View

**File:** `lib/APP_NAME_web/controllers/changeset_json.ex`

```elixir
defmodule APP_NAMEWeb.ChangesetJSON do
  @moduledoc """
  Renders changeset errors as JSON.
  """

  def error(%{changeset: changeset}) do
    %{errors: Ecto.Changeset.traverse_errors(changeset, &translate_error/1)}
  end

  defp translate_error({msg, opts}) do
    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", to_string(value))
    end)
  end
end
```

## Phase 11: CORS Configuration

### 11.1 Update Development Config

**File:** `config/dev.exs`

Add:

```elixir
# CORS configuration for API
config :cors_plug,
  origin: ["http://localhost:3000", "http://localhost:4321"],
  methods: ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
  headers: ["Content-Type", "Authorization", "Accept"],
  max_age: 86400
```

### 11.2 Update Runtime Config for Production

**File:** `config/runtime.exs`

Add:

```elixir
# CORS configuration
if config_env() == :prod do
  config :cors_plug,
    origin: System.get_env("CORS_ORIGINS", "https://yourapp.com") |> String.split(","),
    methods: ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    headers: ["Content-Type", "Authorization", "Accept"]
end
```

## Installation & Verification

After creating all files, run:

```bash
# Install dependencies
mix deps.get

# Run migrations
mix ecto.migrate

# Start server
mix phx.server
```

Visit:
- **Web UI**: `http://localhost:4000` (login/register via phx.gen.auth)
- **Swagger UI**: `http://localhost:4000/api/v1/docs`

## Checklist

After running this command, you should have:

- [ ] User authentication generated via phx.gen.auth
- [ ] Dependencies installed (open_api_spex, cors_plug)
- [ ] Account schema with slug and status
- [ ] AccountUser join table with roles
- [ ] ApiKey schema referencing account_user
- [ ] All migrations created and run
- [ ] Accounts context with account/membership/api_key functions
- [ ] ApiSpec module created
- [ ] ApiAuth plug implemented
- [ ] Router configured with dual auth (session + API key)
- [ ] Error handling (FallbackController, ErrorJSON, ChangesetJSON)
- [ ] CORS configuration
- [ ] Swagger UI accessible at `/api/v1/docs`

## Data Model Reference

```
User (phx.gen.auth)
  |-- email, hashed_password, confirmed_at
  |-- has_many :account_users
  |-- has_many :accounts, through: :account_users

Account
  |-- name, slug, status
  |-- has_many :account_users
  |-- has_many :users, through: :account_users

AccountUser (join table)
  |-- role (owner, admin, member)
  |-- belongs_to :user
  |-- belongs_to :account
  |-- has_many :api_keys

ApiKey
  |-- name, type (public/private), token_prefix, token_hash
  |-- belongs_to :account_user
```

## Pipeline Reference

| Pipeline | Auth Type | Write Access |
|----------|-----------|--------------|
| `:api` | None | N/A |
| `:api_authenticated` | API Key | Read only |
| `:api_write` | API Key (sk_) | Yes |

## Context Assigns Reference

After API authentication, these assigns are available:

| Assign | Type | Description |
|--------|------|-------------|
| `current_api_key` | ApiKey | The authenticated API key |
| `current_account_user` | AccountUser | User's membership (includes role) |
| `current_user` | User | The authenticated user |
| `current_account` | Account | The scoped account |

## Testing Example

**File:** `test/APP_NAME_web/controllers/api/v1/resource_controller_test.exs`

```elixir
defmodule APP_NAMEWeb.Api.V1.ResourceControllerTest do
  use APP_NAMEWeb.ConnCase, async: true

  alias APP_NAME.Accounts

  setup %{conn: conn} do
    # Create test user (use generated fixtures from phx.gen.auth)
    user = user_fixture()

    # Create account with user as owner
    {:ok, account} = Accounts.create_account(user, %{name: "Test Account"})

    # Get the account_user membership
    account_user = Accounts.get_account_user(user, account)

    # Create API key
    {:ok, {api_key, token}} = Accounts.create_api_key(account_user, %{
      name: "Test Key",
      type: :private
    })

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer #{token}")

    %{conn: conn, user: user, account: account, account_user: account_user, api_key: api_key}
  end

  test "returns 401 without token", %{conn: conn} do
    conn =
      conn
      |> delete_req_header("authorization")
      |> get(~p"/api/v1/resources")

    assert json_response(conn, 401)
  end

  test "returns 403 with public key on write endpoint", %{account_user: account_user} do
    {:ok, {_key, token}} = Accounts.create_api_key(account_user, %{
      name: "Public Key",
      type: :public
    })

    conn =
      build_conn()
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer #{token}")
      |> post(~p"/api/v1/resources", %{})

    assert json_response(conn, 403)
  end
end
```

## Quick Reference

### Access Points
- **Web Login**: `http://localhost:4000/users/log_in`
- **Web Register**: `http://localhost:4000/users/register`
- **Swagger UI**: `http://localhost:4000/api/v1/docs`
- **OpenAPI JSON**: `http://localhost:4000/api/v1/openapi`

### Authentication Header
```
Authorization: Bearer pk_xxxxx  (read-only)
Authorization: Bearer sk_xxxxx  (read/write)
```

### Creating API Keys

In IEx console:

```elixir
alias APP_NAME.Accounts

# Get user and account
user = Accounts.get_user_by_email("user@example.com")
account = Accounts.get_account_by_slug("my-account")
account_user = Accounts.get_account_user(user, account)

# Create public key (read-only)
{:ok, {key, token}} = Accounts.create_api_key(account_user, %{
  name: "My Public Key",
  type: :public
})

# Create private key (read/write)
{:ok, {key, token}} = Accounts.create_api_key(account_user, %{
  name: "My Private Key",
  type: :private
})

# Save the token - it's only shown once!
IO.puts("Token: #{token}")
```

### Creating an Account for a User

```elixir
alias APP_NAME.Accounts

user = Accounts.get_user_by_email("user@example.com")

# Create account (user becomes owner automatically)
{:ok, account} = Accounts.create_account(user, %{name: "My Company"})

# Add another user to the account
other_user = Accounts.get_user_by_email("other@example.com")
{:ok, _membership} = Accounts.add_user_to_account(account, other_user, :member)
```

## Placeholder Values to Update

Search and replace `APP_NAME` with your actual app name in:
- All created files
- Module names
- Config references

---

**Note:** This bootstrap sets up a complete multi-tenant API infrastructure with dual authentication (session-based for web UI, API keys for programmatic access). API keys are scoped to a user's membership in an account, supporting team/organization structures.
