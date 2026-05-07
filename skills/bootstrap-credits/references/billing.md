# Billing Modules Reference

**Adapt**: Replace `MyApp` with the actual app module and `:my_app` with the OTP app name.

## Billing — Pack Configuration

```elixir
defmodule MyApp.Billing do
  @moduledoc """
  Billing helpers for configured credit packs.
  """

  @type pack :: %{
          key: String.t(),
          amount_cents: pos_integer(),
          credits: pos_integer()
        }

  @doc """
  Returns configured credit packs as a list sorted by price.
  """
  @spec credit_packs() :: [pack()]
  def credit_packs do
    configured_packs()
    |> Enum.map(fn {key, pack} -> Map.put(pack, :key, key) end)
    |> Enum.sort_by(& &1.amount_cents)
  end

  @doc """
  Returns `{:ok, pack}` for a valid key.
  """
  @spec get_pack(String.t()) :: {:ok, pack()} | {:error, :unknown_pack}
  def get_pack(key) when is_binary(key) do
    case Map.fetch(configured_packs(), key) do
      {:ok, pack} -> {:ok, Map.put(pack, :key, key)}
      :error -> {:error, :unknown_pack}
    end
  end

  @doc """
  Returns a pack for `key` or raises `KeyError`.
  """
  @spec get_pack!(String.t()) :: pack()
  def get_pack!(key) when is_binary(key) do
    case get_pack(key) do
      {:ok, pack} -> pack
      {:error, :unknown_pack} -> raise KeyError, key: key, term: configured_packs()
    end
  end

  @spec configured_packs() :: %{
          optional(String.t()) => %{amount_cents: pos_integer(), credits: pos_integer()}
        }
  defp configured_packs do
    :my_app
    |> Application.get_env(MyApp.Credits, [])
    |> Keyword.get(:packs, %{})
  end
end
```

## Billing.Payments — Stripe PaymentIntent Creation

```elixir
defmodule MyApp.Billing.Payments do
  @moduledoc """
  Stripe PaymentIntent creation for credit purchases.
  """

  alias MyApp.Accounts.Account  # Adapt: use actual account schema
  alias MyApp.Billing
  alias MyApp.Billing.StripeCustomers

  @type payment_intent_result :: {:ok, Stripe.PaymentIntent.t()} | {:error, term()}

  @doc """
  Creates a PaymentIntent for the selected pack and account.
  """
  @spec create_payment_intent(Account.t(), String.t()) :: payment_intent_result()
  def create_payment_intent(%Account{} = account, pack_key) when is_binary(pack_key) do
    with {:ok, pack} <- Billing.get_pack(pack_key),
         {:ok, customer_id} <- StripeCustomers.ensure_customer_id(account) do
      Stripe.PaymentIntent.create(%{
        amount: pack.amount_cents,
        currency: "usd",
        customer: customer_id,
        automatic_payment_methods: %{enabled: true},
        description: purchase_description(pack),
        metadata: %{
          "pack_key" => pack.key,
          "account_id" => account.id
        }
      })
    end
  end

  defp purchase_description(pack) do
    "Purchased #{pack.credits} credits (#{pack.key})"
  end
end
```

## Billing.StripeCustomers — Lazy Customer Lifecycle

```elixir
defmodule MyApp.Billing.StripeCustomers do
  @moduledoc """
  Stripe customer lifecycle helpers for account billing.
  """

  alias MyApp.Accounts.Account  # Adapt: use actual account schema
  alias MyApp.Repo

  @doc """
  Returns the account's Stripe customer ID, creating and storing one lazily.
  """
  @spec ensure_customer_id(Account.t()) :: {:ok, String.t()} | {:error, term()}
  def ensure_customer_id(%Account{stripe_customer_id: customer_id})
      when is_binary(customer_id) and customer_id != "" do
    {:ok, customer_id}
  end

  def ensure_customer_id(%Account{} = account) do
    with {:ok, customer} <- create_customer(account),
         {:ok, updated_account} <- persist_customer_id(account, customer.id) do
      {:ok, updated_account.stripe_customer_id}
    end
  end

  defp create_customer(%Account{} = account) do
    Stripe.Customer.create(%{
      name: account.name,
      metadata: %{"account_id" => account.id}
    })
  end

  defp persist_customer_id(%Account{} = account, customer_id) do
    account
    |> Ecto.Changeset.change(stripe_customer_id: customer_id)
    |> Repo.update()
  end
end
```

**Adapt**: If the billing entity is a User instead of Account, change the association and pass user fields (email, name) to `Stripe.Customer.create`.

## Billing.CreditPurchaseWorker — Idempotent Credit Fulfillment

```elixir
defmodule MyApp.Billing.CreditPurchaseWorker do
  @moduledoc """
  Processes successful Stripe PaymentIntents and adds credits idempotently.
  """
  use Oban.Worker, queue: :default, max_attempts: 20

  alias MyApp.Billing
  alias MyApp.Credits

  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok | {:error, term()}
  def perform(%Oban.Job{
        args: %{
          "payment_intent_id" => payment_intent_id,
          "account_id" => account_id,
          "pack_key" => pack_key
        }
      }) do
    credit_account(account_id, payment_intent_id, pack_key)
  end

  def perform(%Oban.Job{}), do: {:error, :invalid_args}

  defp credit_account(account_id, payment_intent_id, pack_key) do
    with {:ok, pack} <- Billing.get_pack(pack_key),
         {:ok, _result} <-
           Credits.add(account_id, pack.credits, credit_add_opts(pack, payment_intent_id)) do
      :ok
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        if duplicate_purchase_error?(changeset), do: :ok, else: {:error, changeset}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp credit_add_opts(pack, payment_intent_id) do
    %{
      description: "Purchased #{pack.credits} credits (#{pack.key})",
      metadata: %{
        "stripe_payment_intent_id" => payment_intent_id,
        "pack_key" => pack.key,
        "amount_cents" => pack.amount_cents
      }
    }
  end

  defp duplicate_purchase_error?(%Ecto.Changeset{} = changeset) do
    Enum.any?(changeset.errors, fn
      {:account_id, {_message, opts}} ->
        opts[:constraint] == :unique and
          opts[:constraint_name] == :credit_transactions_account_id_payment_intent_id_index

      _ ->
        false
    end)
  end
end
```

**Key**: The worker uses `max_attempts: 20` for resilience and detects the unique constraint violation to handle duplicate webhook deliveries gracefully (returns `:ok` instead of erroring).
