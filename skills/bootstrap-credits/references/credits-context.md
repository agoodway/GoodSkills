# Credits Context Reference

The credits context module is the core of the credit system. It handles all credit operations with atomic guarantees.

**Adapt**: Replace `MyApp` with the actual app module, `:my_app` with the OTP app name, and `MyApp.Cache` with the actual cache module (or remove caching if no cache exists).

```elixir
defmodule MyApp.Credits do
  @moduledoc """
  Credit management context for account-level billing.

  Handles credit balances, deductions, additions, and usage tracking.
  All credit operations use optimistic locking to prevent concurrent
  deduction races, and Ecto.Multi for atomic balance + transaction + event writes.
  """

  import Ecto.Query

  # Dialyzer false positive: Ecto.Multi.new() returns an opaque type
  @dialyzer {:nowarn_function, add: 3, build_deduct_multi: 3}

  alias Ecto.Multi
  alias MyApp.Credits.{CreditBalance, CreditTransaction, UsageEvent}
  alias MyApp.Repo
  # alias MyApp.Cache  # uncomment if cache module exists

  @default_cache_ttl :timer.seconds(30)

  # ============================================
  # Cost Registry
  # ============================================

  @doc """
  Computes the total credit cost for an operation with optional add-ons.

  Returns the integer cost or `{:error, :unknown_operation}`.
  """
  @spec compute_cost(atom(), [atom()]) :: non_neg_integer() | {:error, :unknown_operation}
  def compute_cost(operation, add_ons \\ []) do
    config = Application.get_env(:my_app, __MODULE__, [])
    costs = Keyword.get(config, :costs, %{})
    add_on_costs = Keyword.get(config, :add_ons, %{})

    case Map.fetch(costs, operation) do
      {:ok, base_cost} ->
        add_on_total =
          add_ons
          |> Enum.map(&Map.get(add_on_costs, &1, 0))
          |> Enum.sum()

        base_cost + add_on_total

      :error ->
        {:error, :unknown_operation}
    end
  end

  # ============================================
  # Balance Queries
  # ============================================

  @doc """
  Returns the current credit balance for an account.

  If a cache module exists, uses it with a 30-second TTL.
  Falls back to database on cache miss.
  """
  @spec get_balance(binary()) :: non_neg_integer()
  def get_balance(account_id) do
    # WITH CACHE (uncomment if cache module exists):
    # cache_key = {:credit_balance, account_id}
    # case Cache.get(cache_key) do
    #   nil ->
    #     balance = fetch_balance_from_db(account_id)
    #     Cache.put(cache_key, balance, ttl: cache_ttl())
    #     balance
    #   cached ->
    #     cached
    # end

    # WITHOUT CACHE:
    fetch_balance_from_db(account_id)
  end

  @doc """
  Checks whether an account has at least `cost` credits.
  """
  @spec has_sufficient_credits?(binary(), non_neg_integer()) :: boolean()
  def has_sufficient_credits?(account_id, cost) do
    get_balance(account_id) >= cost
  end

  # ============================================
  # Credit Operations
  # ============================================

  @doc """
  Atomically deducts credits and records a usage event.

  Uses Ecto.Multi to ensure the balance decrement, transaction log entry,
  and usage event are all committed together. Retries once on optimistic
  lock conflict.

  ## Options

  - `:description` — human-readable description for the transaction log
  - `:metadata` — arbitrary map stored on the transaction
  - `:usage_event` — map of usage event attributes to insert atomically

  Returns `{:ok, %{transaction: transaction, balance: balance}}` on success,
  or `{:error, :insufficient_credits}` / `{:error, :conflict}` on failure.
  """
  @spec deduct(binary(), non_neg_integer(), map()) ::
          {:ok, %{transaction: CreditTransaction.t(), balance: CreditBalance.t()}}
          | {:error, :insufficient_credits | :conflict}
  def deduct(account_id, cost, opts \\ %{}) do
    do_deduct(account_id, cost, opts, _retries = 1)
  end

  @doc """
  Adds credits to an account with a transaction log entry.

  Returns `{:ok, %{transaction: transaction, balance: balance}}`.
  """
  @spec add(binary(), non_neg_integer(), map()) ::
          {:ok, %{transaction: CreditTransaction.t(), balance: CreditBalance.t()}}
          | {:error, term()}
  def add(account_id, amount, opts \\ %{}) do
    description = Map.get(opts, :description, "Credit addition")
    metadata = Map.get(opts, :metadata, %{})

    Multi.new()
    |> Multi.one(:current_balance, fn _changes ->
      from(cb in CreditBalance,
        where: cb.account_id == ^account_id,
        lock: "FOR UPDATE"
      )
    end)
    |> Multi.run(:balance, fn _repo, %{current_balance: cb} ->
      if cb do
        new_balance = cb.balance + amount

        cb
        |> Ecto.Changeset.change(balance: new_balance)
        |> Ecto.Changeset.optimistic_lock(:lock_version)
        |> Repo.update()
      else
        {:error, :no_balance_record}
      end
    end)
    |> Multi.insert(:transaction, fn %{balance: balance} ->
      CreditTransaction.changeset(%CreditTransaction{}, %{
        account_id: account_id,
        amount: amount,
        balance_after: balance.balance,
        type: :addition,
        description: description,
        metadata: metadata
      })
    end)
    |> Repo.transaction()
    |> case do
      {:ok, result} ->
        invalidate_balance_cache(account_id)
        {:ok, %{transaction: result.transaction, balance: result.balance}}

      {:error, _step, reason, _changes} ->
        {:error, reason}
    end
  end

  @doc """
  Returns usage summary for an account within a date range.
  """
  @spec get_usage(binary(), {Date.t(), Date.t()}) :: map()
  def get_usage(account_id, {start_date, end_date}) do
    start_dt = DateTime.new!(start_date, ~T[00:00:00], "Etc/UTC")
    end_dt = DateTime.new!(end_date, ~T[23:59:59], "Etc/UTC")

    base_query =
      from(ue in UsageEvent,
        where: ue.account_id == ^account_id,
        where: ue.inserted_at >= ^start_dt and ue.inserted_at <= ^end_dt
      )

    {total_operations, total_credits_used, cache_hits} =
      from(ue in base_query,
        select:
          {count(ue.id), coalesce(sum(ue.credit_cost), 0),
           sum(fragment("CASE WHEN ? THEN 1 ELSE 0 END", ue.cache_hit))}
      )
      |> Repo.one()
      |> then(fn {ops, credits, hits} -> {ops || 0, credits || 0, hits || 0} end)

    operations_by_type =
      from(ue in base_query,
        group_by: ue.operation,
        select: {ue.operation, count(ue.id)}
      )
      |> Repo.all()
      |> Map.new()

    cache_hit_rate =
      if total_operations > 0, do: cache_hits / total_operations, else: 0.0

    %{
      total_operations: total_operations,
      total_credits_used: total_credits_used,
      operations_by_type: operations_by_type,
      cache_hit_rate: cache_hit_rate
    }
  end

  # ============================================
  # Paginated Listing Functions
  # ============================================

  @default_per_page 25
  @max_per_page 100

  @doc """
  Returns paginated credit transactions for an account.

  Returns `{entries, total_count}` ordered by `inserted_at` descending.
  """
  @spec list_transactions(binary(), keyword()) :: {[CreditTransaction.t()], non_neg_integer()}
  def list_transactions(account_id, opts \\ []) do
    page = max(1, Keyword.get(opts, :page, 1))
    per_page = opts |> Keyword.get(:per_page, @default_per_page) |> min(@max_per_page) |> max(1)
    offset = (page - 1) * per_page

    base_query = from(ct in CreditTransaction, where: ct.account_id == ^account_id)

    entries =
      from(ct in base_query,
        order_by: [desc: ct.inserted_at, desc: ct.id],
        limit: ^per_page,
        offset: ^offset
      )
      |> Repo.all()

    total_count = Repo.aggregate(base_query, :count, :id)

    {entries, total_count}
  end

  @doc """
  Returns paginated usage events for an account.

  Returns `{entries, total_count}` ordered by `inserted_at` descending.
  """
  @spec list_usage_events(binary(), keyword()) :: {[UsageEvent.t()], non_neg_integer()}
  def list_usage_events(account_id, opts \\ []) do
    page = max(1, Keyword.get(opts, :page, 1))
    per_page = opts |> Keyword.get(:per_page, @default_per_page) |> min(@max_per_page) |> max(1)
    offset = (page - 1) * per_page

    base_query = from(ue in UsageEvent, where: ue.account_id == ^account_id)

    entries =
      from(ue in base_query,
        order_by: [desc: ue.inserted_at, desc: ue.id],
        # left_join: ak in assoc(ue, :api_key),  # uncomment if api_keys exist
        # preload: [api_key: ak],
        limit: ^per_page,
        offset: ^offset
      )
      |> Repo.all()

    total_count = Repo.aggregate(base_query, :count, :id)

    {entries, total_count}
  end

  @doc """
  Records a usage event (e.g., for cache hits that cost zero credits).
  """
  @spec record_usage_event(map()) :: {:ok, UsageEvent.t()} | {:error, Ecto.Changeset.t()}
  def record_usage_event(attrs) do
    %UsageEvent{}
    |> UsageEvent.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates a credit balance for an account with the configured default balance.
  """
  @spec create_balance(binary(), non_neg_integer() | nil) ::
          {:ok, CreditBalance.t()} | {:error, Ecto.Changeset.t()}
  def create_balance(account_id, balance \\ nil) do
    balance = if is_nil(balance), do: default_balance(), else: balance

    %CreditBalance{}
    |> CreditBalance.changeset(%{account_id: account_id, balance: balance})
    |> Repo.insert()
  end

  @doc """
  Returns whether credit enforcement is enabled.
  """
  @spec enforcement_enabled?() :: boolean()
  def enforcement_enabled? do
    config = Application.get_env(:my_app, __MODULE__, [])
    Keyword.get(config, :enforce_credits, true)
  end

  @doc """
  Returns the configured default balance for new accounts.
  """
  @spec default_balance() :: non_neg_integer()
  def default_balance do
    config = Application.get_env(:my_app, __MODULE__, [])
    Keyword.get(config, :default_balance, 10)
  end

  @doc """
  Returns the configured cache TTL for credit balances.
  """
  @spec cache_ttl() :: non_neg_integer()
  def cache_ttl do
    config = Application.get_env(:my_app, __MODULE__, [])
    Keyword.get(config, :cache_ttl, @default_cache_ttl)
  end

  # ============================================
  # Private Functions
  # ============================================

  defp do_deduct(account_id, cost, opts, retries) do
    account_id
    |> build_deduct_multi(cost, opts)
    |> Repo.transaction()
    |> handle_deduct_result(account_id, cost, opts, retries)
  end

  defp build_deduct_multi(account_id, cost, opts) do
    description = Map.get(opts, :description, "Credit deduction")
    metadata = Map.get(opts, :metadata, %{})
    usage_event_attrs = Map.get(opts, :usage_event, nil)

    multi =
      Multi.new()
      |> Multi.one(:current_balance, fn _changes ->
        from(cb in CreditBalance, where: cb.account_id == ^account_id)
      end)
      |> Multi.run(:check_balance, fn _repo, %{current_balance: cb} ->
        if is_nil(cb) or cb.balance < cost,
          do: {:error, :insufficient_credits},
          else: {:ok, cb}
      end)
      |> Multi.run(:balance, fn _repo, %{check_balance: cb} ->
        cb
        |> Ecto.Changeset.change(balance: cb.balance - cost)
        |> Ecto.Changeset.optimistic_lock(:lock_version)
        |> Repo.update()
      end)
      |> Multi.insert(:transaction, fn %{balance: balance} ->
        CreditTransaction.changeset(%CreditTransaction{}, %{
          account_id: account_id,
          amount: -cost,
          balance_after: balance.balance,
          type: :deduction,
          description: description,
          metadata: metadata
        })
      end)

    if usage_event_attrs do
      Multi.insert(multi, :usage_event, fn _changes ->
        UsageEvent.changeset(%UsageEvent{}, usage_event_attrs)
      end)
    else
      multi
    end
  end

  defp handle_deduct_result({:ok, result}, account_id, _cost, _opts, _retries) do
    invalidate_balance_cache(account_id)
    {:ok, %{transaction: result.transaction, balance: result.balance}}
  end

  defp handle_deduct_result(
         {:error, :balance, %Ecto.StaleEntryError{}, _},
         account_id,
         cost,
         opts,
         retries
       )
       when retries > 0 do
    do_deduct(account_id, cost, opts, retries - 1)
  end

  defp handle_deduct_result({:error, :balance, %Ecto.StaleEntryError{}, _}, _, _, _, _) do
    {:error, :conflict}
  end

  defp handle_deduct_result({:error, :check_balance, :insufficient_credits, _}, _, _, _, _) do
    {:error, :insufficient_credits}
  end

  defp handle_deduct_result({:error, _step, reason, _}, _, _, _, _) do
    {:error, reason}
  end

  defp fetch_balance_from_db(account_id) do
    case Repo.one(
           from(cb in CreditBalance, where: cb.account_id == ^account_id, select: cb.balance)
         ) do
      nil -> 0
      balance -> balance
    end
  end

  defp invalidate_balance_cache(account_id) do
    # Uncomment if cache module exists:
    # Cache.delete({:credit_balance, account_id})
    _ = account_id
    :ok
  end
end
```
