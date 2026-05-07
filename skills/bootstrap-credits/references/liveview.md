# LiveView Pages Reference

**Adapt**: Replace `MyApp`/`MyAppWeb` with actual module names. Adjust route paths and breadcrumbs to match the app's navigation structure.

## CreditLive.Purchase — Pack Selection + Stripe Checkout

```elixir
defmodule MyAppWeb.CreditLive.Purchase do
  @moduledoc """
  LiveView for purchasing account credits via Stripe.
  """
  use MyAppWeb, :live_view

  alias MyApp.Billing
  alias MyApp.Billing.Payments

  @impl true
  def mount(_params, _session, socket) do
    # Adapt: get the billing entity (account/user) from socket assigns
    account = socket.assigns.current_account

    {:ok,
     assign(socket,
       page_title: "Buy Credits",
       packs: Billing.credit_packs(),
       selected_pack: nil,
       client_secret: nil,
       stripe_publishable_key: stripe_publishable_key(),
       return_url: stripe_return_url(account.id)
     )}
  end

  @impl true
  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  @impl true
  def handle_event("select_pack", %{"pack_key" => pack_key}, socket) do
    account = socket.assigns.current_account

    with {:ok, pack} <- Billing.get_pack(pack_key),
         {:ok, publishable_key} <- validate_publishable_key(socket.assigns.stripe_publishable_key),
         {:ok, payment_intent} <- Payments.create_payment_intent(account, pack_key),
         {:ok, client_secret} <- extract_client_secret(payment_intent) do
      socket =
        socket
        |> assign(
          selected_pack: pack,
          client_secret: client_secret,
          stripe_publishable_key: publishable_key
        )
        |> put_flash(:info, "Pack selected. Enter payment details below.")
        |> push_event("stripe:client_secret", %{client_secret: client_secret})

      {:noreply, socket}
    else
      {:error, :unknown_pack} ->
        {:noreply, put_flash(socket, :error, "Selected pack is invalid.")}

      {:error, :missing_publishable_key} ->
        {:noreply, put_flash(socket, :error, "Stripe is not configured. Contact support.")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Unable to initialize payment. Please try again.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-8">
      <%!-- Header --%>
      <div>
        <h1 class="text-2xl font-bold tracking-tight text-base-content">Buy Credits</h1>
        <p class="mt-1 text-sm text-base-content/45">
          Select a credit pack and complete checkout securely with Stripe.
        </p>
      </div>

      <%!-- Pack cards --%>
      <div class="grid grid-cols-1 gap-5 md:grid-cols-3">
        <.pack_card
          :for={{pack, idx} <- Enum.with_index(@packs)}
          pack={pack}
          index={idx}
          total={length(@packs)}
          selected={@selected_pack != nil and @selected_pack.key == pack.key}
        />
      </div>

      <%!-- Payment section --%>
      <div :if={@selected_pack}>
        <div class="rounded-xl border border-base-300/50 bg-base-100 overflow-hidden">
          <%!-- Order summary bar --%>
          <div class="flex items-center justify-between gap-4 px-6 py-4 bg-base-200/30 border-b border-base-300/30">
            <div class="flex items-center gap-3">
              <div class="size-9 rounded-lg bg-primary/10 flex items-center justify-center">
                <.icon name="hero-credit-card-mini" class="size-4 text-primary" />
              </div>
              <div>
                <h2 class="text-sm font-semibold text-base-content">Payment Details</h2>
                <p class="text-[0.7rem] text-base-content/40 mt-0.5">
                  Secure checkout powered by Stripe
                </p>
              </div>
            </div>
            <div class="text-right">
              <span class="text-lg font-bold text-base-content tabular-nums">
                {format_usd(@selected_pack.amount_cents)}
              </span>
              <p class="text-[0.7rem] text-base-content/40">
                {format_credits(@selected_pack.credits)} credits
              </p>
            </div>
          </div>

          <%!-- Stripe form --%>
          <div class="p-6">
            <div
              id="stripe-payment"
              phx-hook="StripePaymentElement"
              data-publishable-key={@stripe_publishable_key || ""}
              data-return-url={@return_url}
            >
              <div data-role="payment-element" class="rounded-lg border border-base-300/40 p-4" />
              <div class="flex items-center justify-between mt-5">
                <div class="flex items-center gap-1.5 text-[0.65rem] text-base-content/30">
                  <.icon name="hero-lock-closed-mini" class="size-3" />
                  <span>Encrypted & secure</span>
                </div>
                <button
                  type="button"
                  data-role="confirm-payment"
                  class="btn btn-primary px-8"
                >
                  Pay {format_usd(@selected_pack.amount_cents)}
                </button>
              </div>
              <p data-role="payment-error" class="mt-3 text-sm text-error" />
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # ============================================
  # Components
  # ============================================

  attr :pack, :map, required: true
  attr :index, :integer, required: true
  attr :total, :integer, required: true
  attr :selected, :boolean, required: true

  defp pack_card(assigns) do
    recommended = assigns.index == div(assigns.total, 2) and assigns.total >= 3
    assigns = assign(assigns, :recommended, recommended)

    ~H"""
    <div class="relative">
      <div :if={@recommended} class="absolute -top-3 left-1/2 -translate-x-1/2 z-10">
        <span class="px-3 py-0.5 text-[0.6rem] font-bold uppercase tracking-[0.12em] rounded-full bg-primary text-primary-content shadow-sm">
          Popular
        </span>
      </div>

      <button
        type="button"
        phx-click="select_pack"
        phx-value-pack_key={@pack.key}
        class={[
          "group relative w-full h-full text-left rounded-xl border transition-all duration-200 cursor-pointer",
          if(@recommended, do: "p-7", else: "p-6"),
          if(@selected,
            do: "border-primary ring-2 ring-primary/20 bg-base-100 shadow-lg",
            else: "border-base-300/50 bg-base-100 hover:border-primary/30 hover:shadow-lg hover:-translate-y-0.5"
          )
        ]}
      >
        <%!-- Selection radio --%>
        <div class={[
          "absolute top-4 right-4 size-5 rounded-full border-2 flex items-center justify-center transition-all duration-150",
          if(@selected,
            do: "border-primary bg-primary scale-110",
            else: "border-base-300/50 group-hover:border-base-content/25"
          )
        ]}>
          <.icon :if={@selected} name="hero-check-mini" class="size-3 text-primary-content" />
        </div>

        <%!-- Tier icon --%>
        <div class={[
          "size-10 rounded-lg flex items-center justify-center mb-4 transition-colors",
          if(@selected,
            do: "bg-primary/12 text-primary",
            else: "bg-base-200/80 text-base-content/25 group-hover:text-base-content/40"
          )
        ]}>
          <.icon name={tier_icon(@index)} class="size-5" />
        </div>

        <%!-- Pack name --%>
        <p class="text-[0.65rem] font-bold uppercase tracking-[0.14em] text-base-content/40 mb-3">
          {humanize_pack_key(@pack.key)}
        </p>

        <%!-- Price --%>
        <p class="text-3xl font-bold tracking-tight text-base-content tabular-nums">
          {format_usd(@pack.amount_cents)}
        </p>

        <%!-- Credits --%>
        <p class="mt-1 text-sm font-medium text-base-content/50">
          {format_credits(@pack.credits)} credits
        </p>

        <%!-- Unit price --%>
        <div class="mt-5 pt-4 border-t border-base-300/30 flex items-center justify-between">
          <span class="text-[0.65rem] text-base-content/35">Per credit</span>
          <span class="text-[0.65rem] font-semibold tabular-nums text-base-content/50">
            {format_unit_price(@pack)}
          </span>
        </div>
      </button>
    </div>
    """
  end

  # ============================================
  # Private helpers
  # ============================================

  defp tier_icon(0), do: "hero-bolt-solid"
  defp tier_icon(1), do: "hero-fire-solid"
  defp tier_icon(_), do: "hero-rocket-launch-solid"

  defp format_unit_price(%{amount_cents: cents, credits: credits}) when credits > 0 do
    dollars = cents / credits / 100
    "$#{:erlang.float_to_binary(dollars, decimals: 2)}"
  end

  defp format_unit_price(_), do: "—"

  defp format_credits(n) when is_integer(n) and n >= 1000 do
    n
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end

  defp format_credits(n) when is_integer(n), do: Integer.to_string(n)

  defp extract_client_secret(%Stripe.PaymentIntent{client_secret: client_secret})
       when is_binary(client_secret) and client_secret != "" do
    {:ok, client_secret}
  end

  defp extract_client_secret(_payment_intent), do: {:error, :missing_client_secret}

  defp validate_publishable_key(key) when is_binary(key) and key != "", do: {:ok, key}
  defp validate_publishable_key(_key), do: {:error, :missing_publishable_key}

  defp stripe_publishable_key do
    :my_app
    |> Application.get_env(MyApp.Billing, [])
    |> Keyword.get(:publishable_key)
  end

  defp stripe_return_url(account_id) do
    # Adapt: use the actual endpoint module and credit page path
    "#{MyAppWeb.Endpoint.url()}/dashboard/credits?purchase=success"
  end

  defp humanize_pack_key(pack_key) do
    pack_key
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp format_usd(amount_cents) do
    dollars = amount_cents / 100
    :erlang.float_to_binary(dollars, decimals: 2) |> then(&"$#{&1}")
  end
end
```

## CreditLive.Index — Balance, Transactions, Usage

This is a larger LiveView with tabbed navigation. Create it following the same patterns as the Purchase page but with:

- **Stats cards** showing: current balance, credits used this month, total operations
- **Tab bar** toggling between Transactions and Usage views
- **Transactions table** columns: Date, Type (badge), Amount (+/-), Balance After, Description
- **Usage events table** columns: Date, Operation, Cost, Cache (hit/miss badge), API Key name
- **Pagination** with server-side page/per_page params
- **Success flash** when redirected from purchase with `?purchase=success`

Key implementation details:
- Use `handle_params` to read `tab` and `page` query params
- Load data in `load_tab_data/4` based on active tab
- Clamp page to valid range
- Format numbers with comma separators
- Color-code transaction amounts (green positive, red negative)
- Transaction type badges: addition (green), deduction (red), adjustment (yellow)

## Router Entries

```elixir
# Inside the authenticated live_session scope:
live "/dashboard/credits", CreditLive.Index, :index
live "/dashboard/credits/purchase", CreditLive.Purchase, :purchase
```

**Adapt**: Adjust paths to match app's routing conventions. If multi-tenant with account scoping:
```elixir
live "/dashboard/accounts/:account_id/credits", CreditLive.Index, :index
live "/dashboard/accounts/:account_id/credits/purchase", CreditLive.Purchase, :purchase
```
