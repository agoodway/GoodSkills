---
name: horde
description: "Set up Horde distributed process infrastructure in Elixir/Phoenix apps. Dispatches subcommands via `/horde [subcommand]`. Use when the user says '/horde bootstrap', '/horde add', '/horde singleton', '/horde help', 'add horde', 'distributed processes', 'cluster registry', or wants to set up Horde registry, supervisor, or cluster monitoring."
---

# Horde

Set up distributed process infrastructure using Horde — a cluster-wide registry and dynamic supervisor for Elixir/Phoenix apps. Processes registered via Horde are unique across all BEAM nodes and automatically redistributed when nodes join or leave.

## Subcommands

| Subcommand | Purpose |
|------------|---------|
| `bootstrap` | Add Horde to a Phoenix app (deps, registry, supervisor, cluster monitor, supervision tree) |
| `add <Module>` | Add Horde registration to an existing GenServer (via tuple, lookup, ensure_started) |
| `singleton <Module>` | Create a cluster-wide singleton GenServer managed by Horde |

### `/horde help`

Display a list of all available subcommands. Output the following exactly:

```
/horde subcommands:

  bootstrap          — Add Horde infrastructure to your project
  add <Module>       — Add Horde registration to a GenServer
  singleton <Module> — Create a cluster-wide singleton GenServer
  help               — Show this help message
```

If `/horde` is invoked without a subcommand, show the help output above.

## Dispatch

1. Parse the subcommand and args from the user's invocation. Examples:
   - `/horde bootstrap` → subcommand `bootstrap`
   - `/horde add MyApp.SessionServer` → subcommand `add`, arg `MyApp.SessionServer`
   - `/horde singleton MyApp.Reconciler` → subcommand `singleton`, arg `MyApp.Reconciler`
   - `/horde help` → show help
2. If the subcommand is unknown, list available subcommands and stop.
3. Follow the matching workflow below.

---

## `/horde bootstrap`

Add Horde distributed process infrastructure to a Phoenix/Elixir app.

### 1. Detect the app

- Read `mix.exs` to find the app name and main module prefix (e.g., `MyApp`).
- Read `lib/<app>/application.ex` to understand the existing supervision tree.

### 2. Add dependency

Add to `deps` in `mix.exs`:

```elixir
{:horde, "~> 0.9"}
```

Run `mix deps.get`.

### 3. Create HordeRegistry module

Create `lib/<app>/horde_registry.ex`:

```elixir
defmodule MyApp.HordeRegistry do
  @moduledoc """
  Cluster-wide distributed process registry backed by Horde.

  Provides unique key registration across all nodes in the cluster.
  Processes can be located by their registered name using
  `{:via, Horde.Registry, {MyApp.HordeRegistry, key}}` tuples.

  Uses Horde's built-in `members: :auto` to automatically track
  BEAM node membership via Horde's internal NodeListener.
  """

  use Horde.Registry

  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts) do
    Horde.Registry.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  @spec init(keyword()) :: {:ok, keyword()}
  def init(opts) do
    members = Keyword.get(opts, :members, :auto)

    Horde.Registry.init(keys: :unique, members: members)
  end
end
```

### 4. Create HordeSupervisor module

Create `lib/<app>/horde_supervisor.ex`:

```elixir
defmodule MyApp.HordeSupervisor do
  @moduledoc """
  Cluster-wide distributed dynamic supervisor backed by Horde.

  Child processes started via this supervisor are distributed across
  available nodes and automatically redistributed when a node leaves
  the cluster.

  Uses Horde's built-in `members: :auto` to automatically track
  BEAM node membership.

  Start child processes using:

      MyApp.HordeSupervisor.start_child(child_spec)
  """

  use Horde.DynamicSupervisor

  require Logger

  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts) do
    Horde.DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    members = Keyword.get(opts, :members, :auto)

    Horde.DynamicSupervisor.init(strategy: :one_for_one, members: members)
  end

  @doc """
  Starts a child process after validating the module against the allowlist.

  Returns `{:error, :module_not_allowed}` if the child spec's module
  is not in the configured `:horde_allowed_modules` list. When the
  allowlist is empty (default), all modules are permitted.
  """
  @spec start_child(Supervisor.child_spec() | {module(), term()} | module()) ::
          DynamicSupervisor.on_start_child() | {:error, :module_not_allowed}
  def start_child(child_spec) do
    if allowed_module?(child_spec) do
      Horde.DynamicSupervisor.start_child(__MODULE__, child_spec)
    else
      {:error, :module_not_allowed}
    end
  end

  defp allowed_modules do
    Application.get_env(:my_app, :horde_allowed_modules, [])
  end

  defp allowed_module?(child_spec) do
    case allowed_modules() do
      [] -> true
      modules -> extract_module(child_spec) in modules
    end
  end

  defp extract_module(%{start: {mod, _, _}}), do: mod
  defp extract_module({mod, _opts}) when is_atom(mod), do: mod
  defp extract_module(mod) when is_atom(mod), do: mod

  defp extract_module(other) do
    Logger.warning("HordeSupervisor: unable to extract module from child spec: #{inspect(other)}")
    nil
  end
end
```

Replace `:my_app` in `allowed_modules/0` with the actual app atom from `mix.exs`.

### 5. Create ClusterMonitor module

Create `lib/<app>/cluster_monitor.ex`:

```elixir
defmodule MyApp.ClusterMonitor do
  @moduledoc """
  Monitors BEAM node membership events for logging and security validation.

  Watches `:nodeup` and `:nodedown` events via `:net_kernel.monitor_nodes/2`
  and validates joining nodes against a configurable trusted suffix allowlist.
  Untrusted nodes are disconnected and logged as warnings.

  Horde cluster membership is managed automatically via `members: :auto`
  in the HordeRegistry and HordeSupervisor. This monitor provides
  defense-in-depth node validation only.
  """

  use GenServer

  require Logger

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    :net_kernel.monitor_nodes(true, node_type: :visible)
    {:ok, %{trusted_suffixes: trusted_suffixes()}}
  end

  @impl true
  def handle_info({:nodeup, node, _info}, state) do
    if trusted_node?(node, state.trusted_suffixes) do
      Logger.info("ClusterMonitor: trusted node joined — #{node}")
    else
      Logger.warning("ClusterMonitor: untrusted node rejected — #{node}")
      Node.disconnect(node)
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:nodedown, node, _info}, state) do
    Logger.info("ClusterMonitor: node left — #{node}")
    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  defp trusted_suffixes do
    Application.get_env(:my_app, :cluster_trusted_suffixes, [])
  end

  defp trusted_node?(_node, []), do: true

  defp trusted_node?(node, suffixes) do
    node_str = Atom.to_string(node)
    Enum.any?(suffixes, &String.ends_with?(node_str, &1))
  end
end
```

Replace `:my_app` with the actual app atom.

### 6. Add to supervision tree

In `application.ex`, add the three modules to the children list. They must start in this order and before any processes that use Horde:

```elixir
MyApp.HordeRegistry,
MyApp.HordeSupervisor,
MyApp.ClusterMonitor,
```

Place them after `PubSub` and `Repo` but before any application-specific supervisors or workers that will register via Horde.

### 7. Add config

Add to `config/config.exs`:

```elixir
# Horde: modules allowed to start as children in HordeSupervisor.
# Empty list permits all modules (useful for dev/test).
config :my_app, :horde_allowed_modules, []
```

Ask the user if they want to restrict which modules can be started in the HordeSupervisor. If yes, populate the allowlist. If no, leave it empty (all modules permitted).

### 8. Optional: DNS clustering

Check if `dns_cluster` is already a dependency. If not, ask the user if they deploy to a platform with DNS-based node discovery (Fly.io, Kubernetes). If yes:

- Add `{:dns_cluster, "~> 0.1"}` to deps
- Add to the supervision tree (before Horde modules):
  ```elixir
  {DNSCluster, query: Application.get_env(:my_app, :dns_cluster_query) || :ignore}
  ```
- Add to `config/runtime.exs`:
  ```elixir
  config :my_app, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")
  ```

### 9. Summary

Tell the user what was created:
- `HordeRegistry` — cluster-wide unique process registry
- `HordeSupervisor` — distributed dynamic supervisor with module allowlist
- `ClusterMonitor` — node membership monitoring with trusted suffix validation
- Supervision tree wiring
- Config entries
- Suggest running `/horde add <Module>` to register a GenServer with Horde

---

## `/horde add <Module>`

Add Horde registration to an existing GenServer so it can be located across the cluster.

### 1. Validate the module

- Read the file for the given module.
- Verify it is a GenServer (`use GenServer` must be present).
- If not found or not a GenServer, tell the user and stop.

### 2. Verify Horde infrastructure

- Check that `HordeRegistry` and `HordeSupervisor` modules exist in the project.
- If not, tell the user to run `/horde bootstrap` first and stop.

### 3. Determine the registry key

Analyze the module to determine what uniquely identifies each process instance. Common patterns:
- An ID field passed in opts (e.g., `session_id`, `user_id`, `room_id`)
- A name or slug

Ask the user if the key isn't obvious.

### 4. Add via/1 helper

Add a private function that builds the via tuple:

```elixir
defp via(id) do
  {:via, Horde.Registry, {MyApp.HordeRegistry, {:module_key, id}}}
end
```

Where `:module_key` is a descriptive atom (e.g., `:session_server`, `:room_worker`).

### 5. Add lookup/1

Add a public function to find a running process:

```elixir
@spec lookup(String.t()) :: {:ok, pid()} | :error
def lookup(id) do
  case Horde.Registry.lookup(MyApp.HordeRegistry, {:module_key, id}) do
    [{pid, _}] -> {:ok, pid}
    [] -> :error
  end
end
```

### 6. Add ensure_started/1

Add a public function that finds or starts the process:

```elixir
@spec ensure_started(String.t()) :: {:ok, pid()} | {:error, term()}
def ensure_started(id) do
  case lookup(id) do
    {:ok, pid} ->
      if Process.alive?(pid), do: {:ok, pid}, else: start(id)

    :error ->
      start(id)
  end
end
```

### 7. Add start/1 (private)

Add a private function that starts via HordeSupervisor:

```elixir
defp start(id) do
  child_spec =
    Supervisor.child_spec({__MODULE__, id: id}, restart: :transient)

  case MyApp.HordeSupervisor.start_child(child_spec) do
    {:ok, pid} -> {:ok, pid}
    {:error, {:already_started, pid}} -> {:ok, pid}
    error -> error
  end
end
```

### 8. Update start_link/1

Modify `start_link` to use the via tuple for named registration:

```elixir
def start_link(opts) do
  id = Keyword.fetch!(opts, :id)
  GenServer.start_link(__MODULE__, opts, name: via(id))
end
```

### 9. Update module allowlist

If the project has a non-empty `:horde_allowed_modules` config, add this module to the list.

### 10. Summary

Tell the user what was added:
- `via/1` — builds the Horde registry via tuple
- `lookup/1` — finds a running process by ID
- `ensure_started/1` — finds or starts the process
- `start/1` — starts via HordeSupervisor with race condition handling
- Updated `start_link/1` with Horde naming
- How to use: `MyModule.ensure_started(id)` to get a pid

---

## `/horde singleton <Module>`

Create or convert a GenServer into a cluster-wide singleton — only one instance runs across all nodes, managed by Horde.

### 1. Validate or create the module

- If the module exists, verify it's a GenServer.
- If it doesn't exist, create a new GenServer module.

### 2. Verify Horde infrastructure

- Check that `HordeRegistry` and `HordeSupervisor` modules exist.
- If not, tell the user to run `/horde bootstrap` first and stop.

### 3. Add via/0 helper (no arguments — singleton)

```elixir
defp via do
  {:via, Horde.Registry, {MyApp.HordeRegistry, :my_singleton_key}}
end
```

Use a descriptive atom key (e.g., `:reconciler`, `:scheduler`).

### 4. Add ensure_started/0

```elixir
@spec ensure_started() :: {:ok, pid()} | {:error, term()}
def ensure_started do
  case Horde.Registry.lookup(MyApp.HordeRegistry, :my_singleton_key) do
    [{pid, _}] ->
      {:ok, pid}

    [] ->
      child_spec = Supervisor.child_spec({__MODULE__, []}, restart: :permanent)

      case MyApp.HordeSupervisor.start_child(child_spec) do
        {:ok, pid} -> {:ok, pid}
        {:error, {:already_started, pid}} -> {:ok, pid}
        error -> error
      end
  end
end
```

### 5. Update start_link/1

```elixir
def start_link(opts) do
  GenServer.start_link(__MODULE__, opts, name: via())
end
```

### 6. Update module allowlist

If the project has a non-empty `:horde_allowed_modules` config, add this module to the list.

### 7. Summary

Tell the user:
- The module is now a cluster-wide singleton
- Only one instance will run across all nodes
- Use `MyModule.ensure_started()` to guarantee it's running
- If the node hosting it goes down, Horde will restart it on another node

---

## Quick Reference

### Key Concepts

- **`members: :auto`** — Horde automatically tracks BEAM node membership. No manual cluster configuration needed.
- **Via tuples** — `{:via, Horde.Registry, {MyApp.HordeRegistry, key}}` for GenServer naming.
- **Module allowlist** — controls which modules can start children in HordeSupervisor. Empty list permits all.
- **Race handling** — always handle `{:error, {:already_started, pid}}` from `start_child` since another node may win the race.
- **Restart strategy** — use `:transient` for on-demand processes, `:permanent` for singletons.

### Supervision tree order

```
Repo
PubSub
DNSCluster          (optional, for node discovery)
MyApp.HordeRegistry (must start before supervisor)
MyApp.HordeSupervisor
MyApp.ClusterMonitor
... application workers ...
```

### Common patterns

**Locate a process:**
```elixir
Horde.Registry.lookup(MyApp.HordeRegistry, {:my_key, id})
```

**Start a distributed process:**
```elixir
MyApp.HordeSupervisor.start_child(child_spec)
```

**Register on start:**
```elixir
GenServer.start_link(__MODULE__, opts, name: {:via, Horde.Registry, {MyApp.HordeRegistry, key}})
```

$ARGUMENTS
