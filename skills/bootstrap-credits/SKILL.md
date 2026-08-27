---
name: bootstrap-credits
description: >
  Bootstrap a credit system with Stripe integration in a Phoenix 1.8 app. Generates migrations,
  schemas, context module, billing modules, Stripe webhook controller, PgFlow job, LiveView
  purchase and history pages, and JS hook. Checks what already exists and only adds missing pieces.
  Use when the user says "bootstrap credits", "add credit system", "add billing", "stripe credits",
  "credit purchase", or wants to add a prepaid credit system with Stripe to a Phoenix app.
---

# Bootstrap Credits with Stripe

Add a complete prepaid credit system with Stripe payment integration to a Phoenix 1.8 app.

## What Gets Created

1. **Credit Balances** — Per-account balance with optimistic locking
2. **Credit Transactions** — Immutable append-only ledger (deductions, additions, adjustments)
3. **Usage Events** — Per-operation tracking with cost, cache status, metadata
4. **Billing** — Credit pack configuration, Stripe PaymentIntent creation, customer lifecycle
5. **Stripe Webhook** — Signature verification, event routing, idempotent credit fulfillment
6. **PgFlow Job** — Async credit fulfillment with deduplication
7. **LiveView Pages** — Purchase page with Stripe Payment Element, balance/history page
8. **JS Hook** — Stripe.js lazy-loading and Payment Element mounting

## Prerequisites

Verify before starting:
1. Phoenix 1.8 app with `phx.gen.auth` completed
2. Multi-tenant account model exists (accounts table with users)
3. DaisyUI installed for UI components
4. PgFlow configured for background jobs (see bootstrap-phoenix / `/pgflow bootstrap`)
5. Nebulex or similar cache configured (optional — skip caching if absent)

## App Name Detection

Detect the app module name from `mix.exs` (e.g., `MyApp`) and the OTP app name (e.g., `my_app`). Replace all template references accordingly. Also detect:
- The **accounts schema** module and table name
- The **repo** module
- The **endpoint** module
- The **web** module prefix
- Whether a **cache** module exists

## Phase 0: Discovery — Check What Already Exists

**CRITICAL: Before generating anything, audit the target app.**

### Discovery Checklist

1. **Dependencies** — Check `mix.exs` for `stripity_stripe` and `pgflow`
   - If `stripity_stripe` missing: add to deps and tell user to run `mix deps.get`
   - If `pgflow` missing: add `{:pgflow, github: "agoodway/pgflow", branch: "main"}` and warn the user to run `/pgflow bootstrap` (or follow bootstrap-phoenix Phase 7) before continuing

2. **Migrations** — Search `priv/repo/migrations/` for credit-related tables
   - `Glob("priv/repo/migrations/*credit*")` and `Grep("credit_balances|credit_transactions|usage_events", path: "priv/repo/migrations/")`

3. **Schemas** — Search for existing credit schemas
   - `Grep("schema \"credit_balances\"")`, `Grep("schema \"credit_transactions\"")`, `Grep("schema \"usage_events\"")`

4. **Context** — Search for existing credit context
   - `Grep("def deduct\\|def add\\|def get_balance\\|def compute_cost")`

5. **Billing modules** — Search for Stripe integration
   - `Grep("PaymentIntent\\|StripeCustomer\\|CreditPurchaseWorker")`

6. **Webhook controller** — Search for existing Stripe webhook
   - `Grep("stripe_webhook\\|StripeWebhook")`

7. **LiveViews** — Search for existing credit LiveViews
   - `Glob("lib/**/credit_live/**")` or `Grep("CreditLive")`

8. **JS Hook** — Search for Stripe payment hook
   - `Grep("StripePaymentElement", path: "assets/")`

9. **Accounts schema** — Check if `stripe_customer_id` field exists
   - `Grep("stripe_customer_id", path: "lib/")`

10. **Cache module** — Check for Nebulex or similar
    - `Grep("Nebulex\\|use Nebulex")` or `Grep("defmodule.*Cache")`

### Discovery Report

Present findings and ask for confirmation before proceeding.

## Phase 1: Gather Configuration

Ask the user:

1. **Account association** — What schema do credits belong to?
   Default: `accounts` (the multi-tenant parent)

2. **Credit packs** — What packs to offer?
   Default: Starter (500 credits / $5), Pro (2000 / $20), Scale (10000 / $100)

3. **Operation costs** — What operations consume credits and how much?
   Example: `%{verify_email: 2, verify_phone: 2, api_call: 1}`
   The user must define at least one operation.

4. **Default balance** — Free credits for new accounts?
   Default: 25

5. **Route paths** — Where to mount the credit pages?
   Default: `/dashboard/credits` (purchase at `/dashboard/credits/purchase`)

6. **Usage events** — Track per-operation usage with API key association?
   Default: yes if API keys exist, no otherwise

## Phase 2: Implementation

Execute in dependency order, skipping existing components.

### Step 1: Dependencies

Add to `mix.exs` if missing:
```elixir
{:stripity_stripe, "~> 3.2"}
```

### Step 2: Environment Configuration

Read [references/config.md](references/config.md)

Add config entries for credits and Stripe.

### Step 3: Data Layer

Read [references/database.md](references/database.md)

Create migrations and schemas for:
- `credit_balances` — per-account balance with optimistic locking
- `credit_transactions` — immutable transaction log
- `usage_events` — per-operation usage tracking (if enabled)
- `stripe_customer_id` field on accounts table
- Idempotency index on credit_transactions for payment deduplication

### Step 4: Credit Context

Read [references/credits-context.md](references/credits-context.md)

Create the credits context module with:
- `compute_cost/2` — config-driven cost registry with add-on support
- `get_balance/1` — cached balance lookup
- `has_sufficient_credits?/2` — balance check
- `deduct/3` — atomic deduction with optimistic lock retry
- `add/3` — atomic addition with FOR UPDATE lock
- `create_balance/2` — initialize balance for new accounts
- `get_usage/2` — aggregated usage stats for date range
- `list_transactions/2` — paginated transaction history
- `list_usage_events/2` — paginated usage events
- `record_usage_event/1` — standalone event recording

### Step 5: Billing Modules

Read [references/billing.md](references/billing.md)

Create:
- `Billing` — credit pack configuration helpers
- `Billing.Payments` — Stripe PaymentIntent creation
- `Billing.StripeCustomers` — lazy Stripe customer creation and persistence
- `Billing.CreditPurchaseWorker` — PgFlow job for idempotent credit fulfillment
- Register the job in `:my_app, PgFlow` `jobs:` and compile with `mix pgflow.gen.job_migration MyApp.Billing.CreditPurchaseWorker`

### Step 6: Stripe Webhook

Read [references/webhook.md](references/webhook.md)

Create:
- `StripeWebhookBodyReader` plug — preserves raw body for signature verification
- `StripeWebhookController` — verifies signature, routes events, enqueues jobs
- Router entries: webhook pipeline + route

### Step 7: LiveView Pages

Read [references/liveview.md](references/liveview.md)

Create:
- `CreditLive.Purchase` — pack selection + Stripe Payment Element checkout
- `CreditLive.Index` — balance display, transaction history, usage events with tabs/pagination
- Router entries for both pages

### Step 8: JavaScript Hook

Read [references/js-hook.md](references/js-hook.md)

Add `StripePaymentElement` hook to `assets/js/app.js`:
- Lazy-loads Stripe.js from CDN
- Mounts Payment Element on `stripe:client_secret` event
- Handles payment confirmation with return URL
- Cleanup on destroy

### Step 9: Integration

1. Hook into account creation to auto-create credit balance (call `Credits.create_balance/1`)
2. Add credit balance to dashboard assigns if a dashboard layout exists
3. Run `mix ecto.migrate`
4. Run `mix test` to verify

## Key Design Patterns

### Optimistic Locking
CreditBalance uses `lock_version` to prevent concurrent deduction races. Deductions retry once on `StaleEntryError`.

### Atomic Operations
`Ecto.Multi` ensures balance update + transaction log + usage event all succeed or all fail.

### Idempotent Payments
A unique partial index on `credit_transactions` prevents double-crediting if the Stripe webhook fires multiple times:
```sql
CREATE UNIQUE INDEX ON credit_transactions (account_id, (metadata->>'stripe_payment_intent_id'))
WHERE type = 'addition' AND metadata ? 'stripe_payment_intent_id'
```

### Lazy Stripe Customer
Stripe customer IDs are created on-demand during the first payment and persisted on the account.

### Raw Body Preservation
Stripe webhook signature verification requires the raw request body. A custom `BodyReader` plug stores it on `conn.assigns` before JSON parsing.

### Cache Invalidation
Credit balances are cached (30s TTL) for read performance and invalidated after every deduction/addition.

## Security Considerations

- Stripe webhook secret verified on every request
- Raw body preserved for signature verification (not re-serialized JSON)
- Payment metadata validated before job enqueue
- Credit operations use database-level locking (not application-level)
- Idempotency index prevents financial double-crediting
- Stripe publishable key validated before showing payment form
