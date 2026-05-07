# Zig CLI Templates

All templates use placeholders: `{{APP_NAME}}`, `{{DESCRIPTION}}`.

Replace with actual values from user input.

Reference implementation: `/Users/tbrewer/projects/goodway/henry/cli-zig/`

## build.zig

```zig
const std = @import("std");
const build_zon = @import("build.zig.zon");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "{{APP_NAME}}",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const options = b.addOptions();
    options.addOption([]const u8, "version", build_zon.version);
    exe.root_module.addOptions("config", options);

    b.installArtifact(exe);

    const run_step = b.step("run", "Run {{APP_NAME}}");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });
    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_exe_tests.step);
}
```

## build.zig.zon

```zig
.{
    .name = .{{APP_NAME}},
    .version = "0.1.0",
    .fingerprint = 0x0000000000000000, // Will be corrected on first build
    .minimum_zig_version = "0.15.2",
    .dependencies = .{},
    .paths = .{
        "build.zig",
        "build.zig.zon",
        "src",
    },
}
```

NOTE: The fingerprint `0x0000000000000000` is a placeholder. On first `zig build`, the compiler
will error with the correct fingerprint. Replace it with the suggested value.

## src/main.zig

Entry point with command routing and shared arg parsing helpers.

```zig
const std = @import("std");
const config = @import("config");
const help = @import("help.zig");
// Import command modules here:
// const my_cmd = @import("commands/my_cmd.zig");

const File = std.fs.File;

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        try File.stderr().writeAll(help.root_help);
        std.process.exit(1);
    }

    const cmd = args[1];

    if (std.mem.eql(u8, cmd, "help") or std.mem.eql(u8, cmd, "--help") or std.mem.eql(u8, cmd, "-h")) {
        if (args.len >= 3) {
            try dispatchHelp(args[2..]);
        } else {
            try File.stdout().writeAll(help.root_help);
        }
        return;
    }
    if (std.mem.eql(u8, cmd, "--version") or std.mem.eql(u8, cmd, "-v")) {
        try File.stdout().writeAll("{{APP_NAME}} " ++ config.version ++ "\n");
        return;
    }

    // Check for trailing --help on any command
    if (args.len >= 3 and (std.mem.eql(u8, args[args.len - 1], "--help") or std.mem.eql(u8, args[args.len - 1], "-h"))) {
        try dispatchHelp(args[1 .. args.len - 1]);
        return;
    }

    // === ADD COMMAND ROUTING HERE ===
    // Example:
    // if (std.mem.eql(u8, cmd, "sync")) {
    //     try sync.run(allocator, args[2..]);
    // } else
    {
        try writeErr(allocator, "Unknown command: {s}\n\n", .{cmd});
        try File.stderr().writeAll(help.root_help);
        std.process.exit(1);
    }
}

fn dispatchHelp(args: []const []const u8) !void {
    if (args.len == 0) {
        try File.stdout().writeAll(help.root_help);
        return;
    }
    // === ADD HELP DISPATCH HERE ===
    // Example:
    // const cmd = args[0];
    // if (std.mem.eql(u8, cmd, "sync")) {
    //     return File.stdout().writeAll(help.sync_help);
    // }
    try File.stdout().writeAll(help.root_help);
}

// --- Output helpers ---

pub fn writeOut(allocator: std.mem.Allocator, comptime fmt: []const u8, args: anytype) !void {
    const msg = try std.fmt.allocPrint(allocator, fmt, args);
    defer allocator.free(msg);
    try File.stdout().writeAll(msg);
}

pub fn writeErr(allocator: std.mem.Allocator, comptime fmt: []const u8, args: anytype) !void {
    const msg = try std.fmt.allocPrint(allocator, fmt, args);
    defer allocator.free(msg);
    try File.stderr().writeAll(msg);
}

// --- Arg parsing helpers ---

pub fn getFlag(args: []const []const u8, name: []const u8) ?[]const u8 {
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.startsWith(u8, arg, name)) {
            if (arg.len > name.len and arg[name.len] == '=') {
                return arg[name.len + 1 ..];
            }
            if (std.mem.eql(u8, arg, name)) {
                if (i + 1 < args.len) return args[i + 1];
            }
        }
    }
    return null;
}

pub fn hasFlag(args: []const []const u8, name: []const u8) bool {
    for (args) |arg| {
        if (std.mem.eql(u8, arg, name)) return true;
    }
    return false;
}

pub fn getPositional(args: []const []const u8) ?[]const u8 {
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.startsWith(u8, arg, "--")) {
            if (std.mem.indexOf(u8, arg, "=") == null) i += 1;
            continue;
        }
        if (std.mem.startsWith(u8, arg, "-")) continue;
        return arg;
    }
    return null;
}

test "getFlag" {
    const a = &[_][]const u8{ "--env", "dev", "--url", "http://localhost" };
    try std.testing.expectEqualStrings("dev", getFlag(a, "--env").?);
    try std.testing.expect(getFlag(a, "--missing") == null);
}

test "getFlag with equals" {
    const a = &[_][]const u8{"--env=prod"};
    try std.testing.expectEqualStrings("prod", getFlag(a, "--env").?);
}

test "hasFlag" {
    const a = &[_][]const u8{ "--json", "--env", "dev" };
    try std.testing.expect(hasFlag(a, "--json"));
    try std.testing.expect(!hasFlag(a, "--force"));
}

test "getPositional" {
    const a = &[_][]const u8{ "--env", "dev", "42" };
    try std.testing.expectEqualStrings("42", getPositional(a).?);
}
```

## src/help.zig

Comprehensive help text for all commands. AI agents read this to discover the CLI's capabilities.

```zig
// Comprehensive help text for all commands and subcommands.
// Designed to be machine-readable by AI coding agents — every flag,
// argument, and behavior is documented in plain text.
//
// IMPORTANT: When adding a new command, you must:
// 1. Add a help constant here (e.g. pub const my_cmd_help)
// 2. Update root_help to list the new command
// 3. Add dispatch in main.zig dispatchHelp()

pub const root_help =
    \\{{APP_NAME}} — {{DESCRIPTION}}
    \\
    \\Usage:
    \\  {{APP_NAME}} <command> [options]
    \\  {{APP_NAME}} help <command>
    \\
    \\Commands:
    \\  help         Show help for any command
    \\
    \\Global Options:
    \\  --help, -h       Show help for the current command
    \\  --version, -v    Print version and exit
    \\
    \\Run '{{APP_NAME}} help <command>' for details on a specific command.
    \\
;

// === ADD COMMAND HELP CONSTANTS HERE ===
// Example:
// pub const sync_help =
//     \\{{APP_NAME}} sync — Synchronize data from remote source.
//     \\
//     \\Usage:
//     \\  {{APP_NAME}} sync [--env <name>] [--dry-run]
//     \\
//     \\Options:
//     \\  --env <name>    Environment to sync from
//     \\  --dry-run       Preview changes without applying
//     \\
//     \\Examples:
//     \\  {{APP_NAME}} sync
//     \\  {{APP_NAME}} sync --env production --dry-run
//     \\
// ;
```

## Subcommand template

For each user-requested command, create `src/commands/{{SUBCMD_NAME}}.zig`:

```zig
const std = @import("std");
const main_mod = @import("../main.zig");

const File = std.fs.File;

pub fn run(allocator: std.mem.Allocator, args: []const []const u8) !void {
    _ = args;
    try main_mod.writeOut(allocator, "TODO: implement {{SUBCMD_NAME}}\n", .{});
}
```

## src/config.zig (optional — only if config needed)

Per-environment config stored at `~/.{{APP_NAME}}.json` on macOS/Linux and
`%USERPROFILE%\.{{APP_NAME}}.json` on Windows.

```zig
const std = @import("std");
const builtin = @import("builtin");

pub const EnvEntry = struct {
    name: []const u8,
    base_url: ?[]const u8 = null,
    api_key: ?[]const u8 = null,
};

pub const Config = struct {
    default_env: ?[]const u8 = null,
    environments: ?[]const EnvEntry = null,
};

const config_filename = ".{{APP_NAME}}.json";

pub fn configPath(allocator: std.mem.Allocator) ![]const u8 {
    const home = if (builtin.os.tag == .windows)
        std.posix.getenv("USERPROFILE") orelse std.posix.getenv("HOME") orelse return error.NoHomeDir
    else
        std.posix.getenv("HOME") orelse return error.NoHomeDir;
    const sep: []const u8 = if (builtin.os.tag == .windows) "\\" else "/";
    return std.fmt.allocPrint(allocator, "{s}{s}{s}", .{ home, sep, config_filename });
}

pub fn load(allocator: std.mem.Allocator) !Config {
    const path = try configPath(allocator);
    defer allocator.free(path);

    const file = std.fs.openFileAbsolute(path, .{}) catch |err| switch (err) {
        error.FileNotFound => return Config{},
        else => return err,
    };
    defer file.close();

    const stat = try file.stat();
    if (stat.size == 0) return Config{};

    const content = try file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(content);

    const parsed = try std.json.parseFromSlice(Config, allocator, content, .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    });
    return parsed.value;
}

pub fn save(allocator: std.mem.Allocator, cfg: Config) !void {
    const path = try configPath(allocator);
    defer allocator.free(path);

    const json_str = try std.fmt.allocPrint(allocator, "{f}", .{std.json.fmt(cfg, .{ .whitespace = .indent_2 })});
    defer allocator.free(json_str);

    const file = try std.fs.createFileAbsolute(path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(json_str);
}

pub fn getEnv(cfg: Config, name: ?[]const u8) ?EnvEntry {
    const env_name = name orelse cfg.default_env orelse return null;
    const envs = cfg.environments orelse return null;
    for (envs) |entry| {
        if (std.mem.eql(u8, entry.name, env_name)) return entry;
    }
    return null;
}

pub fn setEnv(allocator: std.mem.Allocator, cfg: *Config, name: []const u8, base_url: ?[]const u8, api_key: ?[]const u8) !void {
    var envs: std.ArrayList(EnvEntry) = .{};

    if (cfg.environments) |existing| {
        for (existing) |entry| {
            if (std.mem.eql(u8, entry.name, name)) {
                try envs.append(allocator, .{
                    .name = try allocator.dupe(u8, name),
                    .base_url = if (base_url) |u| try allocator.dupe(u8, u) else entry.base_url,
                    .api_key = if (api_key) |k| try allocator.dupe(u8, k) else entry.api_key,
                });
            } else {
                try envs.append(allocator, entry);
            }
        }
    }

    var found = false;
    if (cfg.environments) |existing| {
        for (existing) |entry| {
            if (std.mem.eql(u8, entry.name, name)) { found = true; break; }
        }
    }
    if (!found) {
        try envs.append(allocator, .{
            .name = try allocator.dupe(u8, name),
            .base_url = if (base_url) |u| try allocator.dupe(u8, u) else null,
            .api_key = if (api_key) |k| try allocator.dupe(u8, k) else null,
        });
    }

    cfg.environments = envs.items;
    if (cfg.default_env == null) cfg.default_env = try allocator.dupe(u8, name);
}

pub fn maskKey(allocator: std.mem.Allocator, key: []const u8) ![]const u8 {
    if (key.len <= 8) return "****";
    return std.fmt.allocPrint(allocator, "{s}****{s}", .{ key[0..4], key[key.len - 4 ..] });
}
```

## src/generated.zig (optional — only if API client needed)

Combined types + HTTP client. When the user has an OpenAPI spec, seed this file with
`openapi2zig generate` then manually fix for Zig 0.15.2. When no spec exists, write
types and client by hand following this pattern.

Reference implementation: `/Users/tbrewer/projects/goodway/henry/cli-zig/src/generated.zig`

```zig
///////////////////////////////////////////
// Generated from OpenAPI spec via openapi2zig, then fixed for Zig 0.15.2.
// Regenerate types: openapi2zig generate -i <spec-path> -o src/generated.zig
// Then manually fix nested types and client functions.
///////////////////////////////////////////

const std = @import("std");

// --- Models ---
// Define structs matching API response shapes.
// Use ?T for optional fields, []const T for arrays.
// Nested objects must be their own struct type (NOT []const u8).

pub const Item = struct {
    id: ?i64 = null,
    name: ?[]const u8 = null,
    // Add fields matching your API schema
};

pub const ListResponse = struct {
    data: []const Item,
};

pub const DetailResponse = struct {
    data: Item,
};

// --- API Client ---

pub const Client = struct {
    allocator: std.mem.Allocator,
    base_url: []const u8,
    api_key: []const u8,

    pub fn init(allocator: std.mem.Allocator, base_url: []const u8, api_key: []const u8) Client {
        return .{ .allocator = allocator, .base_url = base_url, .api_key = api_key };
    }

    pub const RawResponse = struct {
        status: std.http.Status,
        body: []const u8,
    };

    // Named methods map 1:1 to REST endpoints.
    // Add one method per endpoint your CLI needs.

    /// GET /api/v1/items
    pub fn listItems(self: *const Client) !RawResponse {
        return self.request(.GET, "/api/v1/items", null);
    }

    /// GET /api/v1/items/{id}
    pub fn getItem(self: *const Client, id: []const u8) !RawResponse {
        const path = try std.fmt.allocPrint(self.allocator, "/api/v1/items/{s}", .{id});
        defer self.allocator.free(path);
        return self.request(.GET, path, null);
    }

    /// POST /api/v1/items
    pub fn createItem(self: *const Client, body: []const u8) !RawResponse {
        return self.request(.POST, "/api/v1/items", body);
    }

    /// PUT /api/v1/items/{id}
    pub fn updateItem(self: *const Client, id: []const u8, body: []const u8) !RawResponse {
        const path = try std.fmt.allocPrint(self.allocator, "/api/v1/items/{s}", .{id});
        defer self.allocator.free(path);
        return self.request(.PUT, path, body);
    }

    /// DELETE /api/v1/items/{id}
    pub fn deleteItem(self: *const Client, id: []const u8) !RawResponse {
        const path = try std.fmt.allocPrint(self.allocator, "/api/v1/items/{s}", .{id});
        defer self.allocator.free(path);
        return self.request(.DELETE, path, null);
    }

    fn request(self: *const Client, method: std.http.Method, path: []const u8, body: ?[]const u8) !RawResponse {
        const url = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ self.base_url, path });
        defer self.allocator.free(url);

        const auth_header = try std.fmt.allocPrint(self.allocator, "Bearer {s}", .{self.api_key});
        defer self.allocator.free(auth_header);

        var http_client: std.http.Client = .{ .allocator = self.allocator };
        defer http_client.deinit();

        var aw: std.Io.Writer.Allocating = .init(self.allocator);
        defer aw.deinit();

        const result = try http_client.fetch(.{
            .location = .{ .url = url },
            .method = method,
            .payload = body,
            .response_writer = &aw.writer,
            .extra_headers = &.{
                .{ .name = "Authorization", .value = auth_header },
                .{ .name = "Content-Type", .value = "application/json" },
            },
            .headers = .{ .accept_encoding = .omit },
        });

        var al = aw.toArrayList();
        const response_body = try al.toOwnedSlice(self.allocator);
        return .{ .status = result.status, .body = response_body };
    }
};
```

### openapi2zig workflow

When the user has an OpenAPI spec:

1. Install: `curl -fsSL https://christianhelle.com/openapi2zig/install | INSTALL_DIR="$HOME/.local/bin" bash`
2. Generate: `~/.local/bin/openapi2zig generate -i <spec.json> -o src/generated.zig`
3. Fix the output (it won't compile as-is on Zig 0.15.2):
   - Replace dotted function names (`Namespace.Controller.action`) with valid identifiers (`listItems`)
   - Fix nested types: `hero: ?[]const u8` → `hero: ?Hero` with proper struct definitions
   - Replace `std.http.Client.init(allocator)` → `std.http.Client{ .allocator = allocator }`
   - Replace `std.ArrayList(u8).init(allocator)` → `var list: std.ArrayList(u8) = .{};`
   - Replace `std.json.stringify(...)` → `std.json.fmt(...)` with `std.fmt.allocPrint`
   - Add `Client` struct with `base_url`, `api_key`, Bearer auth, and `fetch()` pattern
   - Change return types from `!void` to `!RawResponse`
4. Commands import `generated.zig` for both types and client:
   ```zig
   const gen = @import("../generated.zig");
   const client = gen.Client.init(allocator, base_url, api_key);
   const resp = try client.listItems();
   ```

## src/table.zig (optional — only if table output needed)

Column-aligned table printer.

```zig
const std = @import("std");

pub const Table = struct {
    headers: []const []const u8,
    rows: std.ArrayList([]const []const u8),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, headers: []const []const u8) Table {
        return .{ .headers = headers, .rows = .{}, .allocator = allocator };
    }

    pub fn addRow(self: *Table, row: []const []const u8) !void {
        try self.rows.append(self.allocator, row);
    }

    pub fn render(self: *const Table) ![]const u8 {
        const allocator = self.allocator;
        var widths = try allocator.alloc(usize, self.headers.len);
        defer allocator.free(widths);

        for (self.headers, 0..) |h, i| widths[i] = h.len;
        for (self.rows.items) |row| {
            for (row, 0..) |cell, i| {
                if (i < widths.len and cell.len > widths[i]) widths[i] = cell.len;
            }
        }

        var buf: std.ArrayList(u8) = .{};
        for (self.headers, 0..) |h, i| {
            try buf.appendSlice(allocator, h);
            if (i < self.headers.len - 1) try buf.appendNTimes(allocator, ' ', widths[i] - h.len + 2);
        }
        try buf.append(allocator, '\n');

        for (self.rows.items) |row| {
            for (row, 0..) |cell, i| {
                try buf.appendSlice(allocator, cell);
                if (i < row.len - 1) {
                    const w = if (i < widths.len) widths[i] else cell.len;
                    try buf.appendNTimes(allocator, ' ', w - cell.len + 2);
                }
            }
            try buf.append(allocator, '\n');
        }
        return try buf.toOwnedSlice(allocator);
    }
};
```

IMPORTANT: When using Table in a loop, heap-allocate rows:
```zig
// WRONG — stack pointer reused each iteration, all rows show last value:
for (items) |item| {
    try tbl.addRow(&.{ item.name, item.value });
}

// CORRECT — heap-allocated, each row has its own memory:
for (items) |item| {
    const row = try allocator.alloc([]const u8, 2);
    row[0] = item.name;
    row[1] = item.value;
    try tbl.addRow(row);
}
```

## justfile

```just
# {{APP_NAME}} build recipes

version := `grep '\.version' build.zig.zon | head -1 | sed 's/.*"\(.*\)".*/\1/'`
dist := "dist"

# Build debug binary
build:
    zig build

# Build release binary (native platform)
release:
    zig build -Doptimize=ReleaseSafe

# Bump version in build.zig.zon (major, minor, or patch)
bump part="patch":
    #!/usr/bin/env sh
    IFS='.' read -r major minor patch <<< "{{version}}"
    case "{{part}}" in
        major) major=$((major + 1)); minor=0; patch=0 ;;
        minor) minor=$((minor + 1)); patch=0 ;;
        patch) patch=$((patch + 1)) ;;
        *) echo "Error: use 'major', 'minor', or 'patch'" >&2; exit 1 ;;
    esac
    new="${major}.${minor}.${patch}"
    sed -i '' "s/\.version = \"{{version}}\"/\.version = \"${new}\"/" build.zig.zon
    echo "{{version}} → ${new}"

# Build, checksum, tag, and publish a GitHub release
publish: test dist checksums
    git tag -a "v{{version}}" -m "v{{version}}"
    git push origin "v{{version}}"
    gh release create "v{{version}}" {{dist}}/* --title "v{{version}}" --generate-notes

# Run with arguments
run *ARGS:
    zig build run -- {{ARGS}}

# Run tests
test:
    zig build test

# Build release binaries for all supported platforms into dist/
dist: clean-dist
    mkdir -p {{dist}}
    @echo "Building darwin-arm64..."
    zig build -Dtarget=aarch64-macos -Doptimize=ReleaseSafe
    cp zig-out/bin/{{APP_NAME}} {{dist}}/{{APP_NAME}}-darwin-arm64
    @echo "Building darwin-amd64..."
    zig build -Dtarget=x86_64-macos -Doptimize=ReleaseSafe
    cp zig-out/bin/{{APP_NAME}} {{dist}}/{{APP_NAME}}-darwin-amd64
    @echo "Building linux-amd64..."
    zig build -Dtarget=x86_64-linux -Doptimize=ReleaseSafe
    cp zig-out/bin/{{APP_NAME}} {{dist}}/{{APP_NAME}}-linux-amd64
    @echo "Building linux-arm64..."
    zig build -Dtarget=aarch64-linux -Doptimize=ReleaseSafe
    cp zig-out/bin/{{APP_NAME}} {{dist}}/{{APP_NAME}}-linux-arm64
    @echo "Building windows-amd64..."
    zig build -Dtarget=x86_64-windows -Doptimize=ReleaseSafe
    cp zig-out/bin/{{APP_NAME}}.exe {{dist}}/{{APP_NAME}}-windows-amd64.exe
    @echo "Building windows-arm64..."
    zig build -Dtarget=aarch64-windows -Doptimize=ReleaseSafe
    cp zig-out/bin/{{APP_NAME}}.exe {{dist}}/{{APP_NAME}}-windows-arm64.exe
    @echo "Done. Binaries in {{dist}}/"
    ls -lh {{dist}}/

# Generate checksums for dist binaries
checksums:
    cd {{dist}} && shasum -a 256 {{APP_NAME}}-* > checksums.txt
    cat {{dist}}/checksums.txt

# Clean build artifacts
clean:
    rm -rf zig-out .zig-cache

# Clean dist directory
clean-dist:
    rm -rf {{dist}}

# Clean everything
clean-all: clean clean-dist
```

## install.sh

macOS/Linux installer. Redirects Windows (MSYS/MinGW/Cygwin) users to install.ps1.

```bash
#!/bin/sh
# Install {{APP_NAME}} CLI on macOS/Linux.
set -e

VERSION="${{{APP_NAME_UPPER}}_VERSION:-latest}"
INSTALL_DIR="${{{APP_NAME_UPPER}}_INSTALL_DIR:-$HOME/.local/bin}"
BASE_URL="${{{APP_NAME_UPPER}}_BASE_URL:-https://github.com/OWNER/REPO/releases/download}"

OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"

case "$ARCH" in
    x86_64|amd64)  ARCH="amd64" ;;
    aarch64|arm64)  ARCH="arm64" ;;
    *)  echo "Error: unsupported architecture: $ARCH" >&2; exit 1 ;;
esac

case "$OS" in
    darwin|linux) ;;
    msys*|mingw*|cygwin*)
        echo "Error: use install.ps1 for native Windows installs" >&2
        exit 1
        ;;
    *)  echo "Error: unsupported OS: $OS" >&2; exit 1 ;;
esac

BINARY="{{APP_NAME}}-${OS}-${ARCH}"

if [ "$VERSION" = "latest" ]; then
    URL="${BASE_URL}/latest/download/${BINARY}"
else
    URL="${BASE_URL}/v${VERSION}/${BINARY}"
fi

echo "Downloading {{APP_NAME}} for ${OS}/${ARCH}..."

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

if command -v curl >/dev/null 2>&1; then
    curl -fsSL -o "${TMPDIR}/{{APP_NAME}}" "$URL"
elif command -v wget >/dev/null 2>&1; then
    wget -q -O "${TMPDIR}/{{APP_NAME}}" "$URL"
else
    echo "Error: curl or wget is required" >&2; exit 1
fi

chmod +x "${TMPDIR}/{{APP_NAME}}"

mkdir -p "$INSTALL_DIR"
mv "${TMPDIR}/{{APP_NAME}}" "${INSTALL_DIR}/{{APP_NAME}}"

echo "{{APP_NAME}} installed to ${INSTALL_DIR}/{{APP_NAME}}"

case ":$PATH:" in
    *":${INSTALL_DIR}:"*) ;;
    *) echo "NOTE: Add ${INSTALL_DIR} to your PATH:"; echo "  export PATH=\"${INSTALL_DIR}:\$PATH\"" ;;
esac

"${INSTALL_DIR}/{{APP_NAME}}" --version
```

NOTE: Replace `OWNER/REPO` in BASE_URL with the actual GitHub repository path.
`{{APP_NAME_UPPER}}` is `{{APP_NAME}}` uppercased with hyphens replaced by underscores.

## install.ps1

Windows PowerShell installer.

```powershell
# Install {{APP_NAME}} CLI on Windows.
# Usage: irm https://raw.githubusercontent.com/OWNER/REPO/main/install.ps1 | iex

$ErrorActionPreference = "Stop"

$Version = if ($env:{{APP_NAME_UPPER}}_VERSION) { $env:{{APP_NAME_UPPER}}_VERSION } else { "latest" }
$InstallDir = if ($env:{{APP_NAME_UPPER}}_INSTALL_DIR) { $env:{{APP_NAME_UPPER}}_INSTALL_DIR } else { "$env:LOCALAPPDATA\{{APP_NAME}}" }
$BaseUrl = if ($env:{{APP_NAME_UPPER}}_BASE_URL) { $env:{{APP_NAME_UPPER}}_BASE_URL } else { "https://github.com/OWNER/REPO/releases/download" }

$Arch = if ([Environment]::Is64BitOperatingSystem) {
    if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") { "arm64" } else { "amd64" }
} else {
    Write-Error "32-bit Windows is not supported"; exit 1
}

$Binary = "{{APP_NAME}}-windows-${Arch}.exe"

if ($Version -eq "latest") {
    $Url = "${BaseUrl}/latest/download/${Binary}"
} else {
    $Url = "${BaseUrl}/v${Version}/${Binary}"
}

Write-Host "Downloading {{APP_NAME}} for windows/${Arch}..."

if (-not (Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
}

$OutFile = Join-Path $InstallDir "{{APP_NAME}}.exe"
Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing

# Add to PATH if not already there
$UserPath = [Environment]::GetEnvironmentVariable("PATH", "User")
if ($UserPath -notlike "*$InstallDir*") {
    [Environment]::SetEnvironmentVariable("PATH", "$UserPath;$InstallDir", "User")
    $env:PATH = "$env:PATH;$InstallDir"
    Write-Host "Added $InstallDir to PATH"
}

Write-Host "{{APP_NAME}} installed to $OutFile"
& $OutFile --version
```

NOTE: Replace `OWNER/REPO` in BaseUrl and the irm URL with the actual GitHub repository path.
`{{APP_NAME_UPPER}}` is `{{APP_NAME}}` uppercased with hyphens replaced by underscores.

## .gitignore

```
zig-out/
.zig-cache/
dist/
*.o
*.d
```

## CLAUDE.md

```markdown
# CLAUDE.md — {{APP_NAME}}

## What This Is

{{DESCRIPTION}}. Built in Zig with zero external dependencies. Single static binary (~1MB).

## Commands

zig build                  # Build debug binary
zig build test             # Run tests
zig build run -- <args>    # Build and run
just release               # Build optimized native binary
just dist                  # Cross-compile all 6 platform binaries

## Project Structure

src/
  main.zig              # CLI entry point, arg parsing, command routing
  help.zig              # All help text (agent-readable, one const per command)
  config.zig            # Per-environment config (~/.{{APP_NAME}}.json, Windows: %USERPROFILE%\.{{APP_NAME}}.json)
  commands/              # Command implementations

## Adding a New Command

When adding a new command, you MUST update THREE files:

1. **src/main.zig** — Add routing in `main()` and `dispatchHelp()`
2. **src/help.zig** — Add a help constant with usage, flags, arguments, behavior, exit codes, and examples. Also update root_help to list the new command.
3. **src/commands/<name>.zig** — Implementation

## API Client (generated.zig) — if applicable

Types and client live in `src/generated.zig`. If seeded from an OpenAPI spec:

Regenerate after API changes:
  ~/.local/bin/openapi2zig generate -i <spec-path> -o src/generated.zig
  # Then manually fix nested types, function names, and Zig 0.15.2 API calls

The client uses named methods (e.g. `listItems`, `getItem`, `createItem`) that map
1:1 to REST endpoints. Commands import via `const gen = @import("../generated.zig");`.

## Zig 0.15.2 Gotchas

## Version Management

Version is defined once in `build.zig.zon` and derived everywhere else:
- `build.zig` reads it via `@import("build.zig.zon")` and passes it as a comptime build option
- `src/main.zig` imports it via `@import("config").version`
- `justfile` extracts it with `grep | head -1 | sed`

To bump: `just bump` (patch), `just bump minor`, or `just bump major`.
To release: `just publish` (runs tests, builds all platforms, tags, pushes, creates GitHub release).

## Zig 0.15.2 Gotchas

- No `std.io.getStdOut()` — Use `std.fs.File.stdout()`
- No `ArrayList.init(allocator)` — Use `var list: std.ArrayList(u8) = .{};` + pass allocator to methods
- No `std.json.stringify` — Use `std.json.fmt()` with `std.fmt.allocPrint("{f}", .{...})`
- Table rows in loops must be heap-allocated (not `&.{...}`)
- Use `std.heap.page_allocator` for CLI processes
```
