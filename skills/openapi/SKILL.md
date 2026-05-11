---
name: openapi
description: "Manage OpenAPI specifications in Phoenix apps using open_api_spex. Dispatches subcommands via `/openapi [subcommand]`. Use when the user says '/openapi regenerate', '/openapi help', 'regenerate openapi', 'update openapi spec', 'openapi json', 'openapi yaml', or wants to regenerate the OpenAPI specification from controller operations."
---

# OpenAPI

Manage OpenAPI specifications in Phoenix apps that use `open_api_spex`.

## Subcommands

| Subcommand | Purpose |
|------------|---------|
| `regenerate` | Regenerate the OpenAPI spec from controller operations |

### `/openapi help`

Display a list of all available subcommands. Output the following exactly:

```
/openapi subcommands:

  regenerate   — Regenerate the OpenAPI spec from controller operations
  help         — Show this help message
```

If `/openapi` is invoked without a subcommand, default to `regenerate`.

## Dispatch

1. Parse the subcommand from the user's invocation. Examples:
   - `/openapi` → default to `regenerate`
   - `/openapi regenerate` → subcommand `regenerate`
   - `/openapi help` → show help
2. If the subcommand is unknown, list available subcommands and stop.
3. Follow the matching workflow below.

---

## `/openapi regenerate`

Regenerate the OpenAPI specification from the app's controller operations and schema modules.

### How open_api_spex works

Phoenix apps using `open_api_spex` derive their OpenAPI spec from three sources:

1. **ApiSpec module** — implements `OpenApiSpex.OpenApi` behaviour. Defines metadata, servers, security schemes, and calls `Paths.from_router(Router)` to discover all routes.
2. **Controller operations** — each controller action declares its operation spec (parameters, request body schemas, responses) via `OpenApiSpex.operation/2` or the `OpenApiSpex.ControllerSpecs` DSL.
3. **Schema modules** — Ecto-like structs that implement `OpenApiSpex.Schema` for request/response bodies.

### Workflow

1. **Find the ApiSpec module.** Search for the module that implements `@behaviour OpenApiSpex.OpenApi`:

   ```bash
   grep -r "@behaviour OpenApiSpex.OpenApi" lib/ --include="*.ex"
   ```

   It is typically named `<App>Web.ApiSpec`. If not found, check for `@behaviour OpenApi` (aliased import). If still not found, tell the user their app may not have `open_api_spex` set up and stop.

2. **Check for existing spec files.** Look for `openapi.json` or `openapi.yaml` in the project root to determine which format is in use.

3. **Regenerate the spec.** Run the appropriate mix task:

   For JSON:
   ```bash
   mix openapi.spec.json --spec <App>Web.ApiSpec
   ```

   For YAML:
   ```bash
   mix openapi.spec.yaml --spec <App>Web.ApiSpec
   ```

   Use whichever format already exists. If both exist, regenerate both. If neither exists, default to JSON.

4. **Handle compilation errors.** If the mix task fails with a compilation error:
   - Show the error to the user.
   - The spec is generated at compile time from live code — the error must be fixed in the source before the spec can be generated.
   - Offer to help fix the compilation error.

5. **Verify the output.** Diff the generated spec against the previous version:

   ```bash
   git diff openapi.json
   ```

   Report what changed:
   - New endpoints added
   - Endpoints removed
   - Schema changes
   - If no changes, report that the spec is already up to date.

6. **Check for common issues.** Warn the user about:

   - **Missing operations** — if a controller action lacks an `OpenApiSpex.operation` callback or `@doc operation:` annotation, its route won't appear in the spec. List any routes in the router that don't have corresponding operations in the generated spec.
   - **Schema drift** — if Ecto schemas were recently changed but API schema modules weren't updated, the spec may be stale. API schemas typically live alongside controllers or in a `schemas/` directory.
   - **Server URL** — the `servers` field comes from `Server.from_endpoint(Endpoint)`, which reads the endpoint config. In dev this is typically `localhost:4000`.

### Notes

- The YAML format requires the `ymlr` dependency. If the user wants YAML but doesn't have `ymlr`, tell them to add `{:ymlr, "~> 5.0"}` to their deps.
- The generated spec file should be committed to version control.
- If the user has a companion CLI project (e.g., a Zig or Go client), suggest running the client's OpenAPI update command after regenerating.

$ARGUMENTS
