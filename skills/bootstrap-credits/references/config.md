# Configuration Reference

## config/config.exs

Add credit configuration (customize operation names and costs for the target app):

```elixir
config :my_app, MyApp.Credits,
  costs: %{
    # Map operation atoms to their credit cost
    verify_email: 2,
    verify_phone: 2,
    api_call: 1
  },
  add_ons: %{
    # Optional add-ons that increase cost
    # enrichment: 15
  },
  packs: %{
    "starter_500" => %{amount_cents: 500, credits: 500},
    "pro_2000" => %{amount_cents: 2_000, credits: 2_000},
    "scale_10000" => %{amount_cents: 10_000, credits: 10_000}
  },
  default_balance: 25,
  enforce_credits: true
```

## config/runtime.exs

Add Stripe configuration (secrets from environment):

```elixir
if config_env() == :prod or System.get_env("STRIPE_SECRET_KEY") do
  config :stripity_stripe, api_key: System.get_env("STRIPE_SECRET_KEY")

  config :my_app, MyApp.Billing,
    publishable_key: System.get_env("STRIPE_PUBLISHABLE_KEY"),
    webhook_secret: System.get_env("STRIPE_WEBHOOK_SECRET")
end
```

## .env.sample

Add these entries:

```
STRIPE_SECRET_KEY=sk_test_...
STRIPE_PUBLISHABLE_KEY=pk_test_...
STRIPE_WEBHOOK_SECRET=whsec_...
```

## Required Dependencies

In `mix.exs`:

```elixir
{:stripity_stripe, "~> 3.2"}
```

Oban should already be configured. If not, add:
```elixir
{:oban, "~> 2.18"}
```

And in `config/config.exs`:
```elixir
config :my_app, Oban,
  repo: MyApp.Repo,
  queues: [default: 10]
```
