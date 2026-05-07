# Database Reference

## Migration 1: Credit Balances

Per-account credit balance with optimistic locking. One row per account.

```elixir
defmodule MyApp.Repo.Migrations.CreateCreditBalances do
  use Ecto.Migration

  def change do
    create table(:credit_balances, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :account_id, references(:accounts, type: :binary_id, on_delete: :delete_all),
        null: false

      add :balance, :integer, null: false, default: 0
      add :lock_version, :integer, null: false, default: 0

      timestamps()
    end

    create unique_index(:credit_balances, [:account_id])
  end
end
```

**Adapt**: Change `:accounts` to whatever the parent table is. Change `:binary_id` to `:id` if the app uses integer PKs.

## Migration 2: Credit Transactions

Immutable append-only transaction log. Never updated or deleted.

```elixir
defmodule MyApp.Repo.Migrations.CreateCreditTransactions do
  use Ecto.Migration

  def change do
    create table(:credit_transactions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :account_id, references(:accounts, type: :binary_id, on_delete: :delete_all),
        null: false

      add :amount, :integer, null: false
      add :balance_after, :integer, null: false
      add :type, :string, null: false
      add :description, :string
      add :metadata, :map, default: %{}

      timestamps()
    end

    create index(:credit_transactions, [:account_id])
    create index(:credit_transactions, [:account_id, :inserted_at])
  end
end
```

## Migration 3: Usage Events (optional)

Per-operation usage tracking. Only `inserted_at` timestamp (no `updated_at`).

```elixir
defmodule MyApp.Repo.Migrations.CreateUsageEvents do
  use Ecto.Migration

  def change do
    create table(:usage_events, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :account_id, references(:accounts, type: :binary_id, on_delete: :delete_all),
        null: false

      # Optional: associate with API key if api_keys table exists
      # add :api_key_id, references(:api_keys, type: :binary_id, on_delete: :nilify_all)

      add :operation, :string, null: false
      add :credit_cost, :integer, null: false, default: 0
      add :cache_hit, :boolean, null: false, default: false
      add :metadata, :map, default: %{}

      timestamps(updated_at: false)
    end

    create index(:usage_events, [:account_id, :inserted_at])
    # create index(:usage_events, [:api_key_id])  # if api_key_id exists
  end
end
```

## Migration 4: Stripe Customer ID on Accounts

```elixir
defmodule MyApp.Repo.Migrations.AddStripeCustomerIdToAccounts do
  use Ecto.Migration

  def change do
    alter table(:accounts) do
      add :stripe_customer_id, :string
    end
  end
end
```

**Adapt**: Add to whatever table holds the billing entity (accounts, users, organizations, etc.)

## Migration 5: Idempotency Index

Prevents double-crediting if webhook fires multiple times for the same payment.

```elixir
defmodule MyApp.Repo.Migrations.AddCreditPurchaseIdempotencyIndex do
  use Ecto.Migration

  def change do
    execute(
      """
      CREATE UNIQUE INDEX credit_transactions_account_id_payment_intent_id_index
      ON credit_transactions (account_id, (metadata->>'stripe_payment_intent_id'))
      WHERE type = 'addition' AND metadata ? 'stripe_payment_intent_id'
      """,
      "DROP INDEX IF EXISTS credit_transactions_account_id_payment_intent_id_index"
    )
  end
end
```

## Schema: CreditBalance

```elixir
defmodule MyApp.Credits.CreditBalance do
  @moduledoc """
  Per-account credit balance with optimistic locking.

  One row per account. The `lock_version` field prevents concurrent
  deduction races via Ecto's optimistic locking.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "credit_balances" do
    field :balance, :integer, default: 0
    field :lock_version, :integer, default: 0

    belongs_to :account, MyApp.Accounts.Account

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(credit_balance, attrs) do
    credit_balance
    |> cast(attrs, [:account_id, :balance])
    |> validate_required([:account_id, :balance])
    |> validate_number(:balance, greater_than_or_equal_to: 0)
    |> unique_constraint(:account_id)
    |> optimistic_lock(:lock_version)
  end
end
```

## Schema: CreditTransaction

```elixir
defmodule MyApp.Credits.CreditTransaction do
  @moduledoc """
  Immutable credit transaction log.

  Every credit change (deduction, addition, adjustment) is recorded
  as an append-only entry. Transactions are never updated or deleted.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}
  @type transaction_type :: :deduction | :addition | :adjustment

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "credit_transactions" do
    field :amount, :integer
    field :balance_after, :integer
    field :type, Ecto.Enum, values: [:deduction, :addition, :adjustment]
    field :description, :string
    field :metadata, :map, default: %{}

    belongs_to :account, MyApp.Accounts.Account

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(transaction, attrs) do
    transaction
    |> cast(attrs, [:account_id, :amount, :balance_after, :type, :description, :metadata])
    |> validate_required([:account_id, :amount, :balance_after, :type])
    |> validate_inclusion(:type, [:deduction, :addition, :adjustment])
    |> validate_amount_sign()
    |> unique_constraint(:account_id,
      name: :credit_transactions_account_id_payment_intent_id_index
    )
  end

  defp validate_amount_sign(changeset) do
    type = get_field(changeset, :type)
    amount = get_field(changeset, :amount)

    case {type, amount} do
      {:deduction, a} when is_integer(a) and a > 0 ->
        add_error(changeset, :amount, "must be negative for deductions")

      {:addition, a} when is_integer(a) and a < 0 ->
        add_error(changeset, :amount, "must be positive for additions")

      _ ->
        changeset
    end
  end
end
```

## Schema: UsageEvent (optional)

```elixir
defmodule MyApp.Credits.UsageEvent do
  @moduledoc """
  Per-operation usage event tracking.

  Records every API operation with cost, cache status, and metadata.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "usage_events" do
    field :operation, :string
    field :credit_cost, :integer, default: 0
    field :cache_hit, :boolean, default: false
    field :metadata, :map, default: %{}

    belongs_to :account, MyApp.Accounts.Account
    # belongs_to :api_key, MyApp.Accounts.ApiKey  # if api_keys exist

    timestamps(updated_at: false)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(event, attrs) do
    event
    |> cast(attrs, [:account_id, :operation, :credit_cost, :cache_hit, :metadata])
    |> validate_required([:account_id, :operation])
  end
end
```
