---
name: bootstrap-nebulex
description: >
  Bootstrap Nebulex caching in a Phoenix 1.8 app. Creates a Cache module backed
  by Nebulex.Adapters.Local, adds it to the supervision tree, configures GC and
  memory limits, adds a cache helper module with common patterns (get-or-store,
  invalidation), and wires up test config. Use when the user says "bootstrap
  nebulex", "add caching", "setup cache", "add nebulex", "bootstrap cache",
  "in-memory cache", or wants application-level caching in a Phoenix app.
---

# Bootstrap Nebulex Cache

Add [Nebulex](https://hexdocs.pm/nebulex/Nebulex.html) application caching to a Phoenix 1.8 app with a local (single-node) in-memory adapter, sensible GC/memory defaults, a helper module with common cache patterns, and test configuration.

## What Gets Created/Configured

1. **mix.exs** — `{:nebulex, "~> 2.6"}` dependency
2. **lib/<app>/cache.ex** — Cache module using `Nebulex.Adapters.Local`
3. **lib/<app>/cache_helpers.ex** — Convenience functions (get-or-store, bulk invalidation, key namespacing)
4. **lib/<app>/application.ex** — Cache added to supervision tree
5. **config/config.exs** — GC interval, max size, allocated memory defaults
6. **config/test.exs** — Shorter GC interval for tests
7. **test/support/cache_case.ex** — (Optional) ExUnit case template that flushes cache between tests
8. **test/<app>/cache_test.exs** — Basic smoke tests

## App Name Detection

Detect from `mix.exs`:
- **App module prefix** (e.g., `MyApp`) — the module namespace
- **OTP app name** (e.g., `:my_app`) — used in config atoms
- **Application module** (e.g., `MyApp.Application`) — for supervision tree

Also detect:
- **Existing caching** — Check if nebulex, cachex, con_cache, or hand-rolled ETS caches already exist
- **Supervision tree** — Find where to insert the cache child spec

## Phase 0: Discovery

**CRITICAL: Audit the target app before making any changes.**

### Discovery Checklist

1. **Existing caching** — Search for `nebulex`, `cachex`, `con_cache`, `Cachex`, `ConCache`, `:ets.new` in the codebase
   - If Nebulex is already a dependency: report what exists and ask the user what they want to add/change
   - If another caching library is in use: report and ask if they want to add Nebulex alongside or replace it

2. **mix.exs** — Read to get app name, module prefix, and existing deps

3. **application.ex** — Find the supervision tree children list and identify where to insert the cache (after Repo, before Endpoint is a good default)

4. **Config files** — Check `config/config.exs`, `config/dev.exs`, `config/test.exs`, `config/prod.exs`, `config/runtime.exs` for any existing cache config

5. **Test support** — Check `test/support/` for existing case templates

### Discovery Report

Present findings to user. If caching is already configured, confirm before proceeding. Otherwise show what will be added and confirm.

## Phase 1: Dependency

### Step 1: Add Nebulex to mix.exs

Add to the `deps` function in `mix.exs`:

```elixir
{:nebulex, "~> 2.6"},
```

**Placement:** Add in the deps list alphabetically or grouped with other infrastructure deps.

Then run:
```bash
mix deps.get
```

## Phase 2: Cache Module

### Step 2: Create the Cache Module

Create `lib/<app>/cache.ex`:

```elixir
defmodule <AppModule>.Cache do
  @moduledoc """
  Application cache backed by Nebulex.

  Uses the local adapter for single-node in-memory caching. This provides a
  fast, process-safe cache without external infrastructure. The API is
  consistent with Nebulex's distributed adapters if you later need to scale
  to a multi-node setup.

  ## Configuration

      config :<otp_app>, <AppModule>.Cache,
        gc_interval: :timer.hours(12),
        max_size: 100_000,
        allocated_memory: 512_000_000,
        gc_memory_check_interval: :timer.minutes(10)

  ## Basic Usage

      alias <AppModule>.Cache

      # Simple get/put
      Cache.put("key", "value", ttl: :timer.minutes(5))
      Cache.get("key")

      # Delete
      Cache.delete("key")

      # Get with default
      Cache.get("key") || "default"

  See `<AppModule>.CacheHelpers` for higher-level patterns like get-or-store.
  """

  use Nebulex.Cache,
    otp_app: :<otp_app>,
    adapter: Nebulex.Adapters.Local
end
```

### Step 3: Create Cache Helpers Module

Create `lib/<app>/cache_helpers.ex`:

```elixir
defmodule <AppModule>.CacheHelpers do
  @moduledoc """
  Convenience functions for common caching patterns.

  Wraps `<AppModule>.Cache` with higher-level operations like get-or-store,
  namespaced keys, and bulk invalidation.

  ## Examples

      alias <AppModule>.CacheHelpers

      # Fetch from cache or compute and store
      CacheHelpers.get_or_store("user:123", ttl: :timer.minutes(10), fn ->
        Repo.get!(User, 123)
      end)

      # Invalidate all keys with a prefix
      CacheHelpers.invalidate_matching("user:123:*")
  """

  alias <AppModule>.Cache

  @doc """
  Returns a cached value or computes, stores, and returns it.

  If the key exists in the cache, returns the cached value immediately.
  Otherwise, calls `fun`, stores the result with the given TTL, and returns it.

  ## Options

    * `:ttl` — Time-to-live in milliseconds. Defaults to 5 minutes.

  ## Examples

      get_or_store("expensive:query", ttl: :timer.minutes(30), fn ->
        Repo.all(expensive_query)
      end)
  """
  @spec get_or_store(term(), keyword(), (-> term())) :: term()
  def get_or_store(key, opts \\ [], fun) do
    case Cache.get(key) do
      nil ->
        value = fun.()
        ttl = Keyword.get(opts, :ttl, :timer.minutes(5))
        Cache.put(key, value, ttl: ttl)
        value

      cached ->
        cached
    end
  end

  @doc """
  Builds a namespaced cache key.

  Joins the parts with `:` to create consistent, readable cache keys.

  ## Examples

      key("users", 123, "profile")
      #=> "users:123:profile"
  """
  @spec key(term(), term()) :: String.t()
  def key(namespace, id), do: "#{namespace}:#{id}"

  @spec key(term(), term(), term()) :: String.t()
  def key(namespace, id, suffix), do: "#{namespace}:#{id}:#{suffix}"

  @doc """
  Deletes all entries from the cache.

  Useful for testing or administrative resets. In production, prefer
  targeted invalidation with `Cache.delete/1`.
  """
  @spec flush_all() :: integer()
  def flush_all do
    Cache.delete_all()
  end
end
```

## Phase 3: Supervision Tree

### Step 4: Add Cache to Application

In `lib/<app>/application.ex`, add `<AppModule>.Cache` to the children list. Place it **after** the Repo and **before** the Endpoint:

```elixir
children = [
  <AppModule>.Repo,
  # ... other children ...
  <AppModule>.Cache,          # <-- Add this
  # ... more children ...
  <WebModule>.Endpoint
]
```

**Placement rationale:** The cache should start after the database (in case startup logic needs DB access) but before the web endpoint (so it's available when requests arrive).

## Phase 4: Configuration

### Step 5: Base Config (config/config.exs)

Add to `config/config.exs`:

```elixir
# Nebulex local cache
config :<otp_app>, <AppModule>.Cache,
  gc_interval: :timer.hours(12),
  max_size: 100_000,
  allocated_memory: 512_000_000,
  gc_memory_check_interval: :timer.minutes(10)
```

**Configuration options explained:**

| Option | Default | Purpose |
|--------|---------|---------|
| `gc_interval` | 12 hours | How often the generational GC promotes/evicts entries |
| `max_size` | 100,000 | Maximum number of entries before GC kicks in |
| `allocated_memory` | 512 MB | Memory ceiling in bytes before GC kicks in |
| `gc_memory_check_interval` | 10 min | How often to check memory usage |

**ADAPT these values based on the app's expected cache usage:**
- **Light caching** (config, small lookups): `max_size: 10_000`, `allocated_memory: 100_000_000` (100 MB)
- **Medium caching** (API responses, user data): `max_size: 100_000`, `allocated_memory: 512_000_000` (512 MB)
- **Heavy caching** (large datasets, computed results): `max_size: 500_000`, `allocated_memory: 1_000_000_000` (1 GB)

### Step 6: Test Config (config/test.exs)

Add to `config/test.exs`:

```elixir
# Shorter GC interval for tests
config :<otp_app>, <AppModule>.Cache,
  gc_interval: :timer.seconds(1)
```

## Phase 5: Test Support (Optional)

### Step 7: Cache Case Template

If the app will use caching in contexts that need test isolation, create `test/support/cache_case.ex`:

```elixir
defmodule <AppModule>.CacheCase do
  @moduledoc """
  ExUnit case template for tests that interact with the cache.

  Automatically flushes the cache before each test to ensure isolation.

  ## Usage

      use <AppModule>.CacheCase
  """

  use ExUnit.CaseTemplate

  setup do
    <AppModule>.Cache.delete_all()
    :ok
  end
end
```

### Step 8: Smoke Tests

Create `test/<app>/cache_test.exs`:

```elixir
defmodule <AppModule>.CacheTest do
  use ExUnit.Case, async: false

  alias <AppModule>.Cache
  alias <AppModule>.CacheHelpers

  setup do
    Cache.delete_all()
    :ok
  end

  describe "Cache" do
    test "put and get" do
      Cache.put("test_key", "test_value")
      assert Cache.get("test_key") == "test_value"
    end

    test "returns nil for missing keys" do
      assert Cache.get("nonexistent") == nil
    end

    test "delete removes a key" do
      Cache.put("to_delete", "value")
      Cache.delete("to_delete")
      assert Cache.get("to_delete") == nil
    end

    test "ttl expires entries" do
      Cache.put("expiring", "value", ttl: 1)
      Process.sleep(10)
      assert Cache.get("expiring") == nil
    end
  end

  describe "CacheHelpers" do
    test "get_or_store caches the computed value" do
      result = CacheHelpers.get_or_store("computed", ttl: :timer.minutes(1), fn ->
        "expensive_result"
      end)

      assert result == "expensive_result"
      assert Cache.get("computed") == "expensive_result"
    end

    test "get_or_store returns cached value on subsequent calls" do
      call_count = :counters.new(1, [:atomics])

      fetch = fn ->
        :counters.add(call_count, 1, 1)
        "result"
      end

      CacheHelpers.get_or_store("counted", ttl: :timer.minutes(1), fetch)
      CacheHelpers.get_or_store("counted", ttl: :timer.minutes(1), fetch)

      assert :counters.get(call_count, 1) == 1
    end

    test "key/2 builds namespaced key" do
      assert CacheHelpers.key("users", 123) == "users:123"
    end

    test "key/3 builds namespaced key with suffix" do
      assert CacheHelpers.key("users", 123, "profile") == "users:123:profile"
    end

    test "flush_all clears all entries" do
      Cache.put("a", 1)
      Cache.put("b", 2)
      CacheHelpers.flush_all()
      assert Cache.get("a") == nil
      assert Cache.get("b") == nil
    end
  end
end
```

## Phase 6: Verification

1. Run `mix deps.get` to fetch Nebulex
2. Run `mix compile --warnings-as-errors` to verify everything compiles
3. Run `mix test` to ensure no regressions and new cache tests pass
4. If the app has `mix precommit` or `mix check`, run that

## Usage Examples

### Simple Key-Value

```elixir
alias <AppModule>.Cache

# Store with 5-minute TTL
Cache.put("config:feature_flags", flags, ttl: :timer.minutes(5))

# Retrieve
Cache.get("config:feature_flags")
```

### Get-or-Store Pattern

```elixir
alias <AppModule>.CacheHelpers

# Fetch user profile, cache for 10 minutes
profile = CacheHelpers.get_or_store(
  CacheHelpers.key("users", user_id, "profile"),
  ttl: :timer.minutes(10),
  fn -> Accounts.get_user_profile(user_id) end
)
```

### Cache Invalidation on Update

```elixir
def update_user(user, attrs) do
  case Repo.update(User.changeset(user, attrs)) do
    {:ok, updated} ->
      Cache.delete(CacheHelpers.key("users", user.id, "profile"))
      {:ok, updated}

    error ->
      error
  end
end
```

### In a Plug

```elixir
defmodule <WebModule>.Plugs.CachedConfig do
  @behaviour Plug
  alias <AppModule>.CacheHelpers

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    config = CacheHelpers.get_or_store("app:config", ttl: :timer.minutes(15), fn ->
      <AppModule>.Settings.load_public_config()
    end)

    Plug.Conn.assign(conn, :app_config, config)
  end
end
```

## Notes

- Nebulex's local adapter uses a generational cache (two ETS tables that rotate on GC). This means entries aren't evicted immediately at TTL — they're evicted when GC runs. For most apps this is fine.
- The local adapter is single-node only. If you run multiple instances (e.g., multiple Fly machines), each has its own cache. For shared caching, switch to `Nebulex.Adapters.Replicated` or a Redis-backed adapter like `NebulexRedisAdapter`.
- `Cache.delete_all/0` is O(n) — avoid in hot paths. Use targeted `Cache.delete/1` instead.
- Nebulex keys can be any Erlang term, not just strings. Tuples like `{:user, 123}` work fine, but string keys are easier to pattern-match for bulk invalidation.
- The `get_or_store` helper is not atomic — under high concurrency, multiple processes may compute the value simultaneously (thundering herd). For most Phoenix apps this is acceptable. If you need atomic get-or-store, use `:global` locks or a dedicated GenServer.
- Memory defaults (512 MB) are generous for a single-node app. Monitor with `:observer` or Nebulex telemetry and adjust down if needed.
