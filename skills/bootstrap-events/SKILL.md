---
name: bootstrap-events
description: "Bootstrap Event Subscription System"
---

# Bootstrap Event Subscription System

Set up a complete event-driven notification system in a Phoenix 1.8 application with:
- Event struct and PubSub-based event bus
- Database-backed event subscriptions (email, SMS, webhook channels)
- Listener GenServer for orchestrating delivery
- Oban workers for email, SMS, webhook, and in-app delivery
- Notification delivery logging
- Webhook signing (Standard Webhooks spec)
- LiveView real-time integration
- Multi-tenant account scoping

**Prerequisites:**
- Phoenix 1.8+ application with PostgreSQL and binary_id primary keys
- Oban already configured
- Swoosh already configured for email
- An `accounts` table with binary_id primary key
- A `users` table with `email` and optionally `phone` fields
- Phoenix.PubSub already in supervision tree

## Phase 0: Detect What Already Exists

Before generating anything, check what's already in place:

### 0.1 Detection Steps

1. Check for existing PubSub in `application.ex`
2. Check for existing Oban configuration
3. Check for existing Swoosh mailer
4. Check for existing notification/event modules
5. Identify the app name and module prefix from `mix.exs`

```bash
# Get app name
grep "app:" mix.exs | head -1

# Check for PubSub
grep -r "Phoenix.PubSub" lib/*/application.ex

# Check for Oban
grep -r "Oban" config/config.exs

# Check for existing notification modules
find lib -name "notifications*" -o -name "event*" | head -20

# Check for accounts/users tables
find priv/repo/migrations -name "*accounts*" -o -name "*users*"
```

### 0.2 What You Need from the User

Before proceeding, determine:
1. **App module prefix** (e.g., `MyApp`) — derive from mix.exs
2. **PubSub name** (e.g., `MyApp.PubSub`) — find in application.ex
3. **Mailer module** (e.g., `MyApp.Mailer`) — find in lib/
4. **Event types** — ask the user what business events they want to support, or provide sensible defaults based on the domain
5. **Tenant scoping field** — usually `account_id`, confirm with user
6. **Optional secondary scope** — e.g., `organization_id`, `team_id`, `buyer_id` (for sub-tenant routing)

## Phase 1: Database Migrations

Create two migrations: `event_subscriptions` and `notification_logs`.

### 1.1 Event Subscriptions Migration

```bash
mix ecto.gen.migration create_event_subscriptions
```

Write the migration:

```elixir
defmodule MyApp.Repo.Migrations.CreateEventSubscriptions do
  use Ecto.Migration

  def change do
    create table(:event_subscriptions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :event_types, {:array, :string}, null: false, default: []
      add :channel, :string, null: false
      add :destination, :string
      add :criteria, :string
      add :secret, :string
      add :active, :boolean, null: false, default: true
      add :name, :string

      add :account_id, references(:accounts, type: :binary_id, on_delete: :delete_all),
        null: false

      # Optional: secondary scope (e.g., organization_id, team_id)
      # add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all)

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all)

      timestamps(type: :utc_datetime)
    end

    create constraint(:event_subscriptions, :event_subscriptions_channel_check,
             check: "channel IN ('email', 'sms', 'webhook')"
           )

    create index(:event_subscriptions, [:account_id])

    # Unique constraints prevent duplicate subscriptions
    create unique_index(
             :event_subscriptions,
             [:account_id, :channel, :destination],
             where: "destination IS NOT NULL",
             name: :event_subscriptions_static_destination_index
           )

    create unique_index(
             :event_subscriptions,
             [:account_id, :channel, :user_id],
             where: "user_id IS NOT NULL",
             name: :event_subscriptions_user_linked_index
           )
  end
end
```

**Note:** If the app has a secondary scope (e.g., `organization_id`), add it to the unique indexes as well.

### 1.2 Notification Logs Migration

```bash
mix ecto.gen.migration create_notification_logs
```

```elixir
defmodule MyApp.Repo.Migrations.CreateNotificationLogs do
  use Ecto.Migration

  def change do
    create table(:notification_logs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :event_type, :string, null: false

      add :account_id, references(:accounts, type: :binary_id, on_delete: :delete_all),
        null: false

      add :subscription_id,
          references(:event_subscriptions, type: :binary_id, on_delete: :nilify_all)

      add :destination, :string, null: false
      add :channel, :string, null: false
      add :status, :string, null: false
      add :error, :text
      add :resource_type, :string
      add :resource_id, :binary_id

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:notification_logs, [:account_id, :inserted_at])
    create index(:notification_logs, [:subscription_id])
    create index(:notification_logs, [:status])
  end
end
```

### 1.3 Run Migrations

```bash
mix ecto.migrate
```

## Phase 2: Event Struct

Create the event struct at `lib/<app>/notifications/event.ex`.

### Design Principles

- Events are plain structs (not Ecto schemas) — they're broadcast via PubSub, not persisted
- Every event has a unique `event_id` (UUID v4) generated at creation time
- `account_id` is required for tenant scoping
- Optional secondary scope field for sub-tenant routing
- `data` map carries the event-specific payload
- `occurred_at` is always UTC

```elixir
defmodule MyApp.Notifications.Event do
  @moduledoc """
  Standard struct for all business events broadcast via the event bus.

  Every event has a unique `event_id` (UUID v4), a `type` atom identifying
  the business event, an `account_id` for tenant scoping, a `data` map with
  event-specific payload, and an `occurred_at` UTC datetime.
  """

  # CUSTOMIZE: Define event types for your domain
  @event_types ~w(
    resource_created
    resource_updated
    resource_deleted
  )a

  @type t :: %__MODULE__{
          event_id: String.t(),
          type: atom(),
          account_id: String.t(),
          data: map(),
          occurred_at: DateTime.t()
        }

  @enforce_keys [:event_id, :type, :account_id, :data, :occurred_at]
  defstruct [:event_id, :type, :account_id, :data, :occurred_at]

  @spec event_types :: [atom()]
  def event_types, do: @event_types

  @spec new(atom(), String.t(), map(), keyword()) :: t()
  def new(type, account_id, data, opts \\ []) when type in @event_types do
    struct!(__MODULE__,
      event_id: Ecto.UUID.generate(),
      type: type,
      account_id: account_id,
      data: Map.merge(data, Map.new(opts)),
      occurred_at: DateTime.utc_now()
    )
  end
end
```

**IMPORTANT customization points:**
- Replace `@event_types` with actual domain events (e.g., `order_placed`, `payment_received`, `user_invited`)
- Add optional secondary scope field if needed (e.g., `organization_id`, `team_id`)
- If you need scoped event type lists (admin vs user), add `@admin_event_types` and `@user_event_types` module attributes

## Phase 3: Event Subscription Schema

Create `lib/<app>/notifications/event_subscription.ex`.

### Key Design Decisions

- `destination` (static email/phone/URL) is mutually exclusive with `user_id` (resolved at delivery time)
- Webhook subscriptions auto-generate a signing secret
- Webhook URLs must use HTTPS (localhost HTTP allowed in dev/test)
- `criteria` field supports optional filtering (if you use the `predicated` library)

```elixir
defmodule MyApp.Notifications.EventSubscription do
  @moduledoc """
  Schema for event subscriptions that declare who receives which events.

  Each subscription configures:
  - **event_types**: which events to receive
  - **channel**: delivery channel — `"email"`, `"sms"`, or `"webhook"`
  - **destination**: static address (mutually exclusive with `user_id`)
  - **user_id**: resolves to user's email/phone at delivery time
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias MyApp.Accounts.{Account, User}
  alias MyApp.Notifications.Event
  alias MyApp.Notifications.WebhookSigner

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          event_types: [String.t()],
          channel: String.t() | nil,
          destination: String.t() | nil,
          criteria: String.t() | nil,
          secret: String.t() | nil,
          active: boolean(),
          name: String.t() | nil,
          account_id: Ecto.UUID.t() | nil,
          user_id: Ecto.UUID.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @channels ~w(email sms webhook)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "event_subscriptions" do
    field :event_types, {:array, :string}, default: []
    field :channel, :string
    field :destination, :string
    field :criteria, :string
    field :secret, :string
    field :active, :boolean, default: false
    field :name, :string

    belongs_to :account, Account
    belongs_to :user, User

    timestamps(type: :utc_datetime)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(subscription, attrs) do
    subscription
    |> cast(attrs, [:event_types, :channel, :destination, :criteria, :active, :name, :account_id, :user_id])
    |> validate_required([:account_id, :channel, :name])
    |> validate_inclusion(:channel, @channels)
    |> validate_event_types()
    |> validate_destination_or_user()
    |> validate_webhook_settings()
    |> foreign_key_constraint(:account_id)
    |> foreign_key_constraint(:user_id)
    |> check_constraint(:channel, name: :event_subscriptions_channel_check)
    |> unique_constraint([:account_id, :channel, :destination],
      name: :event_subscriptions_static_destination_index
    )
    |> unique_constraint([:account_id, :channel, :user_id],
      name: :event_subscriptions_user_linked_index
    )
  end

  @spec update_changeset(t(), map()) :: Ecto.Changeset.t()
  def update_changeset(subscription, attrs) do
    subscription
    |> cast(attrs, [:event_types, :active, :name, :destination, :user_id, :criteria])
    |> validate_required([:name])
    |> validate_event_types()
    |> validate_destination_or_user()
    |> validate_webhook_settings()
    |> foreign_key_constraint(:user_id)
    |> unique_constraint([:account_id, :channel, :destination],
      name: :event_subscriptions_static_destination_index
    )
    |> unique_constraint([:account_id, :channel, :user_id],
      name: :event_subscriptions_user_linked_index
    )
  end

  @valid_event_types Enum.map(Event.event_types(), &Atom.to_string/1)

  @spec validate_event_types(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp validate_event_types(changeset) do
    event_types = get_field(changeset, :event_types)

    cond do
      is_nil(event_types) or event_types == [] ->
        add_error(changeset, :event_types, "must have at least one event type")

      invalid = Enum.find(event_types, &(&1 not in @valid_event_types)) ->
        add_error(changeset, :event_types, "contains invalid event type: #{invalid}")

      true ->
        changeset
    end
  end

  @spec validate_destination_or_user(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp validate_destination_or_user(changeset) do
    destination = get_field(changeset, :destination)
    user_id = get_field(changeset, :user_id)

    case {destination, user_id} do
      {nil, nil} ->
        add_error(changeset, :destination, "either destination or user_id must be set")

      {dest, uid} when not is_nil(dest) and not is_nil(uid) ->
        add_error(changeset, :destination, "cannot set both destination and user_id")

      _ ->
        changeset
    end
  end

  @spec validate_webhook_settings(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp validate_webhook_settings(changeset) do
    if get_field(changeset, :channel) == "webhook" do
      changeset
      |> validate_webhook_destination()
      |> validate_webhook_user()
      |> maybe_put_webhook_secret()
    else
      changeset
    end
  end

  @spec validate_webhook_destination(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp validate_webhook_destination(changeset) do
    destination = get_field(changeset, :destination)

    cond do
      is_nil(destination) ->
        add_error(changeset, :destination, "must be set for webhook subscriptions")

      valid_webhook_destination?(destination) ->
        changeset

      true ->
        add_error(changeset, :destination, "must use https:// (http://localhost allowed in dev/test)")
    end
  end

  @spec validate_webhook_user(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp validate_webhook_user(changeset) do
    if is_nil(get_field(changeset, :user_id)) do
      changeset
    else
      add_error(changeset, :user_id, "must be blank for webhook subscriptions")
    end
  end

  @spec maybe_put_webhook_secret(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp maybe_put_webhook_secret(changeset) do
    secret = get_field(changeset, :secret)

    if is_binary(secret) and secret != "" do
      changeset
    else
      put_change(changeset, :secret, WebhookSigner.generate_secret())
    end
  end

  @spec valid_webhook_destination?(String.t()) :: boolean()
  defp valid_webhook_destination?(destination) do
    String.starts_with?(destination, "https://") or
      (Application.get_env(:my_app, :env) in [:dev, :test] and
         String.starts_with?(destination, "http://localhost"))
  end
end
```

**IMPORTANT:** Replace `:my_app` in `valid_webhook_destination?/1` with the actual app atom.

## Phase 4: Notification Log Schema

Create `lib/<app>/notifications/notification_log.ex`.

```elixir
defmodule MyApp.Notifications.NotificationLog do
  @moduledoc """
  Append-only audit log for notification delivery attempts.

  Records every delivery attempt with its status (pending/delivered/failed),
  the destination, channel, and any error details.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias MyApp.Accounts.Account
  alias MyApp.Notifications.EventSubscription

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          event_type: String.t() | nil,
          account_id: Ecto.UUID.t() | nil,
          subscription_id: Ecto.UUID.t() | nil,
          destination: String.t() | nil,
          channel: String.t() | nil,
          status: String.t() | nil,
          error: String.t() | nil,
          resource_type: String.t() | nil,
          resource_id: Ecto.UUID.t() | nil,
          inserted_at: DateTime.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "notification_logs" do
    field :event_type, :string
    field :destination, :string
    field :channel, :string
    field :status, :string
    field :error, :string
    field :resource_type, :string
    field :resource_id, :binary_id

    belongs_to :account, Account
    belongs_to :subscription, EventSubscription

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @required_fields ~w(event_type account_id destination channel status)a
  @optional_fields ~w(subscription_id error resource_type resource_id)a

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(%__MODULE__{} = log, attrs) do
    log
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:status, ~w(pending delivered failed))
    |> validate_inclusion(:channel, ~w(email sms webhook))
  end
end
```

## Phase 5: Webhook Signing

Create three files for Standard Webhooks-compliant webhook delivery.

### 5.1 WebhookSigner

`lib/<app>/notifications/webhook_signer.ex`

```elixir
defmodule MyApp.Notifications.WebhookSigner do
  @moduledoc """
  Standard Webhooks compatible HMAC-SHA256 signing.
  """

  @secret_prefix "whsec_"

  @spec generate_secret() :: String.t()
  def generate_secret do
    @secret_prefix <> (24 |> :crypto.strong_rand_bytes() |> Base.encode64(padding: false))
  end

  @spec sign(String.t(), String.t(), String.t() | integer(), String.t()) :: String.t()
  def sign(secret, msg_id, timestamp, body) do
    key = decode_secret!(secret)
    payload = "#{msg_id}.#{timestamp}.#{body}"

    digest =
      :crypto.mac(:hmac, :sha256, key, payload)
      |> Base.encode64(padding: false)

    "v1," <> digest
  end

  @spec secure_compare(String.t(), String.t()) :: boolean()
  def secure_compare(left, right)
      when is_binary(left) and is_binary(right) and byte_size(left) == byte_size(right) do
    Plug.Crypto.secure_compare(left, right)
  end

  def secure_compare(_, _), do: false

  @spec decode_secret!(String.t()) :: binary()
  defp decode_secret!(<<@secret_prefix, encoded::binary>>) do
    Base.decode64!(encoded, padding: false)
  end

  defp decode_secret!(secret) do
    raise ArgumentError, "invalid webhook secret: #{inspect(secret)}"
  end
end
```

### 5.2 WebhookPayload

`lib/<app>/notifications/webhook_payload.ex`

```elixir
defmodule MyApp.Notifications.WebhookPayload do
  @moduledoc """
  Builds Standard Webhooks JSON payloads.
  """

  @spec build(String.t(), map(), DateTime.t() | NaiveDateTime.t() | String.t()) :: String.t()
  def build(event_type, event_data, occurred_at) do
    %{
      "type" => String.replace(event_type, "_", "."),
      "timestamp" => to_iso8601(occurred_at),
      "data" => event_data
    }
    |> Jason.encode!()
  end

  @spec to_iso8601(DateTime.t() | NaiveDateTime.t() | String.t()) :: String.t()
  defp to_iso8601(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp to_iso8601(%NaiveDateTime{} = dt), do: NaiveDateTime.to_iso8601(dt) <> "Z"
  defp to_iso8601(value) when is_binary(value), do: value
end
```

### 5.3 WebhookClient Behaviour + HTTP Implementation

`lib/<app>/notifications/webhook_client.ex`

```elixir
defmodule MyApp.Notifications.WebhookClient do
  @moduledoc """
  Behaviour for delivering webhook HTTP requests.
  """

  @callback post(String.t(), [{String.t(), String.t()}], String.t()) ::
              {:ok, non_neg_integer()} | {:error, term()}
end
```

`lib/<app>/notifications/webhook_client/http.ex`

```elixir
defmodule MyApp.Notifications.WebhookClient.HTTP do
  @moduledoc """
  Req-based webhook delivery implementation.
  """

  @behaviour MyApp.Notifications.WebhookClient

  @request_timeout_ms 20_000

  @impl true
  @spec post(String.t(), [{String.t(), String.t()}], String.t()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def post(url, headers, body) do
    case Req.post(url,
           headers: headers,
           body: body,
           redirect: false,
           receive_timeout: @request_timeout_ms
         ) do
      {:ok, %Req.Response{status: status}} -> {:ok, status}
      {:error, exception} -> {:error, exception}
    end
  end
end
```

## Phase 6: Notifications Context Module

Create `lib/<app>/notifications.ex` — the main event bus and subscription management API.

### Architecture

This module serves two purposes:
1. **Event Bus** — `subscribe/1` and `emit/1` for PubSub
2. **Subscription CRUD** — database operations for managing subscriptions and logs

### Key Design Decisions

- `emit/1` is fire-and-forget — never blocks the caller
- Account-scoped topic for LiveView subscribers: `"notifications:account:<id>"`
- Global topic for Listener GenServer: `"notifications"` (local_broadcast to prevent duplicate delivery across cluster nodes)
- Subscription resolution deduplicates by `{destination, channel}`

```elixir
defmodule MyApp.Notifications do
  @moduledoc """
  Event bus and subscription management for business event notifications.

  Provides `emit/1` to broadcast events and subscription CRUD for
  managing who receives which events via which channels.
  """

  require Logger
  import Ecto.Query

  alias MyApp.Notifications.{Event, EventSubscription, NotificationLog}
  alias MyApp.Repo

  @topic_prefix "notifications:account:"
  @global_topic "notifications"

  # -- Event Bus --------------------------------------------------------------

  @spec subscribe(String.t()) :: :ok | {:error, term()}
  def subscribe(account_id) when is_binary(account_id) do
    Phoenix.PubSub.subscribe(MyApp.PubSub, topic(account_id))
  end

  @spec topic(String.t()) :: String.t()
  def topic(account_id) when is_binary(account_id) do
    @topic_prefix <> account_id
  end

  @spec emit(Event.t()) :: :ok
  def emit(%Event{} = event) do
    pubsub = MyApp.PubSub
    Phoenix.PubSub.broadcast(pubsub, topic(event.account_id), event)
    Phoenix.PubSub.local_broadcast(pubsub, @global_topic, event)
    :ok
  rescue
    error ->
      Logger.error("Failed to emit event #{event.type}: #{inspect(error)}")
      :ok
  end

  # -- Subscription Resolution ------------------------------------------------

  @spec resolve_subscriptions(String.t(), String.t(), keyword()) :: [EventSubscription.t()]
  def resolve_subscriptions(event_type, account_id, _opts \\ []) do
    from(s in EventSubscription,
      where: s.account_id == ^account_id,
      where: s.active == true,
      where: ^event_type in s.event_types,
      preload: [:user]
    )
    |> Repo.all()
    |> Enum.map(&resolve_destination/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(&{&1.destination, &1.channel})
  end

  @spec resolve_destination(EventSubscription.t()) :: EventSubscription.t() | nil
  defp resolve_destination(%EventSubscription{user_id: nil} = sub), do: sub

  defp resolve_destination(%EventSubscription{user: user, channel: channel} = sub) do
    resolved =
      case channel do
        "email" -> user.email
        "sms" -> Map.get(user, :phone)
        _ -> nil
      end

    if resolved, do: %{sub | destination: resolved}, else: nil
  end

  # -- Delivery Logging -------------------------------------------------------

  @spec log_delivery(map()) :: {:ok, NotificationLog.t()} | {:error, Ecto.Changeset.t()}
  def log_delivery(attrs) do
    %NotificationLog{}
    |> NotificationLog.changeset(attrs)
    |> Repo.insert()
  end

  @spec list_notification_logs(keyword()) :: [NotificationLog.t()]
  def list_notification_logs(opts \\ []) do
    account_id = Keyword.fetch!(opts, :account_id)
    page = max(Keyword.get(opts, :page, 1), 1)
    page_size = min(Keyword.get(opts, :page_size, 25), 100)

    from(l in NotificationLog,
      where: l.account_id == ^account_id,
      order_by: [desc: l.inserted_at],
      limit: ^page_size,
      offset: ^((page - 1) * page_size)
    )
    |> Repo.all()
  end

  # -- Subscription CRUD ------------------------------------------------------

  @spec list_subscriptions(keyword()) :: [EventSubscription.t()]
  def list_subscriptions(opts \\ []) do
    account_id = Keyword.fetch!(opts, :account_id)

    from(s in EventSubscription,
      where: s.account_id == ^account_id,
      order_by: [desc: s.inserted_at],
      preload: [:user]
    )
    |> Repo.all()
  end

  @spec get_subscription(String.t(), String.t()) ::
          {:ok, EventSubscription.t()} | {:error, :not_found}
  def get_subscription(id, account_id) do
    query =
      from(s in EventSubscription,
        where: s.id == ^id and s.account_id == ^account_id,
        preload: [:user]
      )

    case Repo.one(query) do
      nil -> {:error, :not_found}
      sub -> {:ok, sub}
    end
  end

  @spec create_subscription(map()) ::
          {:ok, EventSubscription.t()} | {:error, Ecto.Changeset.t()}
  def create_subscription(attrs) do
    %EventSubscription{}
    |> EventSubscription.changeset(attrs)
    |> Repo.insert()
  end

  @spec update_subscription(EventSubscription.t(), map()) ::
          {:ok, EventSubscription.t()} | {:error, Ecto.Changeset.t()}
  def update_subscription(%EventSubscription{} = subscription, attrs) do
    subscription
    |> EventSubscription.update_changeset(attrs)
    |> Repo.update()
  end

  @spec delete_subscription(EventSubscription.t()) ::
          {:ok, EventSubscription.t()} | {:error, Ecto.Changeset.t()}
  def delete_subscription(%EventSubscription{} = subscription) do
    Repo.delete(subscription)
  end

  @spec change_subscription(EventSubscription.t(), map()) :: Ecto.Changeset.t()
  def change_subscription(%EventSubscription{} = subscription, attrs \\ %{}) do
    EventSubscription.changeset(subscription, attrs)
  end
end
```

**IMPORTANT:** Replace `MyApp.PubSub` with the actual PubSub module name from the app's `application.ex`.

## Phase 7: Oban Delivery Workers

### 7.1 Add Oban Queues

In `config/config.exs`, add notification queues to the Oban config:

```elixir
config :my_app, Oban,
  # ... existing config ...
  queues: [
    # ... existing queues ...
    notifications_email: 10,
    notifications_sms: 5,
    notifications_webhook: 5
  ]
```

### 7.2 EmailWorker

`lib/<app>/notifications/workers/email_worker.ex`

```elixir
defmodule MyApp.Notifications.Workers.EmailWorker do
  @moduledoc """
  Oban worker for delivering email notifications.

  Unique on `event_id` + `destination` to prevent duplicate delivery
  within a 60-second window.
  """

  use Oban.Worker,
    queue: :notifications_email,
    max_attempts: 5,
    unique: [keys: [:event_id, :destination], period: 60]

  require Logger
  import Swoosh.Email

  alias MyApp.Notifications

  @email_regex ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/

  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok | {:cancel, String.t()} | {:error, term()}
  def perform(%Oban.Job{args: args}) do
    %{
      "event_type" => event_type,
      "event_data" => event_data,
      "destination" => destination,
      "account_id" => account_id,
      "subscription_id" => subscription_id
    } = args

    resource_type = args["resource_type"]
    resource_id = args["resource_id"]

    if Regex.match?(@email_regex, destination) do
      # CUSTOMIZE: Build your email content based on event_type
      email =
        new()
        |> to(destination)
        |> from(mail_from())
        |> subject("[#{event_type}] Notification")
        |> text_body("Event: #{event_type}\n\nData: #{inspect(event_data)}")

      case MyApp.Mailer.deliver(email) do
        {:ok, _} ->
          log_result(event_type, account_id, subscription_id, destination, "delivered",
            resource_type: resource_type,
            resource_id: resource_id
          )

          :ok

        {:error, reason} ->
          error_msg = inspect(reason) |> String.slice(0, 500)

          log_result(event_type, account_id, subscription_id, destination, "failed",
            error: error_msg,
            resource_type: resource_type,
            resource_id: resource_id
          )

          {:error, reason}
      end
    else
      log_result(event_type, account_id, subscription_id, destination, "failed",
        error: "invalid email",
        resource_type: resource_type,
        resource_id: resource_id
      )

      {:cancel, "Invalid email destination: #{destination}"}
    end
  end

  defp mail_from do
    # CUSTOMIZE: Configure your from address
    config = Application.fetch_env!(:my_app, :mailer_from)
    {Keyword.fetch!(config, :name), Keyword.fetch!(config, :email)}
  end

  @spec log_result(String.t(), String.t(), String.t() | nil, String.t(), String.t(), keyword()) ::
          {:ok, term()} | {:error, term()}
  defp log_result(event_type, account_id, subscription_id, destination, status, opts) do
    Notifications.log_delivery(%{
      event_type: event_type,
      account_id: account_id,
      subscription_id: subscription_id,
      destination: destination,
      channel: "email",
      status: status,
      error: Keyword.get(opts, :error),
      resource_type: Keyword.get(opts, :resource_type),
      resource_id: Keyword.get(opts, :resource_id)
    })
  end
end
```

### 7.3 WebhookWorker

`lib/<app>/notifications/workers/webhook_worker.ex`

```elixir
defmodule MyApp.Notifications.Workers.WebhookWorker do
  @moduledoc """
  Oban worker for delivering signed webhook notifications.
  """

  use Oban.Worker,
    queue: :notifications_webhook,
    max_attempts: 10,
    unique: [keys: [:event_id, :destination], period: 60]

  require Logger

  alias MyApp.Notifications
  alias MyApp.Notifications.{WebhookPayload, WebhookSigner}

  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok | {:error, term()}
  def perform(%Oban.Job{args: args}) do
    %{
      "event_id" => event_id,
      "event_type" => event_type,
      "event_data" => event_data,
      "account_id" => account_id,
      "destination" => destination,
      "subscription_id" => subscription_id,
      "secret" => secret
    } = args

    occurred_at = Map.get(args, "occurred_at", DateTime.utc_now() |> DateTime.to_iso8601())
    resource_type = args["resource_type"]
    resource_id = args["resource_id"]

    msg_id = "msg_" <> event_id
    timestamp = DateTime.utc_now() |> DateTime.to_unix() |> Integer.to_string()
    body = WebhookPayload.build(event_type, event_data, occurred_at)
    signature = WebhookSigner.sign(secret, msg_id, timestamp, body)

    headers = [
      {"content-type", "application/json"},
      {"webhook-id", msg_id},
      {"webhook-timestamp", timestamp},
      {"webhook-signature", signature}
    ]

    case webhook_client().post(destination, headers, body) do
      {:ok, status} when status in 200..299 ->
        log_result(event_type, account_id, subscription_id, destination, "delivered",
          resource_type: resource_type,
          resource_id: resource_id
        )

        :ok

      {:ok, status} ->
        log_result(event_type, account_id, subscription_id, destination, "failed",
          error: "http #{status}",
          resource_type: resource_type,
          resource_id: resource_id
        )

        {:error, {:http_status, status}}

      {:error, reason} ->
        log_result(event_type, account_id, subscription_id, destination, "failed",
          error: inspect(reason),
          resource_type: resource_type,
          resource_id: resource_id
        )

        {:error, reason}
    end
  end

  @spec webhook_client() :: module()
  defp webhook_client do
    Application.get_env(:my_app, :webhook_client, MyApp.Notifications.WebhookClient.HTTP)
  end

  @spec log_result(String.t(), String.t(), String.t() | nil, String.t(), String.t(), keyword()) ::
          {:ok, term()} | {:error, term()}
  defp log_result(event_type, account_id, subscription_id, destination, status, opts) do
    Notifications.log_delivery(%{
      event_type: event_type,
      account_id: account_id,
      subscription_id: subscription_id,
      destination: destination,
      channel: "webhook",
      status: status,
      error: Keyword.get(opts, :error),
      resource_type: Keyword.get(opts, :resource_type),
      resource_id: Keyword.get(opts, :resource_id)
    })
  end
end
```

### 7.4 SmsWorker (Optional)

Only create if the app needs SMS delivery. Similar structure to EmailWorker but uses the app's SMS provider.

`lib/<app>/notifications/workers/sms_worker.ex`

```elixir
defmodule MyApp.Notifications.Workers.SmsWorker do
  @moduledoc """
  Oban worker for delivering SMS notifications.
  """

  use Oban.Worker,
    queue: :notifications_sms,
    max_attempts: 5,
    unique: [keys: [:event_id, :destination], period: 60]

  require Logger

  alias MyApp.Notifications

  @phone_regex ~r/^\+[1-9]\d{1,14}$/

  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok | {:cancel, String.t()} | {:error, term()}
  def perform(%Oban.Job{args: args}) do
    %{
      "event_type" => event_type,
      "event_data" => _event_data,
      "destination" => destination,
      "account_id" => account_id,
      "subscription_id" => subscription_id
    } = args

    resource_type = args["resource_type"]
    resource_id = args["resource_id"]

    if Regex.match?(@phone_regex, destination) do
      # CUSTOMIZE: Build SMS text and send via your provider
      # text = build_message(event_type, event_data)
      # case YourSmsProvider.send(destination, text) do ...

      log_result(event_type, account_id, subscription_id, destination, "delivered",
        resource_type: resource_type,
        resource_id: resource_id
      )

      :ok
    else
      log_result(event_type, account_id, subscription_id, destination, "failed",
        error: "invalid phone",
        resource_type: resource_type,
        resource_id: resource_id
      )

      {:cancel, "Invalid phone destination: #{destination}"}
    end
  end

  @spec log_result(String.t(), String.t(), String.t() | nil, String.t(), String.t(), keyword()) ::
          {:ok, term()} | {:error, term()}
  defp log_result(event_type, account_id, subscription_id, destination, status, opts) do
    Notifications.log_delivery(%{
      event_type: event_type,
      account_id: account_id,
      subscription_id: subscription_id,
      destination: destination,
      channel: "sms",
      status: status,
      error: Keyword.get(opts, :error),
      resource_type: Keyword.get(opts, :resource_type),
      resource_id: Keyword.get(opts, :resource_id)
    })
  end
end
```

## Phase 8: Listener GenServer

Create `lib/<app>/notifications/listener.ex` — the orchestrator that bridges PubSub events to Oban delivery jobs.

### Key Design Decisions

- Subscribes to the global `"notifications"` topic (not account-scoped)
- Uses `local_broadcast` subscription to prevent duplicate delivery across cluster nodes
- Fire-and-forget — rescues all errors to avoid crashing the GenServer
- Not started in test environment (tests call `handle_info/2` directly)

```elixir
defmodule MyApp.Notifications.Listener do
  @moduledoc """
  GenServer that subscribes to the global notifications PubSub topic
  and orchestrates delivery by enqueuing Oban workers for each
  matching subscription.
  """

  use GenServer

  require Logger

  alias MyApp.Notifications
  alias MyApp.Notifications.Event

  alias MyApp.Notifications.Workers.{
    EmailWorker,
    # SmsWorker,
    WebhookWorker
  }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl GenServer
  @spec init(keyword()) :: {:ok, %{}}
  def init(_opts) do
    Phoenix.PubSub.subscribe(MyApp.PubSub, "notifications")
    {:ok, %{}}
  end

  @impl GenServer
  def handle_info(%Event{} = event, state) do
    subscriptions = resolve_matching_subscriptions(event)
    Enum.each(subscriptions, &enqueue_delivery(event, &1))
    {:noreply, state}
  rescue
    error ->
      Logger.error(
        "Listener failed to process event #{event.type}: #{inspect(error)}\n#{Exception.format_stacktrace(__STACKTRACE__)}"
      )

      {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @spec resolve_matching_subscriptions(Event.t()) :: [Notifications.EventSubscription.t()]
  defp resolve_matching_subscriptions(%Event{} = event) do
    event_type = Atom.to_string(event.type)
    Notifications.resolve_subscriptions(event_type, event.account_id)
  end

  @spec enqueue_delivery(Event.t(), Notifications.EventSubscription.t()) :: :ok
  defp enqueue_delivery(%Event{} = event, subscription) do
    {resource_type, resource_id} = resource_for_event(event)

    job_args = %{
      event_id: event.event_id,
      event_type: Atom.to_string(event.type),
      event_data: event.data,
      account_id: event.account_id,
      destination: subscription.destination,
      subscription_id: subscription.id,
      occurred_at: DateTime.to_iso8601(event.occurred_at),
      resource_type: resource_type,
      resource_id: resource_id,
      secret: subscription.secret
    }

    result =
      case subscription.channel do
        "email" -> EmailWorker.new(job_args) |> Oban.insert()
        # "sms" -> SmsWorker.new(job_args) |> Oban.insert()
        "webhook" -> WebhookWorker.new(job_args) |> Oban.insert()
        other -> {:error, "Unknown channel: #{other}"}
      end

    case result do
      {:ok, _job} -> :ok
      {:error, reason} ->
        Logger.error("Failed to enqueue #{subscription.channel} delivery",
          event_id: event.event_id,
          destination: subscription.destination,
          error: inspect(reason)
        )

        :ok
    end
  end

  # CUSTOMIZE: Map event types to resource type/id for log correlation
  @spec resource_for_event(Event.t()) :: {String.t() | nil, String.t() | nil}
  defp resource_for_event(%Event{type: _type, data: _data}) do
    # Example:
    # case type do
    #   :order_placed -> {"order", data[:order_id] || data["order_id"]}
    #   :user_invited -> {"user", data[:user_id] || data["user_id"]}
    #   _ -> {nil, nil}
    # end
    {nil, nil}
  end
end
```

**IMPORTANT:** Replace `MyApp.PubSub` with the actual PubSub module.

## Phase 9: Application Supervision Tree

Add the Listener to `application.ex`, conditionally skipping it in test:

```elixir
# In the children list, before the Endpoint:
# ... existing children ...
# LeadRouterWeb.Endpoint  # keep as last
```

Add the `maybe_start_listener/1` function:

```elixir
defp maybe_start_listener(children) do
  if Application.get_env(:my_app, :env) == :test do
    children
  else
    # Insert before the Endpoint (last element)
    List.insert_at(children, -2, MyApp.Notifications.Listener)
  end
end
```

And pipe the children list through it:

```elixir
children =
  [
    # ... existing children ...
  ]
  |> maybe_start_listener()
```

Also ensure `:env` is set in config:

```elixir
# config/config.exs
config :my_app, env: config_env()
```

## Phase 10: LiveView Integration

### Subscribe in mount

```elixir
def mount(_params, _session, socket) do
  if connected?(socket) do
    MyApp.Notifications.subscribe(socket.assigns.current_account.id)
  end

  {:ok, socket}
end
```

### Handle events

```elixir
def handle_info(%MyApp.Notifications.Event{type: type} = event, socket) do
  # React to specific event types
  case type do
    :resource_created ->
      # Reload data, show flash, etc.
      {:noreply, socket}

    _ ->
      {:noreply, socket}
  end
end
```

## Phase 11: Emitting Events

Throughout your business logic contexts, emit events after successful operations:

```elixir
alias MyApp.Notifications
alias MyApp.Notifications.Event

def create_order(attrs) do
  case Repo.insert(Order.changeset(%Order{}, attrs)) do
    {:ok, order} ->
      Notifications.emit(
        Event.new(:order_placed, order.account_id, %{
          order_id: order.id,
          total: order.total
        })
      )

      {:ok, order}

    error ->
      error
  end
end
```

## Phase 12: Verification

After completing all phases, verify the setup:

```bash
# Compile without warnings
mix compile --warnings-as-errors

# Run migrations
mix ecto.migrate

# Check code quality
mix format --check-formatted
mix credo --strict

# Run tests (if any were added)
mix test
```

## Architecture Summary

```
Business Logic
    │
    ▼
Notifications.emit(Event.new(...))
    │
    ├──▶ PubSub: "notifications:account:<id>"  ──▶  LiveView subscribers
    │
    └──▶ PubSub: "notifications" (local_broadcast)
              │
              ▼
         Listener GenServer
              │
              ├── resolve_subscriptions(event_type, account_id)
              │
              └── For each matching subscription:
                    ├── EmailWorker  ──▶  Swoosh  ──▶  Email provider
                    ├── SmsWorker    ──▶  SMS API ──▶  SMS provider
                    └── WebhookWorker ──▶ Signed HTTP POST
                                               │
                                               ▼
                                        NotificationLog (audit)
```

### Key Principles

1. **Fire-and-forget** — Event emission never blocks business operations
2. **Multi-tenant isolation** — Account-scoped topics and queries
3. **Idempotent delivery** — Oban unique constraints prevent duplicates within 60s
4. **Cluster-safe** — `local_broadcast` for Listener prevents duplicate processing
5. **Testable** — Listener not started in test; call `handle_info/2` directly
6. **Extensible** — Add new event types, channels, or workers without changing core architecture
