# Go CLI Templates

All templates use placeholders: `{{APP_NAME}}`, `{{MODULE_PATH}}`, `{{ENV_PREFIX}}`.

Replace with actual values detected from user input. `{{ENV_PREFIX}}` is `{{APP_NAME}}` uppercased.

## main.go

```go
package main

import "{{MODULE_PATH}}/cmd"

var (
	Version = "0.1.0"
	Commit  = "dev"
	Date    = "unknown"
)

func main() {
	cmd.Version = Version
	cmd.Commit = Commit
	cmd.Date = Date
	cmd.Execute()
}
```

## cmd/root.go

```go
package cmd

import (
	"fmt"
	"log/slog"
	"os"

	"github.com/spf13/cobra"
	"github.com/spf13/viper"
)

var (
	Version string
	Commit  string
	Date    string

	cfgFile string
	verbose bool
	logJSON bool
	logger  *slog.Logger
)

var rootCmd = &cobra.Command{
	Use:   "{{APP_NAME}}",
	Short: "{{APP_NAME}} - a CLI application",
	Long:  `{{APP_NAME}} is a CLI application built with Cobra.`,
	PersistentPreRun: func(cmd *cobra.Command, args []string) {
		level := slog.LevelInfo
		if verbose {
			level = slog.LevelDebug
		}
		opts := &slog.HandlerOptions{Level: level, AddSource: verbose}
		var handler slog.Handler
		if logJSON {
			handler = slog.NewJSONHandler(os.Stderr, opts)
		} else {
			handler = slog.NewTextHandler(os.Stderr, opts)
		}
		logger = slog.New(handler)
		slog.SetDefault(logger)
	},
}

func Execute() {
	rootCmd.Version = fmt.Sprintf("%s (commit: %s, built: %s)", Version, Commit, Date)
	if err := rootCmd.Execute(); err != nil {
		os.Exit(1)
	}
}

func init() {
	cobra.OnInitialize(initConfig)

	rootCmd.PersistentFlags().StringVar(&cfgFile, "config", "", "config file (default $HOME/.{{APP_NAME}}.yaml)")
	rootCmd.PersistentFlags().BoolVarP(&verbose, "verbose", "v", false, "enable debug logging")
	rootCmd.PersistentFlags().BoolVar(&logJSON, "log-json", false, "output logs as JSON")

	viper.BindPFlag("verbose", rootCmd.PersistentFlags().Lookup("verbose"))
}

func initConfig() {
	if cfgFile != "" {
		viper.SetConfigFile(cfgFile)
	} else {
		home, err := os.UserHomeDir()
		cobra.CheckErr(err)
		viper.AddConfigPath(home)
		viper.AddConfigPath(".")
		viper.SetConfigName(".{{APP_NAME}}")
		viper.SetConfigType("yaml")
	}

	viper.SetEnvPrefix("{{ENV_PREFIX}}")
	viper.AutomaticEnv()
	viper.ReadInConfig()
}
```

## cmd/example subcommand

Template for each user-requested subcommand:

```go
package cmd

import (
	"github.com/spf13/cobra"
)

var {{SUBCMD_NAME}}Cmd = &cobra.Command{
	Use:   "{{SUBCMD_NAME}}",
	Short: "TODO: describe {{SUBCMD_NAME}}",
	RunE: func(cmd *cobra.Command, args []string) error {
		logger.Info("running {{SUBCMD_NAME}}")
		// TODO: implement
		return nil
	},
}

func init() {
	rootCmd.AddCommand({{SUBCMD_NAME}}Cmd)
}
```

## .gitignore

```
# Binaries
/{{APP_NAME}}
/dist/
*.exe
*.exe~
*.dll
*.so
*.dylib

# Test
*.test
*.out
coverage.txt

# IDE
.idea/
.vscode/
*.swp
*.swo

# OS
.DS_Store
Thumbs.db

# Config (local overrides)
.{{APP_NAME}}.yaml
```

## .goreleaser.yaml

```yaml
version: 2

project_name: {{APP_NAME}}

before:
  hooks:
    - go mod tidy

builds:
  - main: .
    env:
      - CGO_ENABLED=0
    goos:
      - darwin
      - linux
      - windows
    goarch:
      - amd64
      - arm64
    ldflags:
      - -s -w
      - -X main.Version={{.Version}}
      - -X main.Commit={{.Commit}}
      - -X main.Date={{.Date}}

archives:
  - format: tar.gz
    format_overrides:
      - goos: windows
        format: zip
    name_template: "{{ .ProjectName }}_{{ .Version }}_{{ .Os }}_{{ .Arch }}"

checksum:
  name_template: checksums.txt
  algorithm: sha256

changelog:
  sort: asc
  filters:
    exclude:
      - "^docs:"
      - "^test:"
      - "^ci:"
```

## justfile

```just
# {{APP_NAME}} development commands

default:
    @just --list

# Build the binary
build:
    go build -o {{APP_NAME}} .

# Run the app (pass args after --)
run *ARGS:
    go run . {{ARGS}}

# Run tests
test:
    go test ./... -v

# Run tests with coverage
cover:
    go test ./... -coverprofile=coverage.txt -covermode=atomic
    go tool cover -html=coverage.txt -o coverage.html

# Lint (requires golangci-lint)
lint:
    golangci-lint run ./...

# Format code
fmt:
    gofmt -s -w .

# Tidy dependencies
tidy:
    go mod tidy

# Build snapshot release (requires goreleaser)
snapshot:
    goreleaser build --snapshot --clean

# Full release (requires goreleaser + git tag)
release:
    goreleaser release --clean

# Clean build artifacts
clean:
    rm -f {{APP_NAME}}
    rm -rf dist/
    rm -f coverage.txt coverage.html
```
