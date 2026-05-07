# Database: Migrations & Schemas

## Migration 1: Create Accounts

Generate with `mix ecto.gen.migration create_accounts`, then use:

```elixir
def change do
  create table(:accounts, primary_key: false) do
    add :id, :binary_id, primary_key: true
    add :name, :string, null: false
    add :slug, :string, null: false
    add :status, :string, null: false, default: "active"

    timestamps(type: :utc_datetime)
  end

  create unique_index(:accounts, [:slug])
end
```

## Migration 2: Create Account Users

Generate with `mix ecto.gen.migration create_account_users`, then use:

```elixir
def change do
  create table(:account_users, primary_key: false) do
    add :id, :binary_id, primary_key: true
    add :role, :string, null: false, default: "member"
    add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
    add :account_id, references(:accounts, type: :binary_id, on_delete: :delete_all), null: false

    timestamps(type: :utc_datetime)
  end

  create index(:account_users, [:user_id])
  create index(:account_users, [:account_id])
  create unique_index(:account_users, [:user_id, :account_id])
end
```

## Schema: Account

Create `lib/my_app/accounts/account.ex`:

```elixir
defmodule MyApp.Accounts.Account do
  use Ecto.Schema
  import Ecto.Changeset

  alias MyApp.Accounts.AccountUser

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "accounts" do
    field :name, :string
    field :slug, :string
    field :status, Ecto.Enum, values: [:active, :suspended], default: :active

    has_many :account_users, AccountUser
    has_many :users, through: [:account_users, :user]

    timestamps(type: :utc_datetime)
  end

  def changeset(account, attrs) do
    account
    |> cast(attrs, [:name, :slug, :status])
    |> validate_required([:name])
    |> maybe_generate_slug()
    |> validate_required([:slug])
    |> unique_constraint(:slug)
  end

  defp maybe_generate_slug(changeset) do
    case get_field(changeset, :slug) do
      nil ->
        name = get_field(changeset, :name)

        if name do
          slug = name |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "-") |> String.trim("-")
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

## Schema: AccountUser

Create `lib/my_app/accounts/account_user.ex`:

```elixir
defmodule MyApp.Accounts.AccountUser do
  use Ecto.Schema
  import Ecto.Changeset

  alias MyApp.Accounts.{Account, User}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "account_users" do
    field :role, Ecto.Enum, values: [:owner, :admin, :member], default: :member

    belongs_to :user, User
    belongs_to :account, Account

    timestamps(type: :utc_datetime)
  end

  def changeset(account_user, attrs) do
    account_user
    |> cast(attrs, [:role, :user_id, :account_id])
    |> validate_required([:role, :user_id, :account_id])
    |> unique_constraint([:user_id, :account_id])
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:account_id)
  end
end
```
