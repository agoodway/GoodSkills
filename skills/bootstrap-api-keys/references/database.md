# Database: Migration & Schema

## Migration: Create API Keys

Generate with `mix ecto.gen.migration create_api_keys`, then use:

```elixir
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

    # ADAPT: Change the parent reference to match the chosen association
    # For users:
    add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
    # For account_users:
    # add :account_user_id, references(:account_users, type: :binary_id, on_delete: :delete_all), null: false
    # For accounts:
    # add :account_id, references(:accounts, type: :binary_id, on_delete: :delete_all), null: false

    timestamps(type: :utc_datetime)
  end

  # ADAPT: Change index column to match parent
  create index(:api_keys, [:user_id])
  create index(:api_keys, [:token_prefix])
  create unique_index(:api_keys, [:token_hash])
  create index(:api_keys, [:status])
end
```

## Schema: ApiKey

Create `lib/my_app/accounts/api_key.ex` (adjust path to match the context module):

```elixir
defmodule MyApp.Accounts.ApiKey do
  @moduledoc """
  Schema for API keys used for programmatic authentication.
  Supports public (read-only) and private (read-write) keys.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "api_keys" do
    field :name, :string
    field :type, Ecto.Enum, values: [:public, :private], default: :public
    field :token_prefix, :string
    field :token_hash, :string
    field :status, Ecto.Enum, values: [:active, :revoked], default: :active
    field :last_used_at, :utc_datetime
    field :expires_at, :utc_datetime

    # ADAPT: Change to the correct parent association
    belongs_to :user, MyApp.Accounts.User

    timestamps()
  end

  @doc "Check if API key can perform write operations."
  @spec can_write?(%__MODULE__{}) :: boolean()
  def can_write?(%__MODULE__{type: :private}), do: true
  def can_write?(_), do: false

  @doc "Generate a new API key token with type-based prefix."
  @spec generate_token(:public | :private) :: String.t()
  def generate_token(type) do
    prefix = if type == :private, do: "sk_", else: "pk_"
    random_bytes = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
    prefix <> random_bytes
  end

  @doc "Hash a token for secure storage (SHA256 + base64)."
  @spec hash_token(String.t()) :: String.t()
  def hash_token(token) do
    :crypto.hash(:sha256, token) |> Base.encode64()
  end

  @doc "Changeset for creating an API key."
  @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(api_key, attrs) do
    api_key
    # ADAPT: Change :user_id to match parent foreign key
    |> cast(attrs, [:name, :type, :expires_at, :user_id])
    |> validate_required([:name, :type, :user_id])
    |> foreign_key_constraint(:user_id)
  end
end
```

### If key types are NOT needed

Remove the `:type` field, the `can_write?/1` function, and simplify `generate_token/0`:

```elixir
field :type, Ecto.Enum, values: [:standard], default: :standard

def generate_token do
  "key_" <> (:crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false))
end
```
