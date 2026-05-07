---
name: bootstrap-go-openapi
description: >
  Add OpenAPI client code generation to an existing Go project using oapi-codegen.
  Generates typed Go client and models from an OpenAPI 3.0 spec. Use when the user says
  "bootstrap openapi", "add openapi client", "generate go client from spec",
  "oapi-codegen", "openapi codegen", or wants to consume a REST API from Go using
  a generated client.
---

# Bootstrap Go OpenAPI Client

Add oapi-codegen client generation to an existing Go project. Assumes `go.mod` already exists.

## Prerequisites

Verify before starting:
1. `go.mod` exists in the project root
2. User has an OpenAPI 3.0 spec (local file or URL)

If the spec is OpenAPI 3.1, warn the user: oapi-codegen has partial 3.1 support. Recommend converting to 3.0 or testing carefully.

## Gather Input

Ask the user for:

1. **OpenAPI spec path** — path to their `.yaml`/`.json` spec file (e.g. `api/openapi.yaml`)
2. **Client package name** — Go package for generated code (e.g. `petstore`, `acmeapi`). Suggest deriving from the API name in the spec.

Detect the module path from `go.mod`.

## Generate

Read [references/templates.md](references/templates.md) for all file templates.

### 1. Create client package directory

```bash
mkdir -p <client_pkg>
```

### 2. Create oapi-codegen config

Write `<client_pkg>/generate.yaml` from the config template. Uses `client: true` + `models: true`.

### 3. Create generate.go

Write `<client_pkg>/generate.go` with the `//go:generate` directive pointing at the spec.

The spec path in the directive must be relative to the `generate.go` file. If the spec is at `api/openapi.yaml` and generate.go is at `petstore/generate.go`, the path is `../api/openapi.yaml`.

### 4. Create apiconfig package

Write `internal/apiconfig/apiconfig.go` from the template. This provides per-environment config storage (base_url + api_key) using Viper's config file.

```bash
mkdir -p internal/apiconfig
```

### 5. Create configure command

Write `cmd/configure.go` from the template. Adds three subcommands:

- `configure set --env <name> --base-url <url> --api-key <key>` — save credentials for an environment
- `configure show` — list all configured environments (API keys are masked)
- `configure use <name>` — switch the default environment

Config is stored in the Viper config file (`~/.{{APP_NAME}}.yaml`) under:

```yaml
default_env: production
environments:
  production:
    base_url: https://api.example.com
    api_key: sk-xxx
```

### 6. Install dependencies

```bash
go get github.com/oapi-codegen/runtime@latest
go mod tidy
```

### 7. Run code generation

```bash
go generate ./...
```

### 8. Add justfile recipes

If a `justfile` exists, append `generate` and `regen` recipes from the templates. Check whether a `tidy` recipe already exists — if so use `regen: generate tidy`, otherwise inline `go mod tidy` in the `regen` recipe. Skip recipes that already exist.

### 9. Verify

```bash
go build ./...
```

## Output

After generation, print:

```
Added OpenAPI client in <client_pkg>/:
  generate.yaml              — oapi-codegen config (client + models)
  generate.go                — go:generate directive
  client.gen.go              — generated client and models (do not edit)

Added environment config:
  internal/apiconfig/        — per-env config loader (base_url + api_key)
  cmd/configure.go           — configure set/show/use commands

Setup:
  <app> configure set --env production --base-url https://api.example.com --api-key sk-xxx
  <app> configure show
  <app> configure use staging

Regenerate after spec changes:
  go generate ./...
```

## Notes

- Generated `*.gen.go` files should be committed to version control
- Regenerate with `go generate ./...` after any spec changes
- The config file (`~/.{{APP_NAME}}.yaml`) stores API keys — add it to `.gitignore` (already handled by bootstrap-go-cli)
- For large APIs, consider splitting models and client — see the split config pattern in references/templates.md
- Use `apiconfig.Load(env)` in your commands to get the active environment's base URL and API key for creating the generated client
