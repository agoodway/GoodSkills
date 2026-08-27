# Stripe Webhook Reference

**Adapt**: Replace `MyApp`/`MyAppWeb` with actual module names.

## StripeWebhookBodyReader — Raw Body Preservation

Stripe webhook signature verification requires the raw (unparsed) request body. This plug stores it on `conn.assigns[:raw_body]` before JSON parsing occurs.

```elixir
defmodule MyAppWeb.Plugs.StripeWebhookBodyReader do
  @moduledoc false

  alias Plug.Conn

  @spec read_body(Conn.t(), keyword()) :: {:ok, binary(), Conn.t()}
  def read_body(conn, opts) do
    case Conn.read_body(conn, opts) do
      {:ok, body, conn} ->
        {:ok, body, Conn.assign(conn, :raw_body, body)}

      {:more, chunk, conn} ->
        read_remaining_body(conn, opts, chunk)
    end
  end

  defp read_remaining_body(conn, opts, acc) do
    case Conn.read_body(conn, opts) do
      {:ok, body, conn} ->
        full_body = acc <> body
        {:ok, full_body, Conn.assign(conn, :raw_body, full_body)}

      {:more, chunk, conn} ->
        read_remaining_body(conn, opts, acc <> chunk)
    end
  end
end
```

### Endpoint Configuration

In `endpoint.ex`, configure the body reader for the webhook path. This must come **before** the standard `Plug.Parsers`:

```elixir
plug Plug.Parsers,
  parsers: [:urlencoded, :multipart, :json],
  pass: ["*/*"],
  body_reader: {MyAppWeb.Plugs.StripeWebhookBodyReader, :read_body, []},
  json_decoder: Phoenix.json_library()
```

**Note**: This applies the body reader globally, but it only adds a `raw_body` assign — it doesn't change parsing behavior. If you want to scope it to only the webhook path, use a custom plug that checks the path before delegating.

## StripeWebhookController

```elixir
defmodule MyAppWeb.StripeWebhookController do
  @moduledoc """
  Handles Stripe webhook events for credit purchasing.
  """
  use MyAppWeb, :controller
  require Logger

  alias MyApp.Billing.CreditPurchaseWorker

  @doc """
  Verifies Stripe webhook signatures and enqueues credit jobs for successful payments.
  """
  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create(conn, _params) do
    signature = get_req_header(conn, "stripe-signature") |> List.first()
    raw_body = conn.assigns[:raw_body] || ""
    webhook_secret = webhook_secret()

    with {:ok, signature} <- validate_signature_header(signature),
         {:ok, secret} <- validate_webhook_secret(webhook_secret),
         {:ok, event} <- Stripe.Webhook.construct_event(raw_body, signature, secret),
         :ok <- maybe_enqueue_credit_job(event) do
      send_resp(conn, :ok, "ok")
    else
      {:error, :missing_signature} ->
        send_resp(conn, :bad_request, "missing signature")

      {:error, :missing_webhook_secret} ->
        send_resp(conn, :internal_server_error, "webhook secret not configured")

      {:error, {:invalid_metadata, payment_intent_id, metadata}} ->
        Logger.warning("stripe_webhook_invalid_metadata",
          payment_intent_id: payment_intent_id,
          metadata: metadata
        )

        send_resp(conn, :unprocessable_entity, "invalid payment metadata")

      {:error, {:enqueue_failed, payment_intent_id, reason}} ->
        Logger.error("stripe_webhook_enqueue_failed",
          payment_intent_id: payment_intent_id,
          reason: inspect(reason)
        )

        send_resp(conn, :internal_server_error, "failed to enqueue credit job")

      {:error, _reason} ->
        send_resp(conn, :bad_request, "invalid signature")
    end
  end

  defp maybe_enqueue_credit_job(%Stripe.Event{
         type: "payment_intent.succeeded",
         data: %{object: %Stripe.PaymentIntent{} = payment_intent}
       }) do
    with {:ok, args} <- build_job_args(payment_intent),
         {:ok, _run_id} <- enqueue_credit_job(args) do
      :ok
    else
      {:error, {:invalid_metadata, _payment_intent_id, _metadata}} = error ->
        error

      {:error, reason} ->
        {:error, {:enqueue_failed, payment_intent.id, reason}}
    end
  end

  defp maybe_enqueue_credit_job(_event), do: :ok

  defp build_job_args(%Stripe.PaymentIntent{id: payment_intent_id, metadata: metadata})
       when is_map(metadata) do
    account_id = metadata["account_id"]
    pack_key = metadata["pack_key"]

    if valid_metadata_value?(payment_intent_id) and valid_metadata_value?(account_id) and
         valid_metadata_value?(pack_key) do
      {:ok,
       %{
         "payment_intent_id" => payment_intent_id,
         "account_id" => account_id,
         "pack_key" => pack_key
       }}
    else
      {:error, {:invalid_metadata, payment_intent_id, metadata}}
    end
  end

  defp build_job_args(%Stripe.PaymentIntent{id: payment_intent_id, metadata: metadata}),
    do: {:error, {:invalid_metadata, payment_intent_id, metadata}}

  defp enqueue_credit_job(args) do
    PgFlow.enqueue(CreditPurchaseWorker, args)
  rescue
    error -> {:error, error}
  end

  defp valid_metadata_value?(value), do: is_binary(value) and value != ""

  defp validate_signature_header(signature) when is_binary(signature) and signature != "",
    do: {:ok, signature}

  defp validate_signature_header(_signature), do: {:error, :missing_signature}

  defp validate_webhook_secret(secret) when is_binary(secret) and secret != "", do: {:ok, secret}
  defp validate_webhook_secret(_secret), do: {:error, :missing_webhook_secret}

  defp webhook_secret do
    :my_app
    |> Application.get_env(MyApp.Billing, [])
    |> Keyword.get(:webhook_secret)
  end
end
```

## Router Entries

Add to `router.ex`:

```elixir
# Stripe webhook pipeline — JSON only, no CSRF
pipeline :stripe_webhook do
  plug :accepts, ["json"]
end

# Webhook route — outside any auth scope
scope "/webhooks", MyAppWeb do
  pipe_through :stripe_webhook

  post "/stripe", StripeWebhookController, :create
end
```

**Important**: The webhook route must be outside any authentication scope since Stripe sends unauthenticated POST requests.
