# Context: API Key Functions

Add these functions to the relevant context module (e.g., `MyApp.Accounts`).

## Required Imports

At the top of the context module, ensure these aliases exist:

```elixir
alias MyApp.Accounts.ApiKey
alias MyApp.Repo
import Ecto.Query
```

## Functions

Add these inside the context module, grouped under an `# API Key Functions` section comment:

```elixir
  # API Key Functions
  # ============================================

  @doc "Verify an API token and return the key with parent preloaded."
  @spec verify_api_token(String.t()) :: {:ok, %ApiKey{}} | {:error, :invalid_token}
  def verify_api_token(token) do
    prefix = String.slice(token, 0, 12)
    hash = ApiKey.hash_token(token)

    query =
      from(k in ApiKey,
        where: k.token_prefix == ^prefix and k.token_hash == ^hash,
        where: k.status == :active,
        where: is_nil(k.expires_at) or k.expires_at > ^DateTime.utc_now(),
        # ADAPT: preload the parent and any needed associations
        preload: [:user]
      )

    case Repo.one(query) do
      nil -> {:error, :invalid_token}
      api_key -> {:ok, api_key}
    end
  end

  @doc "Update last_used_at timestamp for an API key."
  @spec touch_api_key(%ApiKey{}) :: {:ok, %ApiKey{}} | {:error, Ecto.Changeset.t()}
  def touch_api_key(api_key) do
    api_key
    |> Ecto.Changeset.change(last_used_at: DateTime.utc_now() |> DateTime.truncate(:second))
    |> Repo.update()
  end

  @doc """
  Create a new API key.
  Returns `{:ok, {api_key, raw_token}}` — the raw token is only available at creation time.
  """
  @spec create_api_key(struct(), map()) :: {:ok, {%ApiKey{}, String.t()}} | {:error, Ecto.Changeset.t()}
  def create_api_key(parent, attrs) do
    type = attrs[:type] || :public
    token = ApiKey.generate_token(type)
    prefix = String.slice(token, 0, 12)
    hash = ApiKey.hash_token(token)

    # ADAPT: Change :user_id to match parent foreign key
    changeset =
      %ApiKey{user_id: parent.id}
      |> ApiKey.changeset(Map.put(attrs, :user_id, parent.id))
      |> Ecto.Changeset.put_change(:token_prefix, prefix)
      |> Ecto.Changeset.put_change(:token_hash, hash)

    case Repo.insert(changeset) do
      {:ok, api_key} -> {:ok, {api_key, token}}
      error -> error
    end
  end

  @doc "List API keys for a parent record."
  @spec list_api_keys(struct()) :: [%ApiKey{}]
  def list_api_keys(parent) do
    # ADAPT: Change :user_id to match parent foreign key
    from(k in ApiKey, where: k.user_id == ^parent.id)
    |> Repo.all()
  end

  @doc "Revoke an API key (soft delete — sets status to :revoked)."
  @spec revoke_api_key(%ApiKey{}) :: {:ok, %ApiKey{}} | {:error, Ecto.Changeset.t()}
  def revoke_api_key(api_key) do
    api_key
    |> Ecto.Changeset.change(status: :revoked)
    |> Repo.update()
  end
```

## If key types are NOT needed

Remove the `type` parameter from `create_api_key/2` and use a single token generator:

```elixir
def create_api_key(parent, attrs) do
  token = ApiKey.generate_token()
  prefix = String.slice(token, 0, 12)
  hash = ApiKey.hash_token(token)
  # ... rest is the same
end
```
