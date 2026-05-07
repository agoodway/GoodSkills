---
name: bootstrap-zig-cli
description: >
  Bootstrap a Zig CLI application with zero dependencies, JSON config, help system,
  cross-compilation, and install script. Optimized for distribution to AI coding agents.
  Use when the user says "bootstrap zig cli", "new zig cli", "create a cli app in zig",
  "zig command line", "scaffold zig cli", or wants to start a new Zig CLI project.
---

# Bootstrap Zig CLI

Scaffold a production-ready Zig CLI application with zero external dependencies. Produces
a single static binary (~1MB) that cross-compiles to macOS, Linux, and Windows from any platform.
Designed for distribution to AI coding agents via `curl | sh` (or `install.ps1` on Windows).

## Reference Implementation

The Henry CLI at `/Users/tbrewer/projects/goodway/henry/cli-zig/` is the reference
implementation this skill is based on. When in doubt about patterns, read those files.

## Prerequisites

Verify before starting:
1. `zig version` returns 0.15.x or later
2. User has a directory for the project

## Gather Input

Ask the user for:

1. **App name** — binary name (lowercase, hyphen-separated, e.g. `my-tool`)
2. **Description** — one-line description for root help
3. **Subcommands** — initial commands to scaffold (e.g. `sync`, `deploy`, `status`)
4. **Config needed?** — whether the app needs per-environment config (`~/.{{APP_NAME}}.json`)
5. **API client?** — whether to include an HTTP client for a REST API (if yes, ask for base URL)

## Generate Project

Read [references/templates.md](references/templates.md) for all file templates.

Create files in this order:

### 1. Initialize project

```bash
mkdir -p <app-name>/src/commands
cd <app-name>
zig init
rm src/root.zig  # No library consumers
```

### 2. Create files from templates

Apply placeholder substitution (`{{APP_NAME}}`, `{{DESCRIPTION}}`) to each template:

| File | Template | Notes |
|------|----------|-------|
| `build.zig` | build.zig template | Binary named `{{APP_NAME}}`, no deps |
| `build.zig.zon` | build.zig.zon template | Zero dependencies |
| `src/main.zig` | main.zig template | Command routing + arg helpers |
| `src/help.zig` | help.zig template | All help text, agent-readable |
| `src/commands/<subcmd>.zig` | subcommand template (one per command) | |
| `justfile` | justfile template | build/test/dist/release recipes |
| `install.sh` | install.sh template | macOS/Linux installer |
| `install.ps1` | install.ps1 template | Windows PowerShell installer |
| `.gitignore` | .gitignore template | |
| `CLAUDE.md` | CLAUDE.md template | |

If config is needed, also create:

| File | Template |
|------|----------|
| `src/config.zig` | config.zig template |
| `src/commands/configure.zig` | configure.zig template |

If API client is needed, also create:

| File | Template |
|------|----------|
| `src/generated.zig` | generated.zig template |
| `src/table.zig` | table.zig template |

### 2b. OpenAPI client generation (if user has an OpenAPI spec)

If the user has an OpenAPI JSON spec, use `openapi2zig` to seed the types and client:

```bash
# Install openapi2zig if not present
which openapi2zig || curl -fsSL https://christianhelle.com/openapi2zig/install | INSTALL_DIR="$HOME/.local/bin" bash

# Generate from spec
~/.local/bin/openapi2zig generate -i <spec-path> -o src/generated.zig
```

**CRITICAL: The generated output will NOT compile on Zig 0.15.2.** You MUST manually fix it:

1. **Function names** — `HenryWeb.Api.V1.Controller.index` is invalid Zig. Replace with valid identifiers like `listItems`, `getItem`, `createItem`.
2. **Nested types flattened** — Fields like `hero: ?[]const u8` should be `hero: ?Hero` with proper struct types. Fix all `$ref` fields.
3. **Old API calls** — Replace `std.http.Client.init(allocator)` with `std.http.Client{ .allocator = allocator }`. Replace `std.ArrayList(u8).init(allocator)` with `var list: std.ArrayList(u8) = .{};`. Replace `std.json.stringify` with `std.json.fmt`.
4. **No auth headers** — Add Bearer token auth via `extra_headers` in `fetch()`.
5. **No response handling** — Functions return `!void`. Change to return `RawResponse` with status + body.
6. **No base URL** — Functions use relative paths. Add a `Client` struct that holds `base_url` and prepends it.

See the `generated.zig` template in references/templates.md for the corrected pattern.
The reference implementation at `/Users/tbrewer/projects/goodway/henry/cli-zig/src/generated.zig` shows a complete working example.

Add a `generate` recipe to the justfile:

```just
# Regenerate API client from OpenAPI spec (requires manual fixes after)
generate:
    ~/.local/bin/openapi2zig generate -i <spec-path> -o src/generated.zig
    @echo "IMPORTANT: Generated code needs manual fixes for Zig 0.15.2 — see CLAUDE.md"
```

### 3. Fix fingerprint

The first `zig build` will fail with an invalid fingerprint error and suggest the correct value. Run:

```bash
zig build 2>&1
```

Then update `build.zig.zon` with the suggested fingerprint value and build again.

### 4. Verify

```bash
zig build
zig build test
zig build run -- --help
```

## Zig 0.15.2+ Critical Patterns

These are non-obvious and will cause compilation failures if done wrong:

1. **stdout/stderr** — Use `std.fs.File.stdout()`, not `std.io.getStdOut()` (removed in 0.15)
2. **ArrayList** — Unmanaged: `var list: std.ArrayList(u8) = .{};` then pass allocator to each method: `list.append(allocator, x)`, `list.deinit(allocator)`
3. **Formatted output** — Use `std.fmt.allocPrint(allocator, fmt, args)` then `File.stdout().writeAll(msg)`
4. **JSON serialization** — Use `std.json.fmt(value, .{.whitespace = .indent_2})` with `std.fmt.allocPrint("{f}", .{...})`
5. **JSON parsing** — `std.json.parseFromSlice(T, allocator, content, .{.ignore_unknown_fields = true, .allocate = .alloc_always})`
6. **HTTP client** — Use `std.http.Client.fetch()` with `std.Io.Writer.Allocating` to capture response body. No `.open()` method.
7. **Table rows in loops** — Heap-allocate row slices: `const row = try allocator.alloc([]const u8, n);`. Stack-allocated `&.{...}` gets overwritten each iteration.
8. **main signature** — `pub fn main() !void` (no Init parameter in 0.15.2)
9. **Allocator for CLI** — Use `std.heap.page_allocator` for short-lived CLI processes. GPA reports false leak warnings on exit.

## Help System Design

CRITICAL: The help system is designed to be read by AI coding agents. Every command must have:

- Usage line with exact syntax
- All flags with types and descriptions
- All positional arguments with descriptions
- Behavior notes (what happens when, defaults, side effects)
- Exit codes
- Examples showing common use cases

When adding a new command, you MUST update THREE files:
1. `src/main.zig` — routing in `main()` and `dispatchHelp()`
2. `src/help.zig` — add help constant AND update parent command's help listing
3. `src/commands/<name>.zig` — implementation

## Output

After generation, print:

```
Created {{APP_NAME}}/ with:
  build.zig              — build config (zero dependencies)
  build.zig.zon          — package manifest
  src/main.zig           — CLI entry point + arg parsing
  src/help.zig           — comprehensive help text (agent-readable)
  src/commands/*.zig     — command implementations
  justfile               — build/test/dist/release recipes
  install.sh             — macOS/Linux installer (auto-detects OS/arch)
  install.ps1            — Windows PowerShell installer
  CLAUDE.md              — AI agent instructions

Binary: zig-out/bin/{{APP_NAME}} (~1MB release)

Run it:
  cd {{APP_NAME}} && zig build run -- --help

Cross-compile all platforms:
  just dist

Next steps:
  - Implement command logic in src/commands/*.zig
  - Update help text in src/help.zig for each command
  - Run `zig build test` to verify
  - Run `just dist` to build release binaries
```
