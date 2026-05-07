---
name: bootstrap-go-cli
description: >
  Bootstrap a Go CLI application with Cobra, Viper config, slog structured logging, justfile,
  and goreleaser. Use when the user says "bootstrap go cli", "new go cli", "create a cli app
  in go", "go cobra app", "scaffold go command line", or wants to start a new Go CLI project
  from scratch.
---

# Bootstrap Go CLI

Scaffold a production-ready Go CLI application using Cobra + Viper + slog.

## Gather Input

Ask the user for:

1. **App name** — binary/project name (lowercase, hyphen-separated, e.g. `my-tool`)
2. **Module path** — Go module path (e.g. `github.com/user/my-tool`)
3. **Subcommands** — initial subcommands to scaffold (e.g. `serve`, `init`, `sync`)

Derive `ENV_PREFIX` from app name: uppercase, hyphens replaced with underscores (e.g. `my-tool` → `MY_TOOL`).

## Generate Project

Read [references/templates.md](references/templates.md) for all file templates.

Create files in this order:

### 1. Initialize Go module

```bash
mkdir -p <app-name>/cmd
cd <app-name>
go mod init <module-path>
```

### 2. Create files from templates

Apply placeholder substitution (`{{APP_NAME}}`, `{{MODULE_PATH}}`, `{{ENV_PREFIX}}`) to each template:

| File | Template |
|------|----------|
| `main.go` | main.go template |
| `cmd/root.go` | cmd/root.go template |
| `cmd/<subcmd>.go` | subcommand template (one per requested subcommand) |
| `.gitignore` | .gitignore template |
| `.goreleaser.yaml` | .goreleaser.yaml template |
| `justfile` | justfile template |

### 3. Install dependencies

```bash
go get github.com/spf13/cobra@latest
go get github.com/spf13/viper@latest
go mod tidy
```

### 4. Initialize git and verify

```bash
git init
go build ./...
```

## Output

After generation, print a summary:

```
Created <app-name>/ with:
  main.go              — entry point with version/commit/date ldflags
  cmd/root.go          — root command with Viper config + slog logging
  cmd/<subcmd>.go      — subcommand stubs (one per requested command)
  .goreleaser.yaml     — cross-platform release config
  justfile             — build/test/lint/release recipes
  .gitignore           — Go + editor + OS ignores

Run it:
  cd <app-name> && just run --help

Next steps:
  - Implement subcommand logic in cmd/*.go
  - Add config options via Viper (flags, env vars, or .yaml file)
  - Run `just test` to verify, `just snapshot` to test releases
```
