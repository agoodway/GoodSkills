# OpenAPI Client Templates

Placeholders: `{{CLIENT_PKG}}` (package name, e.g. `petstore`), `{{SPEC_PATH}}` (path to openapi spec), `{{APP_NAME}}`, `{{MODULE_PATH}}`.

## oapi-codegen config — client + models

File: `{{CLIENT_PKG}}/generate.yaml`

```yaml
# yaml-language-server: $schema=https://raw.githubusercontent.com/oapi-codegen/oapi-codegen/HEAD/configuration-schema.json
package: {{CLIENT_PKG}}
generate:
  client: true
  models: true
  embedded-spec: false
output: client.gen.go
```

## go:generate directive

Place in `{{CLIENT_PKG}}/generate.go`:

```go
package {{CLIENT_PKG}}

//go:generate go run github.com/oapi-codegen/oapi-codegen/v2/cmd/oapi-codegen@latest --config=generate.yaml {{SPEC_PATH}}
```

## internal/apiconfig/apiconfig.go

Per-environment config loader. Reads from the Viper config file.

```go
package apiconfig

import (
	"fmt"

	"github.com/spf13/viper"
)

// EnvConfig holds the connection settings for a single environment.
type EnvConfig struct {
	Name    string
	BaseURL string
	APIKey  string
}

// Load returns the config for the active environment.
// Precedence: --env flag > default_env in config file.
func Load(env string) (*EnvConfig, error) {
	if env == "" {
		env = viper.GetString("default_env")
	}
	if env == "" {
		return nil, fmt.Errorf("no environment specified and no default_env set; run: {{APP_NAME}} configure set --env <name> --base-url <url> --api-key <key>")
	}

	key := fmt.Sprintf("environments.%s", env)
	if !viper.IsSet(key) {
		return nil, fmt.Errorf("environment %q not configured; run: {{APP_NAME}} configure set --env %s --base-url <url> --api-key <key>", env, env)
	}

	return &EnvConfig{
		Name:    env,
		BaseURL: viper.GetString(key + ".base_url"),
		APIKey:  viper.GetString(key + ".api_key"),
	}, nil
}

// Set writes config for an environment to the Viper config file.
func Set(env, baseURL, apiKey string) error {
	key := fmt.Sprintf("environments.%s", env)
	if baseURL != "" {
		viper.Set(key+".base_url", baseURL)
	}
	if apiKey != "" {
		viper.Set(key+".api_key", apiKey)
	}

	// If no default_env is set yet, make this one the default
	if viper.GetString("default_env") == "" {
		viper.Set("default_env", env)
	}

	return viper.WriteConfig()
}

// SetDefault sets the default environment.
func SetDefault(env string) error {
	key := fmt.Sprintf("environments.%s", env)
	if !viper.IsSet(key) {
		return fmt.Errorf("environment %q not configured; set it first with configure set", env)
	}
	viper.Set("default_env", env)
	return viper.WriteConfig()
}

// List returns all configured environment names.
func List() []string {
	envs := viper.GetStringMap("environments")
	names := make([]string, 0, len(envs))
	for name := range envs {
		names = append(names, name)
	}
	return names
}
```

## cmd/configure.go

Cobra command with subcommands: `set`, `show`, `use`.

```go
package cmd

import (
	"fmt"
	"os"
	"text/tabwriter"

	"{{MODULE_PATH}}/internal/apiconfig"
	"github.com/spf13/cobra"
	"github.com/spf13/viper"
)

var configureCmd = &cobra.Command{
	Use:   "configure",
	Short: "Manage API environment configurations",
	Long:  `Set, view, and switch between API environments (base URL and API key).`,
}

var configSetCmd = &cobra.Command{
	Use:   "set",
	Short: "Set base URL and API key for an environment",
	Example: `  {{APP_NAME}} configure set --env production --base-url https://api.example.com --api-key sk-xxx
  {{APP_NAME}} configure set --env staging --base-url https://staging.api.example.com --api-key sk-yyy`,
	RunE: func(cmd *cobra.Command, args []string) error {
		env, _ := cmd.Flags().GetString("env")
		baseURL, _ := cmd.Flags().GetString("base-url")
		apiKey, _ := cmd.Flags().GetString("api-key")

		if env == "" {
			return fmt.Errorf("--env is required")
		}
		if baseURL == "" && apiKey == "" {
			return fmt.Errorf("at least one of --base-url or --api-key is required")
		}

		// Ensure config file exists before writing
		if err := ensureConfigFile(); err != nil {
			return err
		}

		if err := apiconfig.Set(env, baseURL, apiKey); err != nil {
			return fmt.Errorf("saving config: %w", err)
		}

		logger.Info("configuration saved", "env", env)
		return nil
	},
}

var configShowCmd = &cobra.Command{
	Use:   "show",
	Short: "Show all configured environments",
	RunE: func(cmd *cobra.Command, args []string) error {
		defaultEnv := viper.GetString("default_env")
		envNames := apiconfig.List()

		if len(envNames) == 0 {
			fmt.Println("No environments configured. Run: {{APP_NAME}} configure set --env <name> --base-url <url> --api-key <key>")
			return nil
		}

		w := tabwriter.NewWriter(os.Stdout, 0, 0, 2, ' ', 0)
		fmt.Fprintln(w, "ENV\tBASE URL\tAPI KEY\tDEFAULT")
		for _, name := range envNames {
			cfg, err := apiconfig.Load(name)
			if err != nil {
				continue
			}
			maskedKey := maskKey(cfg.APIKey)
			isDefault := ""
			if name == defaultEnv {
				isDefault = "*"
			}
			fmt.Fprintf(w, "%s\t%s\t%s\t%s\n", cfg.Name, cfg.BaseURL, maskedKey, isDefault)
		}
		w.Flush()
		return nil
	},
}

var configUseCmd = &cobra.Command{
	Use:   "use <environment>",
	Short: "Set the default environment",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		if err := ensureConfigFile(); err != nil {
			return err
		}
		if err := apiconfig.SetDefault(args[0]); err != nil {
			return err
		}
		logger.Info("default environment set", "env", args[0])
		return nil
	},
}

func init() {
	rootCmd.AddCommand(configureCmd)
	configureCmd.AddCommand(configSetCmd)
	configureCmd.AddCommand(configShowCmd)
	configureCmd.AddCommand(configUseCmd)

	configSetCmd.Flags().String("env", "", "environment name (e.g. production, staging)")
	configSetCmd.Flags().String("base-url", "", "API base URL")
	configSetCmd.Flags().String("api-key", "", "API key")
}

// ensureConfigFile creates the config file if it doesn't exist.
func ensureConfigFile() error {
	if viper.ConfigFileUsed() != "" {
		return nil
	}
	home, err := os.UserHomeDir()
	if err != nil {
		return err
	}
	cfgPath := home + "/.{{APP_NAME}}.yaml"
	if _, err := os.Stat(cfgPath); os.IsNotExist(err) {
		if err := os.WriteFile(cfgPath, []byte(""), 0600); err != nil {
			return fmt.Errorf("creating config file: %w", err)
		}
		viper.SetConfigFile(cfgPath)
		if err := viper.ReadInConfig(); err != nil {
			return err
		}
	}
	return nil
}

// maskKey shows first 4 and last 4 chars, masks the rest.
func maskKey(key string) string {
	if len(key) <= 8 {
		return "****"
	}
	return key[:4] + "****" + key[len(key)-4:]
}
```

## Config file format

Stored at `~/.{{APP_NAME}}.yaml`:

```yaml
default_env: production
environments:
  production:
    base_url: https://api.example.com
    api_key: sk-prod-xxxx
  staging:
    base_url: https://staging.api.example.com
    api_key: sk-stag-yyyy
```

## Example client usage

Shows how to use the generated client with the stored config:

```go
package example

import (
	"context"
	"fmt"
	"net/http"

	"{{MODULE_PATH}}/internal/apiconfig"
	"{{MODULE_PATH}}/{{CLIENT_PKG}}"
)

func Example(env string) error {
	cfg, err := apiconfig.Load(env)
	if err != nil {
		return err
	}

	// Create client with stored base URL and inject API key via request editor
	client, err := {{CLIENT_PKG}}.NewClientWithResponses(cfg.BaseURL,
		{{CLIENT_PKG}}.WithRequestEditorFn(func(ctx context.Context, req *http.Request) error {
			req.Header.Set("Authorization", "Bearer "+cfg.APIKey)
			return nil
		}),
	)
	if err != nil {
		return fmt.Errorf("creating client: %w", err)
	}

	resp, err := client.ListItemsWithResponse(context.Background())
	if err != nil {
		return fmt.Errorf("listing items: %w", err)
	}

	if resp.StatusCode() != http.StatusOK {
		return fmt.Errorf("unexpected status: %d", resp.StatusCode())
	}

	for _, item := range *resp.JSON200 {
		fmt.Println(item.Name)
	}
	return nil
}
```

## Separate config pattern (models + client split)

For larger APIs, split models and client into separate files:

### models config — `{{CLIENT_PKG}}/models.yaml`

```yaml
package: {{CLIENT_PKG}}
generate:
  models: true
output: models.gen.go
```

### client config — `{{CLIENT_PKG}}/client.yaml`

```yaml
package: {{CLIENT_PKG}}
generate:
  client: true
output: client.gen.go
```

### generate.go with both

```go
package {{CLIENT_PKG}}

//go:generate go run github.com/oapi-codegen/oapi-codegen/v2/cmd/oapi-codegen@latest --config=models.yaml {{SPEC_PATH}}
//go:generate go run github.com/oapi-codegen/oapi-codegen/v2/cmd/oapi-codegen@latest --config=client.yaml {{SPEC_PATH}}
```

## justfile recipes to add

If a `tidy` recipe already exists (e.g. from bootstrap-go-cli):

```just
# Generate OpenAPI client code
generate:
    go generate ./...

# Regenerate and tidy
regen: generate tidy
```

If no `tidy` recipe exists:

```just
# Generate OpenAPI client code
generate:
    go generate ./...

# Regenerate and tidy deps
regen: generate
    go mod tidy
```
