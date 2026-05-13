---
name: can-opener
description: "Create and update Elixir API client packages using CanOpener compile-time OpenAPI code generation. Dispatches subcommands via `/can-opener [subcommand]`. Use when the user says '/can-opener bootstrap', '/can-opener update', '/can-opener help', 'new elixir client', 'api client package', 'can opener', 'update api client', or wants to scaffold or update a CanOpener-based Elixir client library."
---

# CanOpener

Create and maintain Elixir API client packages using CanOpener — a compile-time OpenAPI 3.x client generator. CanOpener reads an OpenAPI JSON spec and generates typed client functions, schema structs, and `from_map/1` decoders with zero runtime reflection.

## Subcommands

| Subcommand | Purpose |
|------------|---------|
| `bootstrap` | Scaffold a new CanOpener client package from an OpenAPI spec |
| `update` | Update the OpenAPI spec and regenerate the client |

### `/can-opener help`

Display a list of all available subcommands. Output the following exactly:

```
/can-opener subcommands:

  bootstrap   — Scaffold a new Elixir API client package
  update      — Update the OpenAPI spec and regenerate
  help        — Show this help message
```

If `/can-opener` is invoked without a subcommand, show the help output above.

## Dispatch

1. Parse the subcommand from the user's invocation. Examples:
   - `/can-opener bootstrap` → subcommand `bootstrap`
   - `/can-opener update` → subcommand `update`
   - `/can-opener help` → show help
2. If the subcommand is unknown, list available subcommands and stop.
3. Follow the matching workflow below.

---

## `/can-opener bootstrap`

Scaffold a new Elixir client package powered by CanOpener from an OpenAPI specification.

### Gather Input

Ask the user for:

1. **Package name** — the Elixir package name (snake_case, e.g., `goodissues_ex`, `billing_client`)
2. **Module name** — the main module (PascalCase, e.g., `GoodissuesEx`, `BillingClient`)
3. **OpenAPI spec path** — path to the OpenAPI JSON file. Common locations:
   - A sibling app directory (e.g., `../app/openapi.json`)
   - A URL to fetch
   - Already in the project
4. **Base URL** — the default API base URL (e.g., `https://api.example.com`)
5. **Auth strategy** — one of:
   - `:bearer` (default) — sends `Authorization: Bearer <key>`
   - `{:header, "X-API-Key"}` — sends key in a custom header
   - `:none` — no auth
6. **Path prefix** — the API path prefix to strip for function naming (e.g., `"/api/v1/"`)
7. **GitHub repo** — for the install instructions in README (e.g., `agoodway/goodissues`, with sparse checkout path)

### Create Project

#### 1. Initialize the Mix project

```bash
mix new <package_name>
cd <package_name>
```

#### 2. Copy the OpenAPI spec

Copy the OpenAPI JSON file into the project root:

```bash
cp <spec_path> openapi.json
```

#### 3. Update mix.exs

Replace the generated `mix.exs` with:

```elixir
defmodule <ModuleName>.MixProject do
  use Mix.Project

  def project do
    [
      app: :<package_name>,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:can_opener, git: "https://github.com/agoodway/can_opener.git"}
    ]
  end
end
```

#### 4. Create the API module

Create `lib/<package_name>.ex`:

```elixir
defmodule <ModuleName> do
  @moduledoc """
  API client for <ServiceName>.

  Create a client with `client/1`, then call the generated functions.

      client = <ModuleName>.client(base_url: "<base_url>", api_key: "sk_...")

      {:ok, result} = <ModuleName>.list_items(client)
  """

  use CanOpener,
    spec: "openapi.json",
    otp_app: :<package_name>,
    base_url: "<base_url>",
    auth: <auth_strategy>,
    path_prefix: "<path_prefix>"
end
```

#### 5. Create basic tests

Create `test/<package_name>_test.exs`:

```elixir
defmodule <ModuleName>Test do
  use ExUnit.Case

  alias CanOpener.Client

  test "creates an API client" do
    assert %Client{base_url: "<base_url>", auth: nil} = <ModuleName>.client()
  end

  test "accepts explicit client options" do
    client = <ModuleName>.client(base_url: "https://api.example.test", api_key: "sk_test")

    assert client.base_url == "https://api.example.test"
    assert client.auth == {:bearer, "sk_test"}
  end

  test "generates schemas from the OpenAPI spec" do
    # Verify at least one schema struct exists — pick one from the spec
    # assert %<ModuleName>.Schemas.<SchemaName>{} = <ModuleName>.Schemas.<SchemaName>.from_map(%{})
  end

  test "generates operations from the OpenAPI spec" do
    # Verify key operations exist — check the spec for operation names
    # assert function_exported?(<ModuleName>, :list_items, 1)
    # assert function_exported?(<ModuleName>, :create_item, 2)
  end
end
```

After the project compiles, update the test to assert on actual generated schemas and operations discovered from the spec.

#### 6. Fetch deps and compile

```bash
mix deps.get
mix compile
```

If compilation succeeds, CanOpener has read the spec and generated all functions and schemas.

#### 7. Discover generated functions

After compilation, run in IEx to see what was generated:

```bash
mix run -e "<ModuleName>.__info__(:functions) |> Enum.each(fn {name, arity} -> IO.puts(\"#{name}/#{arity}\") end)"
```

Use this output to:
- Update the test file with real schema and operation assertions
- Build the function reference table for the README

#### 8. Generate README

Create a `README.md` following the pattern from GoodissuesEx:

- Package name and one-line description
- Installation instructions (git dependency with sparse checkout if in a monorepo)
- Configuration section (config.exs and runtime client options)
- Authentication section (key types if applicable)
- Usage examples grouped by resource (projects, issues, etc.)
- Error handling patterns
- Schema structs section
- Function reference table
- "How It Works" section explaining the `use CanOpener` macro

#### 9. Update tests with real assertions

Read the generated functions and schemas, then update the test file:
- Assert specific schemas exist and `from_map/1` works
- Assert key operations are exported with correct arities

#### 10. Verify

```bash
mix test
```

### Summary

Tell the user what was created:
- `mix.exs` with CanOpener dependency
- `openapi.json` — the OpenAPI spec (compiled into the module)
- `lib/<package_name>.ex` — single-file API module using `use CanOpener`
- `test/<package_name>_test.exs` — basic tests
- `README.md` — usage documentation
- All client functions, schema structs, and decoders are generated at compile time

---

## `/can-opener update`

Update the OpenAPI spec and regenerate the client.

### Workflow

1. **Find the current spec.** Look for `openapi.json` in the project root. If not found, ask the user where it is.

2. **Find the API module.** Search for `use CanOpener` in `lib/`:

   ```bash
   grep -r "use CanOpener" lib/ --include="*.ex"
   ```

   Read the `spec:` option to confirm which file is used.

3. **Determine the spec source.** Ask the user where to get the updated spec:
   - A sibling app directory (e.g., `../app/openapi.json`)
   - The Phoenix app can regenerate it with `/openapi regenerate` first
   - A URL to fetch
   - The user will provide it manually

4. **Backup the current spec:**

   ```bash
   cp openapi.json openapi.json.bak
   ```

5. **Copy the new spec:**

   ```bash
   cp <source_path> openapi.json
   ```

6. **Recompile.** Since the spec is registered as an external resource, changing it triggers recompilation:

   ```bash
   mix compile --force
   ```

   If compilation fails, show the error. Common issues:
   - New endpoints with unsupported patterns
   - Removed endpoints that tests depend on
   - Schema changes that break existing test assertions

7. **Discover changes.** Compare old and new specs to report:
   - New operations (functions) added
   - Operations removed
   - Schema changes (new fields, removed fields, type changes)
   - Run the function discovery command to list all current operations

8. **Update tests.** If new operations were added:
   - Add `function_exported?` assertions for new operations
   - Add `from_map` assertions for new schemas

9. **Update README.** If the README has a function reference table:
   - Add new functions to the table
   - Remove deleted functions
   - Update descriptions if needed

10. **Verify:**

    ```bash
    mix test
    ```

11. **Clean up:**
    - If everything passes, remove the backup: `rm openapi.json.bak`
    - If tests fail, report what needs manual attention

12. **Summary.** Report what changed: new operations, removed operations, schema changes.

---

## Quick Reference

### CanOpener Options

| Option | Required | Default | Description |
|--------|----------|---------|-------------|
| `:spec` | Yes | — | Path to OpenAPI JSON file (relative to project root) |
| `:otp_app` | Yes | — | OTP app name for runtime config lookups |
| `:base_url` | No | `"http://localhost:4000"` | Default API base URL |
| `:auth` | No | `:bearer` | Auth strategy: `:bearer`, `{:header, "X-API-Key"}`, or `:none` |
| `:path_prefix` | No | `"/"` | Path prefix stripped when generating function names |

### Generated Function Naming

From `operationId` (Phoenix controller-style):

| operationId | Generated function |
|---|---|
| `AppWeb.Api.V1.ItemController.index` | `list_items/1` |
| `AppWeb.Api.V1.ItemController.create` | `create_item/2` |
| `AppWeb.Api.V1.ItemController.show` | `show_item/2` |
| `AppWeb.Api.V1.ItemController.update` | `update_item/3` |
| `AppWeb.Api.V1.ItemController.delete` | `delete_item/2` |

From path (fallback when no operationId):

| Operation | Generated function |
|---|---|
| `GET /api/v1/status` | `get_status/1` |
| `POST /api/v1/widgets` | `post_widgets/2` |
| `GET /api/v1/items/{id}` | `get_item/2` |

### Client Usage Pattern

```elixir
# Create client
client = MyClient.client(api_key: "sk_...")

# Call generated functions
{:ok, result} = MyClient.list_items(client)
{:ok, item} = MyClient.create_item(client, %{name: "Widget"})
{:ok, item} = MyClient.show_item(client, item_id)
{:ok, item} = MyClient.update_item(client, item_id, %{name: "Updated"})
{:ok, _} = MyClient.delete_item(client, item_id)
```

### Response Pattern

```elixir
{:ok, body}                    # 2xx success, body decoded to struct if schema exists
{:error, %{status: s, body: b}} # non-2xx HTTP error
{:error, exception}             # transport error
```

### Testing with Mimic

```elixir
# test/test_helper.exs
Mimic.copy(Req)
ExUnit.start()

# In tests
expect(Req, :request, fn opts ->
  assert opts[:method] == :get
  {:ok, %Req.Response{status: 200, body: %{"data" => []}}}
end)
```

$ARGUMENTS
