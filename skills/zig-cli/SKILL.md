---
name: zig-cli
description: "Build and maintain Zig CLI applications with zero dependencies, cross-compilation, and OpenAPI client generation. Dispatches subcommands via `/zig-cli [subcommand]`. Use when the user says '/zig-cli bootstrap', '/zig-cli openapi-update', '/zig-cli add-command', '/zig-cli help', 'new zig cli', 'bootstrap zig cli', 'update openapi client', 'add zig command', or wants to scaffold, extend, or maintain a Zig CLI project."
---

# Zig CLI

Build and maintain production-ready Zig CLI applications. Single static binary (~1MB), zero external dependencies, cross-compiles to macOS, Linux, and Windows from any platform.

## Subcommands

| Subcommand | Purpose |
|------------|---------|
| `bootstrap` | Scaffold a new Zig CLI project from scratch |
| `openapi-update` | Regenerate the API client from an OpenAPI spec |
| `add-command <name>` | Add a new subcommand to an existing Zig CLI |
| `dist` | Cross-compile release binaries for all platforms |

### `/zig-cli help`

Display a list of all available subcommands. Output the following exactly:

```
/zig-cli subcommands:

  bootstrap              — Scaffold a new Zig CLI project
  openapi-update         — Regenerate API client from OpenAPI spec
  add-command <name>     — Add a new subcommand to the CLI
  dist                   — Cross-compile for all 6 platforms
  help                   — Show this help message
```

If `/zig-cli` is invoked without a subcommand, show the help output above.

## Dispatch

1. Parse the subcommand and args from the user's invocation. Examples:
   - `/zig-cli bootstrap` → subcommand `bootstrap`
   - `/zig-cli openapi-update` → subcommand `openapi-update`
   - `/zig-cli add-command verify` → subcommand `add-command`, arg `verify`
   - `/zig-cli dist` → subcommand `dist`
   - `/zig-cli help` → show help
2. If the subcommand is unknown, list available subcommands and stop.
3. Follow the matching workflow below.

---

## `/zig-cli bootstrap`

Scaffold a production-ready Zig CLI application with zero external dependencies. Produces a single static binary (~1MB) that cross-compiles to macOS, Linux, and Windows.

### Prerequisites

Verify before starting:
1. `zig version` returns 0.15.x or later
2. User has a directory for the project

### Gather Input

Ask the user for:

1. **App name** — binary name (lowercase, hyphen-separated, e.g. `my-tool`)
2. **Description** — one-line description for root help
3. **Subcommands** — initial commands to scaffold (e.g. `sync`, `deploy`, `status`)
4. **Config needed?** — whether the app needs per-environment config (`~/.{app-name}.json`)
5. **API client?** — whether to include an HTTP client for a REST API (if yes, ask for base URL and whether they have an OpenAPI spec)

### Generate Project

Read [references/templates.md](references/templates.md) for all file templates.

Create files in this order:

#### 1. Initialize project

```bash
mkdir -p <app-name>/src/commands
cd <app-name>
zig init
rm src/root.zig  # No library consumers
```

#### 2. Create files from templates

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

#### 2b. OpenAPI client generation (if user has a spec)

If the user has an OpenAPI JSON spec, use `openapi2zig` to seed the types and client:

```bash
which openapi2zig || curl -fsSL https://christianhelle.com/openapi2zig/install | INSTALL_DIR="$HOME/.local/bin" bash
~/.local/bin/openapi2zig generate -i <spec-path> -o src/generated.zig
```

**CRITICAL: The generated output will NOT compile on Zig 0.15.2.** You MUST manually fix it:

1. **Function names** — dotted names like `Namespace.Controller.action` are invalid Zig. Replace with valid identifiers like `listItems`, `getItem`.
2. **Nested types flattened** — fields like `hero: ?[]const u8` should be `hero: ?Hero` with proper struct types.
3. **Old API calls** — Replace `std.http.Client.init(allocator)` with `std.http.Client{ .allocator = allocator }`. Replace `std.ArrayList(u8).init(allocator)` with `var list: std.ArrayList(u8) = .{};`.
4. **No auth headers** — Add Bearer token auth via `extra_headers` in `fetch()`.
5. **No response handling** — Functions return `!void`. Change to return `RawResponse` with status + body.
6. **No base URL** — Functions use relative paths. Add a `Client` struct that holds `base_url` and prepends it.

See the `generated.zig` template in references/templates.md for the corrected pattern.

Add a `generate` recipe to the justfile:

```just
generate:
    ~/.local/bin/openapi2zig generate -i <spec-path> -o src/generated.zig
    @echo "IMPORTANT: Generated code needs manual fixes for Zig 0.15.2 — see CLAUDE.md"
```

#### 3. Fix fingerprint

The first `zig build` will fail with an invalid fingerprint error and suggest the correct value. Run `zig build 2>&1`, then update `build.zig.zon` with the suggested fingerprint and build again.

#### 4. Verify

```bash
zig build
zig build test
zig build run -- --help
```

### Output

After generation, print a summary of created files and next steps.

---

## `/zig-cli openapi-update`

Regenerate the API client (`src/generated.zig`) from an OpenAPI spec.

### Workflow

1. **Find the OpenAPI spec** — look for common locations:
   - Check if the user specified a path in args
   - Look for `openapi.json` or `openapi.yaml` in the project root
   - Look for a sibling `../app/openapi.json` (common for companion API projects)
   - If not found, ask the user for the spec path

2. **Install openapi2zig if needed**:
   ```bash
   which openapi2zig || curl -fsSL https://christianhelle.com/openapi2zig/install | INSTALL_DIR="$HOME/.local/bin" bash
   ```

3. **Backup existing generated.zig** (if it exists):
   ```bash
   cp src/generated.zig src/generated.zig.bak
   ```

4. **Generate from spec**:
   ```bash
   ~/.local/bin/openapi2zig generate -i <spec-path> -o src/generated.zig
   ```

5. **Fix the generated output for Zig 0.15.2** — the raw output will NOT compile. Apply these fixes:

   - **Function names** — replace dotted identifiers (e.g., `AppWeb.Api.V1.Controller.index`) with valid Zig names (e.g., `listItems`). Use the backup file as reference for naming conventions if it exists.
   - **Nested types** — ensure `$ref` fields use proper struct types, not `[]const u8`.
   - **HTTP client pattern** — replace generated client code with the `Client` struct pattern from references/templates.md (base URL, Bearer auth, `fetch()`, `RawResponse`).
   - **ArrayList API** — `var list: std.ArrayList(u8) = .{};` not `std.ArrayList(u8).init(allocator)`.
   - **HTTP Client init** — `std.http.Client{ .allocator = allocator }` not `std.http.Client.init(allocator)`.
   - **JSON** — `std.json.fmt()` not `std.json.stringify()`.

6. **Verify**:
   ```bash
   zig build
   zig build test
   ```

7. **Clean up**:
   - If build succeeds, remove the backup: `rm src/generated.zig.bak`
   - If build fails, report errors and keep the backup for reference

8. **Summary** — report what changed: new endpoints, removed endpoints, type changes.

---

## `/zig-cli add-command <name>`

Add a new subcommand to an existing Zig CLI project.

### Workflow

1. **Validate project** — verify `src/main.zig`, `src/help.zig`, and `src/commands/` exist.

2. **Create the command file** — `src/commands/<name>.zig`:

   ```zig
   const std = @import("std");
   const main_mod = @import("../main.zig");

   const File = std.fs.File;

   pub fn run(allocator: std.mem.Allocator, args: []const []const u8) !void {
       _ = args;
       try main_mod.writeOut(allocator, "TODO: implement <name>\n", .{});
   }
   ```

3. **Update src/main.zig** — add three things:
   - Import: `const <name> = @import("commands/<name>.zig");`
   - Command routing in `main()`: add an `if` branch for the command name
   - Help dispatch in `dispatchHelp()`: route to the help constant

4. **Update src/help.zig** — add two things:
   - A new `pub const <name>_help` constant with full usage, flags, behavior, exit codes, and examples
   - Add the command to the `root_help` commands listing

5. **Verify**: `zig build && zig build test`

6. **Remind the user** — when adding a command, you MUST update THREE files:
   - `src/main.zig` — routing
   - `src/help.zig` — help text
   - `src/commands/<name>.zig` — implementation

---

## `/zig-cli dist`

Cross-compile release binaries for all 6 supported platforms.

### Workflow

1. **Check for justfile** — if `justfile` exists with a `dist` recipe, run `just dist`.

2. **Manual fallback** — if no justfile:
   ```bash
   mkdir -p dist
   zig build -Dtarget=aarch64-macos -Doptimize=ReleaseSafe && cp zig-out/bin/<app> dist/<app>-darwin-arm64
   zig build -Dtarget=x86_64-macos -Doptimize=ReleaseSafe && cp zig-out/bin/<app> dist/<app>-darwin-amd64
   zig build -Dtarget=x86_64-linux -Doptimize=ReleaseSafe && cp zig-out/bin/<app> dist/<app>-linux-amd64
   zig build -Dtarget=aarch64-linux -Doptimize=ReleaseSafe && cp zig-out/bin/<app> dist/<app>-linux-arm64
   zig build -Dtarget=x86_64-windows -Doptimize=ReleaseSafe && cp zig-out/bin/<app>.exe dist/<app>-windows-amd64.exe
   zig build -Dtarget=aarch64-windows -Doptimize=ReleaseSafe && cp zig-out/bin/<app>.exe dist/<app>-windows-arm64.exe
   ```

3. **Generate checksums**:
   ```bash
   cd dist && shasum -a 256 <app>-* > checksums.txt
   ```

4. **Report** — list binaries with sizes.

---

## Zig 0.15.2+ Critical Patterns

These are non-obvious and will cause compilation failures if done wrong:

1. **stdout/stderr** — `std.fs.File.stdout()`, not `std.io.getStdOut()` (removed in 0.15)
2. **ArrayList** — Unmanaged: `var list: std.ArrayList(u8) = .{};` then pass allocator to each method
3. **Formatted output** — `std.fmt.allocPrint(allocator, fmt, args)` then `File.stdout().writeAll(msg)`
4. **JSON serialization** — `std.json.fmt(value, .{.whitespace = .indent_2})` with `std.fmt.allocPrint("{f}", .{...})`
5. **JSON parsing** — `std.json.parseFromSlice(T, allocator, content, .{.ignore_unknown_fields = true, .allocate = .alloc_always})`
6. **HTTP client** — `std.http.Client.fetch()` with `std.Io.Writer.Allocating`. No `.open()` method.
7. **Table rows in loops** — heap-allocate: `const row = try allocator.alloc([]const u8, n);`
8. **main signature** — `pub fn main() !void`
9. **Allocator** — `std.heap.page_allocator` for CLI processes
10. **Config path (cross-platform)** — use `std.process.getEnvVarOwned(allocator, "HOME")` not `std.posix.getenv("HOME")`. `std.posix.getenv` is not available on Windows.

## Help System Design

Every command must have comprehensive help text in `src/help.zig` designed to be read by AI coding agents:

- Usage line with exact syntax
- All flags with types and descriptions
- All positional arguments
- Behavior notes (defaults, side effects)
- Exit codes
- Examples

$ARGUMENTS
