# Context: Member Management Functions

Add these functions to the existing `lib/my_app/accounts.ex` context module.

## Required Imports

Add these aliases at the top of the module if not already present:

```elixir
alias MyApp.Accounts.{Account, AccountUser, User}
alias MyApp.Repo
import Ecto.Query
```

## Functions

### parse_member_role/1

```elixir
@doc """
Parses a role string into a role atom.

Returns `{:ok, role}` or `{:error, changeset}`.
"""
@spec parse_member_role(String.t()) :: {:ok, AccountUser.role()} | {:error, Ecto.Changeset.t()}
def parse_member_role("owner"), do: {:ok, :owner}
def parse_member_role("admin"), do: {:ok, :admin}
def parse_member_role("member"), do: {:ok, :member}

def parse_member_role(_) do
  changeset =
    %AccountUser{}
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.add_error(:role, "is invalid")

  {:error, changeset}
end
```

### authorize_role_assignment/2

```elixir
@doc """
Checks if the current account user can assign the given role.

Only owners can assign the `:owner` role.
"""
@spec authorize_role_assignment(AccountUser.t(), AccountUser.role()) ::
        :ok | {:error, :forbidden}
def authorize_role_assignment(current_au, :owner) do
  if AccountUser.owner?(current_au), do: :ok, else: {:error, :forbidden}
end

def authorize_role_assignment(_current_au, _role), do: :ok
```

### count_account_owners/1

```elixir
@doc """
Counts the number of owners in an account.
"""
@spec count_account_owners(Ecto.UUID.t()) :: non_neg_integer()
def count_account_owners(account_id) do
  from(au in AccountUser,
    where: au.account_id == ^account_id and au.role == :owner
  )
  |> Repo.aggregate(:count)
end
```

### list_account_members/1

```elixir
@doc """
Lists account members with preloaded user association.

Returns list of `AccountUser` structs ordered by `inserted_at` ascending.
"""
@spec list_account_members(Ecto.UUID.t()) :: [AccountUser.t()]
def list_account_members(account_id) do
  from(au in AccountUser,
    where: au.account_id == ^account_id,
    join: u in assoc(au, :user),
    order_by: [asc: au.inserted_at],
    limit: 200,
    preload: [user: u]
  )
  |> Repo.all()
end
```

### get_account_member/2

```elixir
@doc """
Gets a single account member by membership ID, scoped to the account.

Returns `{:ok, account_user}` with preloaded user, or `{:error, :not_found}`.
"""
@spec get_account_member(Ecto.UUID.t(), Ecto.UUID.t()) ::
        {:ok, AccountUser.t()} | {:error, :not_found}
def get_account_member(account_id, id) do
  query =
    from(au in AccountUser,
      where: au.id == ^id and au.account_id == ^account_id,
      preload: [:user]
    )

  case Repo.one(query) do
    nil -> {:error, :not_found}
    account_user -> {:ok, account_user}
  end
end
```

### invite_user_to_account/3

```elixir
@doc """
Invites a user to an account by email.

Finds or creates a user by email, then creates an `account_user` membership.
Returns `{:ok, account_user}` or `{:error, changeset}`.
"""
@spec invite_user_to_account(Ecto.UUID.t(), String.t(), AccountUser.role()) ::
        {:ok, AccountUser.t()} | {:error, Ecto.Changeset.t()}
def invite_user_to_account(account_id, email, role) do
  Repo.transaction(fn ->
    with {:ok, user} <- find_or_create_user(email),
         {:ok, account_user} <- do_add_user_to_account(account_id, user, role) do
      Repo.preload(account_user, [:user])
    else
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end)
end

defp find_or_create_user(email) do
  case get_user_by_email(email) do
    nil ->
      case register_user(%{email: email}) do
        {:ok, user} -> {:ok, user}
        error -> error
      end

    user ->
      {:ok, user}
  end
end

defp do_add_user_to_account(account_id, user, role) do
  %AccountUser{}
  |> AccountUser.changeset(%{
    account_id: account_id,
    user_id: user.id,
    role: role
  })
  |> Repo.insert()
end
```

**Note:** `get_user_by_email/1` and `register_user/1` should already exist from `phx.gen.auth`. If `register_user/1` provisions a default account (from `/bootstrap-accounts`), you may want to pass an option to skip that when creating users via invite. Adapt accordingly.

### delete_account_member/1

```elixir
@doc """
Deletes an account member, checking that they are not the last owner.

Returns `:ok` or `{:error, changeset}`.
"""
@spec delete_account_member(AccountUser.t()) :: :ok | {:error, Ecto.Changeset.t()}
def delete_account_member(member) do
  if member.role == :owner && count_account_owners(member.account_id) <= 1 do
    changeset =
      %AccountUser{}
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.add_error(:role, "account must have at least one owner")

    {:error, changeset}
  else
    case Repo.delete(member) do
      {:ok, _} ->
        clear_default_account_if_needed(member)
        :ok

      {:error, changeset} ->
        {:error, changeset}
    end
  end
end

defp clear_default_account_if_needed(member) do
  from(u in User,
    where: u.id == ^member.user_id and u.default_account_id == ^member.account_id
  )
  |> Repo.update_all(set: [default_account_id: nil])
end
```

**Note:** If the User schema does not have a `default_account_id` field, remove the `clear_default_account_if_needed/1` function and its call. This field is added by `/bootstrap-accounts`.
