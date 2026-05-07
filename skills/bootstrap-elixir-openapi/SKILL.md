---
name: bootstrap-elixir-openapi
description: >
  Bootstrap an Elixir API client library from an OpenAPI 3.x spec using compile-time
  code generation. Generates typed structs, API functions, HTTP client, and tests — all
  driven by the spec. Use when the user says "bootstrap elixir client", "new elixir api
  client", "generate elixir client from openapi", "elixir openapi client", or wants to
  create a new Hex-publishable Elixir wrapper for a REST API.
---

# Bootstrap Elixir OpenAPI Client

Generate a production-ready Elixir API client library from an OpenAPI spec. Uses compile-time code generation — no runtime code generators, no build steps. The spec is the single source of truth.

## Architecture

The generated library follows this structure:

```
{{APP_NAME}}/
  mix.exs
  .formatter.exs
  openapi.json                      # OpenAPI spec (source of truth)
  README.md
  lib/
    {{APP_NAME}}.ex                 # Public API — macro-generated endpoint functions
    {{APP_NAME}}/
      client.ex                     # HTTP client (Req-based, Bearer auth)
      schemas.ex                    # Compile-time schema struct generation
  test/
    test_helper.exs
    {{APP_NAME}}_test.exs           # Unit tests (client, schemas)
    {{APP_NAME}}/
      integration_test.exs          # Integration tests with mocked HTTP
```

Key design decisions:
- **Compile-time generation** from `openapi.json` via `@external_resource` — auto-recompiles on spec change
- **Req** for HTTP — modern, composable, Finch-backed connection pooling
- **Mimic** for test mocking — mock `Req` calls without behaviour boilerplate
- **Typed structs** for every schema — `from_map/1` recursively converts JSON to nested structs
- **No runtime dependencies** on code generators — the generated library is self-contained

## Prerequisites

1. Elixir >= 1.17 installed
2. User has an OpenAPI 3.x spec (JSON or YAML file, or a URL to fetch)

If the spec is YAML, convert to JSON during setup using Jason or yamerl, or ask the user to provide JSON.

## Gather Input

Ask the user for:

1. **API name** — human-readable name (e.g. "Stripe", "Twilio", "GoodVerify")
2. **App/package name** — the Elixir app name as an atom, snake_case (e.g. `stripe_ex`, `twilio_ex`). Suggest `{{api_name_snake}}_ex` as default.
3. **Module name** — the top-level Elixir module (e.g. `StripeEx`, `TwilioEx`). Derive from app name.
4. **OpenAPI spec** — path to a local file or URL to fetch. Accepts JSON or YAML.
5. **API base URL** — default base URL (e.g. `https://api.stripe.com`). Extract from `servers[0].url` in the spec if available.
6. **Path prefix to strip** — common API path prefix to strip when generating function names (e.g. `/api/v1/` turns `/api/v1/verify/email` into `verify_email`). Detect from spec paths if they share a common prefix.
7. **Auth style** — how the API authenticates. Default: Bearer token in Authorization header. Also support: API key header (custom header name), no auth.

Derive these automatically:
- `{{MODULE_NAME}}` — PascalCase module (e.g. `GoodverifyEx`)
- `{{APP_NAME}}` — snake_case app name (e.g. `goodverify_ex`)
- `{{APP_ATOM}}` — atom form (e.g. `:goodverify_ex`)
- `{{PATH_PREFIX}}` — path prefix to strip (e.g. `/api/v1/`)
- `{{BASE_URL}}` — default base URL
- `{{DEFAULT_BASE_URL}}` — fallback for development (e.g. `http://localhost:4000`)

## Generate

Read [references/templates.md](references/templates.md) for all file templates.

### 1. Create project structure

```bash
mkdir -p {{APP_NAME}}/{lib/{{APP_NAME}},test/{{APP_NAME}},config}
```

### 2. Place the OpenAPI spec

Copy or download the spec to `{{APP_NAME}}/openapi.json`. If the user provided YAML, convert to JSON. If a URL, fetch it.

### 3. Write mix.exs

Use the mix.exs template. Set `app: :{{APP_ATOM}}`, `version: "0.1.0"`. Include deps: `req ~> 0.5`, `jason ~> 1.4`, `mimic ~> 2.0` (test only).

### 4. Write .formatter.exs

Standard formatter config covering `{mix,.formatter}.exs` and `{config,lib,test}/**/*.{ex,exs}`.

### 5. Write the main module — `lib/{{APP_NAME}}.ex`

This is the public API entry point. Uses compile-time code generation to iterate `paths` in the OpenAPI spec and generate one function per operation.

Function name derivation:
- Strip `{{PATH_PREFIX}}` from the path
- Replace `/` with `_`
- Convert to atom

Function signatures:
- Operations **with** `requestBody` → `func_name(client, params)` where params is a map
- Operations **without** `requestBody` → `func_name(client)`

Response handling:
- Extract `$ref` from `responses.200.content.application/json.schema`
- Convert response body to the corresponding schema struct via `from_map/1`
- Return `{:ok, struct}` for 2xx, `{:error, %{status, body}}` for others, `{:error, exception}` for transport errors

Apply the main module template from references/templates.md.

### 6. Write the client module — `lib/{{APP_NAME}}/client.ex`

HTTP client struct with `base_url`, `api_key` (or equivalent auth field), and `req_options`.

Configuration priority: explicit opts > application config > defaults.

Auth header building depends on the auth style chosen:
- **Bearer token**: `{"authorization", "Bearer #{api_key}"}`
- **API key header**: `{{{HEADER_NAME}}, api_key}`
- **No auth**: empty headers

Apply the client template from references/templates.md.

### 7. Write the schemas module — `lib/{{APP_NAME}}/schemas.ex`

Compile-time schema generation from `components.schemas` in the spec. For each schema:
- Create a module `{{MODULE_NAME}}.Schemas.{{SchemaName}}`
- Define `defstruct` with sorted field names from `properties`
- Define `from_map/1` that converts JSON maps to structs
- Handle nested types: `$ref` → struct, `anyOf`/`allOf` with `$ref` → first struct found, `array` with `$ref` items → list of structs, otherwise passthrough

Apply the schemas template from references/templates.md.

### 8. Write test_helper.exs

```elixir
Mimic.copy(Req)
ExUnit.start()
```

### 9. Write unit tests — `test/{{APP_NAME}}_test.exs`

Test client creation (defaults and explicit options), schema `from_map/1` conversions for representative schemas, nil handling, unknown field handling, and that expected API functions are exported.

Select 2-3 representative schemas from the spec that exercise:
- Simple flat schemas
- Schemas with nested `$ref` fields
- Schemas with array-of-ref fields

### 10. Write integration tests — `test/{{APP_NAME}}/integration_test.exs`

For each generated API function, write at least:
- One success case (200 response with full mock data, asserting struct types and field values)
- One error case (4xx or 5xx response)

Also test:
- Transport errors (connection refused, timeout)
- Auth header presence/absence
- Custom `req_options` passthrough

Use the Mimic `expect(Req, :request, fn opts -> ... end)` pattern.

### 11. Write README.md

Follow this structure:
1. Title and one-line description
2. Installation (mix.exs dependency)
3. Configuration (application config and runtime)
4. Usage examples for each endpoint
5. Error handling patterns
6. Response types table
7. Testing instructions
8. License

### 12. Install dependencies and verify

```bash
cd {{APP_NAME}} && mix deps.get && mix compile && mix test
```

If compilation or tests fail, fix the issues before continuing.

### 13. Initialize git

```bash
cd {{APP_NAME}} && git init && git add -A && git commit -m "feat: initial {{API_NAME}} API client library"
```

## Path Prefix Detection

To auto-detect `{{PATH_PREFIX}}`:
1. Collect all paths from `spec["paths"]`
2. Find the longest common prefix that ends with `/`
3. Suggest it to the user (e.g. "Detected common prefix `/api/v1/` — strip it from function names?")

## Handling Edge Cases

### Path parameters
If paths contain `{param}` placeholders (e.g. `/users/{id}`), generate functions that accept the path parameter as an argument:
- `/users/{id}` with GET → `get_user(client, id)`
- `/users/{id}/posts` with GET → `list_user_posts(client, id)`

### Multiple response codes
If an operation defines multiple success responses (200, 201, 204), use the first one with a JSON schema. If 204 (no content), return `{:ok, nil}`.

### Operations with operationId
If `operationId` is present, prefer it over path-derived names. Convert to snake_case atom.

## Output

After generation, print:

```
Created {{APP_NAME}}/ — Elixir client for the {{API_NAME}} API

  lib/{{APP_NAME}}.ex                  — Public API (N functions generated)
  lib/{{APP_NAME}}/client.ex           — HTTP client (Req-based)
  lib/{{APP_NAME}}/schemas.ex          — M schema structs generated
  test/                                — Unit + integration tests

Configuration:
  config :{{APP_ATOM}},
    base_url: "{{BASE_URL}}",
    api_key: "your-api-key"

Quick start:
  client = {{MODULE_NAME}}.client(api_key: "sk_...")
  {:ok, result} = {{MODULE_NAME}}.{{EXAMPLE_FUNC}}(client)

Regenerate after spec changes:
  Replace openapi.json and recompile — structs update automatically.
```
