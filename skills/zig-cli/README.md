# Zig CLI

Build and maintain production-ready Zig CLI applications with zero dependencies and cross-compilation.

## Install

Install this skill globally:

```bash
npx skills add agoodway/GoodSkills --skill zig-cli -g
```

Install into the current project:

```bash
npx skills add agoodway/GoodSkills --skill zig-cli
```

## Usage

```
/zig-cli help
```

## Subcommands

| Subcommand | Purpose |
|------------|---------|
| `bootstrap` | Scaffold a new Zig CLI project from scratch |
| `openapi-update` | Regenerate the API client from an OpenAPI spec |
| `add-command <name>` | Add a new subcommand to an existing Zig CLI |
| `dist` | Cross-compile release binaries for all platforms |
