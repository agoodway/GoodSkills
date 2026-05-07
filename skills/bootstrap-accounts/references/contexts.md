# Contexts: Accounts & AccountContext

## Accounts Context Additions

Add these functions to the existing `lib/my_app/accounts.ex` context module:

```elixir
alias MyApp.Accounts.{Account, AccountUser}

@doc """
Lists all accounts a user has access to, with their role.
Returns [{account, role}] sorted by account name.
"""
def list_user_accounts(%User{} = user) do
  AccountUser
  |> where([au], au.user_id == ^user.id)
  |> join(:inner, [au], a in Account, on: au.account_id == a.id)
  |> where([au, a], a.status == :active)
  |> select([au, a], {a, au.role})
  |> order_by([au, a], asc: a.name)
  |> Repo.all()
end

@doc """
Gets a single account by ID.
"""
def get_account(id) when is_binary(id) do
  Repo.get(Account, id)
end

@doc """
Gets the AccountUser record for a user+account pair.
Returns nil if the user doesn't belong to the account.
"""
def get_account_user(%User{} = user, %Account{} = account) do
  Repo.get_by(AccountUser, user_id: user.id, account_id: account.id)
end

@doc """
Creates an account.
"""
def create_account(attrs \\ %{}) do
  %Account{}
  |> Account.changeset(attrs)
  |> Repo.insert()
end

@doc """
Creates an account user membership.
"""
def create_account_user(attrs \\ %{}) do
  %AccountUser{}
  |> AccountUser.changeset(attrs)
  |> Repo.insert()
end
```

Required imports at the top of the Accounts context (add if not present):

```elixir
import Ecto.Query
```

## AccountContext Module

Create `lib/my_app/account_context.ex`:

```elixir
defmodule MyApp.AccountContext do
  @moduledoc """
  Context module for managing account-scoped operations and user account access.
  """

  alias MyApp.Accounts
  alias MyApp.Accounts.{Account, AccountUser, User}

  @spec list_user_accounts(User.t()) :: [{Account.t(), AccountUser.role()}]
  def list_user_accounts(%User{} = user) do
    Accounts.list_user_accounts(user)
  end

  @spec get_account_for_user(User.t(), String.t() | Ecto.UUID.t()) ::
          {:ok, Account.t()} | {:error, :not_found}
  def get_account_for_user(_user, nil), do: {:error, :not_found}

  def get_account_for_user(%User{} = user, account_id) when is_binary(account_id) do
    with {:ok, uuid} <- Ecto.UUID.cast(account_id),
         %Account{} = account <- Accounts.get_account(uuid),
         true <- user_has_access?(user, account) do
      {:ok, account}
    else
      _ -> {:error, :not_found}
    end
  end

  @spec user_has_access?(User.t(), Account.t()) :: boolean()
  def user_has_access?(%User{} = user, %Account{} = account) do
    case Accounts.get_account_user(user, account) do
      nil -> false
      %AccountUser{} -> true
    end
  end

  @spec get_default_account(User.t(), map()) :: {:ok, Account.t()} | {:error, :no_accounts}
  def get_default_account(%User{} = user, session) do
    last_account_id = session["last_account_id"]

    if last_account_id do
      case get_account_for_user(user, last_account_id) do
        {:ok, account} -> {:ok, account}
        {:error, _} -> first_account(user)
      end
    else
      first_account(user)
    end
  end

  defp first_account(user) do
    case list_user_accounts(user) do
      [{account, _role} | _] -> {:ok, account}
      [] -> {:error, :no_accounts}
    end
  end
end
```
