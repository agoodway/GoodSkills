---
name: bootstrap-postmark
description: >
  Bootstrap Postmark as the production Swoosh mailer adapter in a Phoenix 1.8 app. Configures
  prod.exs for Swoosh API client, runtime.exs for Postmark adapter and from address, updates
  .env.sample, and verifies the Mailer module exists. Use when the user says "bootstrap postmark",
  "add postmark", "setup postmark mailer", "configure swoosh for production", or wants to add
  Postmark email delivery to a Phoenix app.
---

# Bootstrap Postmark Mailer

Configure Postmark as the production email adapter for Swoosh in a Phoenix 1.8 app.

## What Gets Configured

1. **prod.exs** — Swoosh API client set to `Swoosh.ApiClient.Req`, local storage disabled
2. **runtime.exs** — Postmark adapter with `POSTMARK_API_KEY` env var, configurable from address with `MAILER_FROM_NAME` and `MAILER_FROM_EMAIL`
3. **config.exs** — Default `Swoosh.Adapters.Local` for dev, default `:mailer_from` tuple
4. **test.exs** — `Swoosh.Adapters.Test` adapter, API client disabled
5. **.env.sample** — `POSTMARK_API_KEY`, `MAILER_FROM_EMAIL`, `MAILER_FROM_NAME` entries
6. **Mailer module** — Verified or created

## App Name Detection

Detect from `mix.exs`:
- **App module prefix** (e.g., `MyApp`) — the module namespace
- **OTP app name** (e.g., `:my_app`) — used in config atoms
- **Web module prefix** (e.g., `MyAppWeb`) — for endpoint references

Also detect:
- **Mailer module** — Look for `use Swoosh.Mailer` in `lib/`
- **Existing Swoosh config** — Check all config files for existing adapter settings

## Phase 0: Discovery

**CRITICAL: Audit the target app before making any changes.**

### Discovery Checklist

1. **Swoosh dependency** — Check `mix.exs` for `{:swoosh, ...}`
   - If missing: add `{:swoosh, "~> 1.16"}` to deps and tell user to run `mix deps.get`

2. **Req dependency** — Check `mix.exs` for `{:req, ...}`
   - Swoosh.ApiClient.Req requires Req. If missing: add `{:req, "~> 0.5"}` to deps
   - If the app uses `Swoosh.ApiClient.Finch` or `Swoosh.ApiClient.Hackney` instead, prefer Req but note the existing choice

3. **Mailer module** — Search for `use Swoosh.Mailer` in `lib/`
   - If found: note the module name and otp_app
   - If missing: will create one

4. **Existing config** — Check each config file:
   - `config/config.exs` — look for existing mailer adapter config
   - `config/dev.exs` — look for swoosh settings
   - `config/test.exs` — look for swoosh settings
   - `config/prod.exs` — look for swoosh settings
   - `config/runtime.exs` — look for mailer config in `if config_env() == :prod` block

5. **Existing .env.sample** — Check for `POSTMARK_API_KEY` or `MAILER_FROM` entries

6. **Existing from address config** — Search for `:mailer_from` in config files

### Discovery Report

Present findings to user. If Swoosh is already fully configured for Postmark, confirm and skip. Otherwise show what will be added/changed.

## Phase 1: Implementation

Execute in order, skipping anything that already exists.

### Step 1: Dependencies

Ensure `mix.exs` has:
```elixir
{:swoosh, "~> 1.16"}
{:req, "~> 0.5"}
```

### Step 2: Mailer Module

If no mailer module exists, create `lib/<app>/mailer.ex`:
```elixir
defmodule <AppModule>.Mailer do
  @moduledoc """
  Email delivery for the application using Swoosh.
  """
  use Swoosh.Mailer, otp_app: :<otp_app>
end
```

### Step 3: Base Config (config/config.exs)

Add if not present — sets Local adapter for dev and a default from address:
```elixir
# Mailer — uses Local adapter by default (see runtime.exs for production)
config :<otp_app>, <AppModule>.Mailer, adapter: Swoosh.Adapters.Local
config :<otp_app>, :mailer_from, {"<AppName>", "contact@example.com"}
```

### Step 4: Dev Config (config/dev.exs)

Add if not present:
```elixir
# Disable swoosh api client as it is only required for production adapters.
config :swoosh, :api_client, false
```

### Step 5: Test Config (config/test.exs)

Add if not present:
```elixir
config :<otp_app>, <AppModule>.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false
```

### Step 6: Prod Config (config/prod.exs)

Add if not present:
```elixir
# Configure Swoosh API Client
config :swoosh, api_client: Swoosh.ApiClient.Req

# Disable Swoosh Local Memory Storage
config :swoosh, local: false
```

### Step 7: Runtime Config (config/runtime.exs)

Inside the `if config_env() == :prod do` block, add:
```elixir
  # Postmark mailer adapter
  config :<otp_app>, <AppModule>.Mailer,
    adapter: Swoosh.Adapters.Postmark,
    api_key:
      System.get_env("POSTMARK_API_KEY") ||
        raise("environment variable POSTMARK_API_KEY is missing.")

  # Mailer from address
  config :<otp_app>,
         :mailer_from,
         {System.get_env("MAILER_FROM_NAME", "<AppName>"),
          System.get_env("MAILER_FROM_EMAIL") ||
            raise("environment variable MAILER_FROM_EMAIL is missing.")}
```

**Important:** Place this inside the existing `if config_env() == :prod do` block — do not create a duplicate conditional.

### Step 8: Environment File (.env.sample)

Add these entries if not already present:
```
# Postmark mailer adapter
POSTMARK_API_KEY=

# Required in production (sender email for system mail)
MAILER_FROM_EMAIL=noreply@example.com

# Optional (defaults to <AppName>)
MAILER_FROM_NAME=<AppName>
```

### Step 9: Dev Mailbox Route (Optional)

If the router doesn't already have the Swoosh dev mailbox route, suggest adding to `router.ex` inside a dev-only scope:
```elixir
if Mix.env() == :dev do
  scope "/dev" do
    pipe_through :browser
    forward "/mailbox", Plug.Swoosh.MailboxPreview
  end
end
```

Only suggest this — don't add it automatically since it touches routing.

## Phase 2: Verification

1. Run `mix compile --warnings-as-errors` to verify config compiles
2. Check that `mix test` still passes
3. Tell the user to:
   - Set `POSTMARK_API_KEY` in their production environment
   - Set `MAILER_FROM_EMAIL` to a verified sender domain in Postmark
   - Optionally set `MAILER_FROM_NAME`

## Usage Pattern

The app should use the `:mailer_from` config when sending emails:

```elixir
{from_name, from_email} = Application.get_env(:<otp_app>, :mailer_from)

Swoosh.Email.new()
|> Swoosh.Email.from({from_name, from_email})
|> Swoosh.Email.to(recipient)
|> Swoosh.Email.subject("Hello")
|> Swoosh.Email.text_body("...")
|> <AppModule>.Mailer.deliver()
```

## Notes

- Postmark requires a verified sender signature or domain before emails will deliver
- The `Swoosh.ApiClient.Req` client is preferred over Finch/Hackney for new Phoenix apps
- Local adapter in dev provides the `/dev/mailbox` preview UI
- Test adapter captures emails for assertion in ExUnit tests via `Swoosh.TestAssertions`
