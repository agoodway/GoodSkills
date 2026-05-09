---
name: durex
description: "Add Durex GenServer state checkpointing to Elixir projects. Dispatches subcommands via `/durex [subcommand]`. Use when the user says '/durex bootstrap', '/durex add', '/durex help', 'add durex', 'checkpoint genserver', 'genserver crash recovery', or wants to set up or integrate Durex state checkpointing."
---

# Durex

Durex provides GenServer state checkpointing to external stores (Redis or Tigris) for crash recovery and node migration. This skill helps bootstrap Durex into a project and add checkpointing to GenServers.

## Subcommands

| Subcommand | Purpose |
|------------|---------|
| `bootstrap` | Add Durex to a Phoenix/Elixir app (deps, config, optional Redis supervision) |
| `add <Module>` | Add Durex checkpointing to an existing GenServer module |

### `/durex help`

Display a list of all available subcommands. Output the following exactly:

```
/durex subcommands:

  bootstrap          — Add Durex to your project (deps, config, store setup)
  add <Module>       — Add Durex checkpointing to a GenServer
  help               — Show this help message
```

If `/durex` is invoked without a subcommand, show the help output above.

## Dispatch

1. Parse the subcommand and args from the user's invocation. Examples:
   - `/durex bootstrap` → subcommand `bootstrap`
   - `/durex add MyApp.SessionServer` → subcommand `add`, arg `MyApp.SessionServer`
   - `/durex help` → show help
2. If the subcommand is unknown, list available subcommands and stop.
3. Follow the matching workflow below.

---

## `/durex bootstrap`

Add Durex as a dependency and configure the chosen store backend.

### 1. Ask which store backend

Ask the user: "Which store backend do you want to use?"

- **Redis** — Low-latency hot recovery. Requires a Redix connection in your supervision tree.
- **Tigris** — Durable object-backed checkpointing via S3-compatible API. Tolerates higher latency.

### 2. Add dependency to `mix.exs`

Add to the `deps` function:

```elixir
{:durex, github: "agoodway/durex", branch: "main"}
```

If the user chose **Tigris**, also add `:req` (Durex declares it as optional):

```elixir
{:req, "~> 0.5"}
```

Run `mix deps.get`.

### 3. Add configuration

#### Redis

Add to `config/config.exs`:

```elixir
config :durex, :app_name, :my_app  # replace with actual app name

config :durex, Durex.Store.Redis,
  connection: MyApp.Redis  # replace with actual Redis process name
```

Then check if the app already has a Redix process in its supervision tree (`application.ex`). If not, add one:

```elixir
{Redix, name: MyApp.Redis, host: "localhost"}
```

Also check if `:redix` is already a dependency. If not, add it:

```elixir
{:redix, "~> 1.5"}
```

And run `mix deps.get` again.

#### Tigris

Add to `config/config.exs`:

```elixir
config :durex, :app_name, :my_app  # replace with actual app name
```

Add to `config/runtime.exs` (create if needed):

```elixir
config :durex, Durex.Store.Tigris,
  bucket: System.get_env("TIGRIS_BUCKET") || raise("TIGRIS_BUCKET not set"),
  access_key_id: System.get_env("TIGRIS_ACCESS_KEY_ID") || raise("TIGRIS_ACCESS_KEY_ID not set"),
  secret_access_key: System.get_env("TIGRIS_SECRET_ACCESS_KEY") || raise("TIGRIS_SECRET_ACCESS_KEY not set"),
  prefix: "checkpoints"
```

Add the env vars to `.env.sample` (create if needed):

```
TIGRIS_BUCKET=
TIGRIS_ACCESS_KEY_ID=
TIGRIS_SECRET_ACCESS_KEY=
```

### 4. Summary

Tell the user what was added and what to do next:
- For Redis: ensure the Redis process name matches their actual named Redix connection.
- For Tigris: fill in the Tigris credentials in their `.env` or deployment config.
- Suggest running `/durex add <Module>` to add checkpointing to a GenServer.

---

## `/durex add <Module>`

Add Durex checkpointing to an existing GenServer.

### 1. Validate the module

- Read the file for the given module.
- Verify it is a GenServer (`use GenServer` must be present).
- If the module is not found or is not a GenServer, tell the user and stop.

### 2. Determine the store

- Check `config/config.exs` and `config/runtime.exs` for Durex store configuration.
- If `Durex.Store.Redis` is configured, use that.
- If `Durex.Store.Tigris` is configured, use that.
- If both are configured, ask the user which to use for this module.
- If neither is configured, tell the user to run `/durex bootstrap` first and stop.

### 3. Add `use Durex`

Add `use Durex` after `use GenServer` with sensible defaults:

```elixir
use Durex,
  store: Durex.Store.Redis,  # or Durex.Store.Tigris
  interval: 30_000,
  ttl: 300,
  version: 1
```

### 4. Add the three required callbacks

Add at the bottom of the module (before the final `end`):

```elixir
# --- Durex callbacks ---

@impl Durex
def serialize(state) do
  Map.take(state, [:key1, :key2])  # only checkpoint the keys that matter
end

@impl Durex
def deserialize(data) do
  Map.new(data, fn {k, v} -> {String.to_existing_atom(k), v} end)
end

@impl Durex
def checkpoint_key(state) do
  state.id  # unique identifier for this process instance
end
```

**Important:** Analyze the module's state shape to fill in realistic values:
- `serialize/1`: include the state keys that represent meaningful data (skip derived/cached fields).
- `checkpoint_key/1`: use whatever field uniquely identifies the process (an ID, session_id, name, etc.).
- If the state shape is unclear, add TODO comments and tell the user what to fill in.

### 5. Wire up `init/1`

Modify the existing `init/1` to start sync and optionally restore:

```elixir
def init(args) do
  # ... existing init logic that builds initial state ...

  # Start periodic checkpointing
  state = Durex.start_sync(__MODULE__, state)

  # Restore from checkpoint if available
  case Durex.maybe_restore(__MODULE__, state) do
    {:ok, nil}      -> {:ok, state}
    {:ok, restored} -> {:ok, Map.merge(state, restored)}
  end
end
```

Preserve the existing init logic — insert the Durex calls after state is built but before the return tuple.

### 6. Add `terminate/2`

If the module already has a `terminate/2`, add a `Durex.checkpoint/2` call at the top. If it doesn't have one, add:

```elixir
@impl GenServer
def terminate(_reason, state) do
  Durex.checkpoint(__MODULE__, state)
end
```

### 7. Ordering check

Verify that `use Durex` comes before any catch-all `handle_info/2` clause. Durex injects a `handle_info(:__durex_sync__, ...)` clause — a catch-all above it would shadow the sync handler. If a catch-all exists, warn the user to reorder.

### 8. Summary

Tell the user what was added:
- `use Durex` with options
- Three callbacks: `serialize/1`, `deserialize/1`, `checkpoint_key/1`
- Init wiring: `start_sync` + `maybe_restore`
- Terminate wiring: final checkpoint on shutdown
- Any TODOs they need to fill in

---

## Quick Reference

### Key Concepts

- **State must be a map.** Structs work (they are maps). Keyword lists and tuples are not supported.
- **`__durex__` key is reserved.** Durex stashes timer bookkeeping there. It's automatically excluded from serialization.
- **Place `use Durex` before catch-all `handle_info` clauses.** Durex injects a `handle_info(:__durex_sync__, ...)` clause.
- **JSON round-trips atom keys to strings.** `deserialize/1` must handle this with `String.to_existing_atom/1`.
- **Version bumping:** when serialization format changes, bump the `:version` option to discard stale checkpoints.

### API

| Function | Purpose |
|---|---|
| `Durex.start_sync(module, state)` | Start periodic sync timer, returns updated state |
| `Durex.checkpoint(module, state)` | Write checkpoint immediately |
| `Durex.maybe_restore(module, state)` | Restore from checkpoint, returns `{:ok, data \| nil}` |
| `Durex.delete(module, state)` | Remove stored checkpoint |

### Options

| Option | Default | Description |
|---|---|---|
| `:store` | (required) | `Durex.Store.Redis` or `Durex.Store.Tigris` |
| `:interval` | `30_000` | Milliseconds between periodic checkpoints |
| `:ttl` | `nil` | TTL in seconds for stored checkpoints |
| `:version` | `1` | Schema version; bump to invalidate stale checkpoints |

### Telemetry Events

| Event | When |
|---|---|
| `[:durex, :checkpoint, :write]` | Successful write (includes `:duration`) |
| `[:durex, :checkpoint, :write_failed]` | Store error (includes `:reason`) |
| `[:durex, :checkpoint, :skipped]` | Payload too large or encode failed |
| `[:durex, :restore, :ok]` | Restore completed (includes `:found` boolean) |
| `[:durex, :restore, :failed]` | Store error during restore |

$ARGUMENTS
