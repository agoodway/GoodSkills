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

PgFlow should already be configured (bootstrap-phoenix Phase 7 / `/pgflow bootstrap`). If not, add:
```elixir
{:pgflow, github: "agoodway/pgflow", branch: "main"}
```

And follow the Goodviews wiring:

```elixir
# config/config.exs — enqueue without a running supervisor (tests)
config :pgflow, repo: MyApp.Repo

# config/runtime.exs — omit in test so workers do not start
if config_env() != :test do
  config :my_app, PgFlow,
    repo: MyApp.Repo,
    jobs: [MyApp.Billing.CreditPurchaseWorker],
    flows: [],
    max_concurrency: 10,
    signal_strategy: :notify
end
```

If PgFlow is already configured, append `MyApp.Billing.CreditPurchaseWorker` to the existing `jobs:` list. Then compile the job:

```bash
mix pgflow.gen.job_migration MyApp.Billing.CreditPurchaseWorker
mix ecto.migrate
```

Rename the generated migration module to `MyApp.Repo.Migrations.*` if it emits `PgFlow.Repo.Migrations.*`.
