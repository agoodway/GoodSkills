---
name: bootstrap-google-analytics
description: >
  Bootstrap Google Analytics (GA4) in a Phoenix 1.8 app. Configures gtag script in root layout,
  config.exs for disabled-by-default, runtime.exs for production enablement via env var, and updates
  .env.sample. Use when the user says "bootstrap google analytics", "add GA4", "add analytics",
  "setup google analytics", "configure gtag", or wants to add Google Analytics tracking to a Phoenix app.
---

# Bootstrap Google Analytics (GA4)

Configure Google Analytics 4 with gtag.js in a Phoenix 1.8 app — disabled in dev/test, enabled in production via environment variable.

## What Gets Configured

1. **config.exs** — GA disabled by default with `enabled: false, measurement_id: nil`
2. **runtime.exs** — GA enabled in production with `GOOGLE_ANALYTICS_MEASUREMENT_ID` env var
3. **root.html.heex** — Conditional gtag.js script injection
4. **.env.sample** — `GOOGLE_ANALYTICS_MEASUREMENT_ID` entry

## App Name Detection

Detect from `mix.exs`:
- **App module prefix** (e.g., `MyApp`) — the module namespace
- **OTP app name** (e.g., `:my_app`) — used in config atoms
- **Web module prefix** (e.g., `MyAppWeb`) — for layout references

Also detect:
- **Root layout file** — Look for `root.html.heex` in `lib/<app>_web/components/layouts/`
- **Existing GA config** — Check all config files for existing `:google_analytics` settings
- **Existing gtag scripts** — Check root layout for existing Google Analytics script tags

## Phase 0: Discovery

**CRITICAL: Audit the target app before making any changes.**

### Discovery Checklist

1. **Root layout** — Locate `root.html.heex` in `lib/<app>_web/components/layouts/`
   - If missing: stop and notify user — the layout must exist before adding GA

2. **Existing GA script** — Search root layout for `googletagmanager.com/gtag` or `gtag(`
   - If found: GA is already in the layout — note and skip layout changes

3. **Existing config** — Check each config file:
   - `config/config.exs` — look for `:google_analytics` config
   - `config/runtime.exs` — look for `:google_analytics` in `if config_env() == :prod` block

4. **Existing .env.sample** — Check for `GOOGLE_ANALYTICS_MEASUREMENT_ID` entry

5. **CSP headers** — Search for Content-Security-Policy configuration
   - If CSP is configured: note that `https://www.googletagmanager.com` and `https://www.google-analytics.com` must be allowed in `script-src` and `connect-src`

### Discovery Report

Present findings to user. If GA is already fully configured, confirm and skip. Otherwise show what will be added/changed.

## Phase 1: Implementation

Execute in order, skipping anything that already exists.

### Step 1: Base Config (config/config.exs)

Add if not present:
```elixir
# Google Analytics Configuration
# Measurement ID is set via GOOGLE_ANALYTICS_MEASUREMENT_ID env var in runtime.exs
config :<otp_app>, :google_analytics,
  enabled: false,
  measurement_id: nil
```

### Step 2: Runtime Config (config/runtime.exs)

Inside the `if config_env() == :prod do` block, add:
```elixir
  # Google Analytics Configuration for Production
  config :<otp_app>, :google_analytics,
    enabled: true,
    measurement_id: System.get_env("GOOGLE_ANALYTICS_MEASUREMENT_ID")
```

**Important:** Place this inside the existing `if config_env() == :prod do` block — do not create a duplicate conditional.

**Note:** The measurement ID is not required — if missing, GA will be "enabled" but the script won't load because the conditional in the layout checks for a truthy measurement_id. This allows deploying without GA configured.

### Step 3: Root Layout (root.html.heex)

Add the gtag.js script block just before the closing `</head>` tag:
```heex
<%= if Application.get_env(:<otp_app>, :google_analytics)[:enabled] do %>
  <script
    async
    src={"https://www.googletagmanager.com/gtag/js?id=#{Application.get_env(:<otp_app>, :google_analytics)[:measurement_id]}"}
  >
  </script>
  <script>
    window.dataLayer = window.dataLayer || [];
    function gtag(){dataLayer.push(arguments);}
    gtag('js', new Date());
    gtag('config', '<%= Application.get_env(:<otp_app>, :google_analytics)[:measurement_id] %>');
  </script>
<% end %>
```

**Placement:** Insert before `</head>` — after meta tags, CSS, and other scripts. The `async` attribute ensures it doesn't block page rendering.

### Step 4: Environment File (.env.sample)

Add these entries if not already present:
```
# Google Analytics
GOOGLE_ANALYTICS_MEASUREMENT_ID=
```

## Phase 2: Verification

1. Run `mix compile --warnings-as-errors` to verify config compiles
2. Check that `mix test` still passes
3. Verify the script does NOT appear in dev by:
   - Checking that `config/config.exs` has `enabled: false`
4. Tell the user to:
   - Set `GOOGLE_ANALYTICS_MEASUREMENT_ID` in their production environment (e.g., `G-XXXXXXXXXX`)
   - Find the measurement ID in Google Analytics: Admin > Data Streams > Web > Measurement ID
   - If using CSP headers, add `https://www.googletagmanager.com` and `https://www.google-analytics.com` to `script-src` and `connect-src`

## Notes

- GA4 uses measurement IDs that start with `G-` (e.g., `G-SBPZDTZ6RW`)
- The gtag.js script loads asynchronously and won't block page rendering
- GA is completely disabled in dev/test — no network requests to Google
- The `enabled` flag provides a clean way to toggle GA without removing config
- If you need to test GA locally, temporarily set `enabled: true` in `config/dev.exs`:
  ```elixir
  config :<otp_app>, :google_analytics,
    enabled: true,
    measurement_id: "G-XXXXXXXXXX"
  ```
- For GDPR compliance, consider adding a cookie consent banner before enabling GA — gtag.js sets cookies by default
