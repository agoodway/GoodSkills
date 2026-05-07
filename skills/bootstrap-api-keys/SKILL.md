---
name: bootstrap-api-keys
description: >
  Bootstrap API key management UI and backend in a Phoenix 1.8 app. Generates migration,
  schema, context functions, LiveView with create/revoke modals, Bearer token auth plug,
  and router entries. Checks what already exists and only adds missing pieces.
  Use when the user says "bootstrap api keys", "add api keys", "api key management",
  "generate api keys", or wants to add API key CRUD to a Phoenix app.
---

# Bootstrap API Keys

Add complete API key management to a Phoenix 1.8 app — schema, context, LiveView UI, and Bearer token auth plug.

## Prerequisites

Verify before starting:
1. Phoenix 1.8 app with `phx.gen.auth` completed
2. DaisyUI installed
3. A parent association exists for scoping keys (e.g., `users`, `account_users`, or `accounts` table)

## App Name Detection

Detect the app module name from `mix.exs` (e.g., `MyApp`) and the OTP app name (e.g., `my_app`). Replace all occurrences of `MyApp`/`my_app`/`MyAppWeb`/`my_app_web` in reference templates with the actual names.

## Phase 0: Discovery — Check What Already Exists

**CRITICAL: Before generating anything, audit the target app to understand what's already in place.** Search for each component and track what exists vs what's missing. Only create what's missing.

### Discovery Checklist

Run these checks and record findings:

1. **Migration** — Search `priv/repo/migrations/` for files containing `api_keys`
   - `Glob("priv/repo/migrations/*api_key*")` and `Grep("api_keys", path: "priv/repo/migrations/")`
   - If found: skip migration creation

2. **Schema** — Search for an existing `ApiKey` schema module
   - `Grep("schema \"api_keys\"")` or `Glob("lib/**/api_key.ex")`
   - If found: read it, note the parent association and fields, use it as-is

3. **Context functions** — Search for existing API key context functions
   - `Grep("def create_api_key")`, `Grep("def verify_api_token")`, `Grep("def list_api_keys")`, `Grep("def revoke_api_key")`
   - If found: note which functions exist, only add missing ones

4. **LiveView** — Search for existing API key LiveView
   - `Glob("lib/**/api_key_live/**")` or `Grep("ApiKeyLive")`
   - If found: skip LiveView creation (or ask user if they want to replace it)

5. **Auth plug** — Search for existing Bearer token auth plug
   - `Grep("Bearer.*token")` in plugs directory, or `Grep("ApiAuth")`
   - If found: skip plug creation

6. **Router entries** — Search for existing api-keys routes
   - `Grep("api.key\\|api_key\\|ApiKey", path: "lib/*_web/router.ex")`
   - If found: skip route additions

7. **Rate limiter** — Check if a rate limiter exists
   - `Grep("RateLimiter")` or check for Hammer dependency in mix.exs
   - If not found: skip rate limiting in the LiveView

8. **TaskSupervisor** — Check if one exists for async key touching
   - `Grep("TaskSupervisor")` in application.ex
   - If not found: use synchronous touch or add one

### Discovery Report

After the audit, present a summary to the user:
```
Existing: [list what was found]
Missing:  [list what will be created]
```

Ask for confirmation before proceeding. If the app already has partial API key support, adapt the plan to fill gaps rather than overwrite.

## Phase 1: Gather Configuration (only for missing pieces)

If the schema doesn't already exist, ask the user:

1. **Parent association** — What table/schema should API keys belong to?
   - `users` (simplest — keys belong directly to a user)
   - `account_users` (multi-tenant — keys scoped to user+account membership)
   - `accounts` (keys belong to an org/team, not a specific user)
   Default: `users`

2. **Key types** — Should there be public (read-only) and private (read-write) key types?
   Default: yes (public `pk_*` and private `sk_*`)

3. **Rate limiting** — Should key creation be rate-limited?
   Default: yes if rate limiter exists, no otherwise

4. **Where to mount** — What route path for the LiveView? (e.g., `/api-keys`, `/settings/api-keys`)
   Default: `/api-keys`

5. **Existing live_session** — Should the route be added to an existing live_session or create a new one?

If the schema already exists, infer configuration from it (parent association, key types, etc.) and skip questions that are already answered by existing code.

## Phase 2: Implementation (only missing pieces)

Execute in order, **skipping any step where discovery found existing code**.

### Step 1: Data Layer (if missing)
Read [references/database.md](references/database.md)

1. Create migration for `api_keys` table
2. Create `ApiKey` schema with token generation and hashing

### Step 2: Context Layer (if missing or incomplete)
Read [references/context.md](references/context.md)

3. Add API key functions to the relevant context module:
   - `create_api_key/2` — generates token, stores hash, returns `{:ok, {api_key, raw_token}}`
   - `list_api_keys/1` — list keys for parent
   - `revoke_api_key/1` — set status to `:revoked`
   - `verify_api_token/1` — look up by prefix+hash, check active+not expired
   - `touch_api_key/1` — update `last_used_at`
   Only add functions that don't already exist.

### Step 3: LiveView UI (if missing)
Read [references/liveview.md](references/liveview.md)

4. Create `ApiKeyLive.Index` LiveView with:
   - Key listing table (name, type badge, prefix, status badge, last used, created, actions)
   - Empty state when no keys exist
   - Create key modal (name, type selector, optional expiration)
   - Token display modal (shown once after creation, copy-to-clipboard)
   - Revoke confirmation modal
   - All modals dismissable with Escape

### Step 4: Auth Plug (if missing)
Read [references/auth-plug.md](references/auth-plug.md)

5. Create `ApiAuth` plug for Bearer token authentication
6. Add router pipelines for `:api_authenticated` and `:api_write`

### Step 5: Routes & Integration (if missing)
Read [references/routes.md](references/routes.md)

7. Add LiveView route to router
8. Run migration and verify with `mix test`

## Key Security Patterns

- **Never store raw tokens** — only the SHA256 hash and a 12-char prefix
- **Show token exactly once** — after creation, in a modal with copy button
- **Prefix convention** — `pk_` for public (read-only), `sk_` for private (read-write)
- **Verify with prefix+hash** — prefix narrows the lookup, hash confirms identity
- **Soft revocation** — revoked keys stay in DB with status flag, never deleted
- **Expiration** — optional UTC datetime, checked at verification time
