# Bootstrap Strategies Reference

How to detect and implement each environment loading strategy for workie bootstrap.

## Table of Contents

- [Step 0: Detect Environment Loading Strategy](#step-0-detect-environment-loading-strategy)
- [Strategy A: Dotenvy](#strategy-a-dotenvy)
- [Strategy B: Elixir Script Import](#strategy-b-elixir-script-import)
- [Strategy C: Plain System.get_env](#strategy-c-plain-systemget_env)

---

## Step 0: Detect Environment Loading Strategy

**Before doing anything else**, inspect the project to determine how it loads environment variables. Check these files:

1. `config/config.exs` - look for `import_config` of `.env.*` files
2. `config/runtime.exs` - look for `import Dotenvy` or `Dotenvy.source!`
3. `mix.exs` - look for `:dotenvy` or `:dotenv` in deps
4. Root directory - look for `envs/` directory, `.env` files, `.env.*.exs` files

### Strategy A: Dotenvy (preferred for new setups)

**Detected when**: `mix.exs` contains `{:dotenvy, ...}` or `config/runtime.exs` contains `import Dotenvy`.

**Also use when**: No env loading method exists yet (install dotenvy fresh).

Uses standard `.env` files (KEY=VALUE format) loaded via `Dotenvy.source!/2` in `config/runtime.exs`. Works in both dev and production releases.

### Strategy B: Elixir Script Import

**Detected when**: `config/config.exs` contains `import_config "../.env.#{config_env()}.exs"` or similar.

Uses `.env.dev.exs` / `.env.test.exs` files containing `System.put_env/2` calls, imported via `import_config` in `config/config.exs`.

### Strategy C: Plain System.get_env

**Detected when**: Config files only use `System.get_env/1` with no `.env` file loading.

Secrets are set externally (shell exports, direnv, etc). Workie only needs to handle the `.branch` file and database scripts.

---

**Use whichever strategy the project already has. If none exists, install dotenvy (Strategy A).**

---

## Strategy A: Dotenvy

### A1. Install Dotenvy (skip if already present)

Add to `mix.exs` deps:

```elixir
{:dotenvy, "~> 0.8", only: [:dev, :test]}
```

Run `mix deps.get`.

### A2. Create Env Directory and Files

Create an `envs/` directory in the project root with these files:

**`envs/.env`** (shared defaults, committed):
```bash
# Shared defaults across all environments
# Override in environment-specific files
DATABASE_HOST=localhost
DATABASE_USER=postgres
DATABASE_PASS=postgres
```

**`envs/.dev.env`** (dev secrets, gitignored):
```bash
# Dev environment secrets - DO NOT COMMIT
# SOME_API_KEY=your-key-here
```

**`envs/.test.env`** (test secrets, gitignored):
```bash
# Test environment secrets - DO NOT COMMIT
```

**`envs/.dev.overrides.env`** (personal overrides, gitignored):
```bash
# Personal overrides - DO NOT COMMIT
```

### A3. Configure runtime.exs

Add dotenvy loading to the **top** of `config/runtime.exs`, before any `config` calls:

```elixir
import Config
import Dotenvy

env_dir_prefix = System.get_env("RELEASE_ROOT") || Path.expand("./envs")

source!([
  Path.absname(".env", env_dir_prefix),
  Path.absname(".#{config_env()}.env", env_dir_prefix),
  Path.absname(".#{config_env()}.overrides.env", env_dir_prefix),
  System.get_env()
])
```

### A4. Branch-Aware Database Naming

In `config/runtime.exs`, after the `source!` call, configure the database:

```elixir
# Branch-isolated database for worktrees
branch_suffix =
  if File.exists?(".branch") do
    branch_id = File.read!(".branch") |> String.trim()
    "_#{branch_id}"
  else
    ""
  end

if config_env() == :dev do
  config :app_name, AppName.Repo,
    username: env!("DATABASE_USER", :string, "postgres"),
    password: env!("DATABASE_PASS", :string, "postgres"),
    hostname: env!("DATABASE_HOST", :string, "localhost"),
    database: "APP_NAME#{branch_suffix}_dev",
    stacktrace: true,
    show_sensitive_data_on_connection_error: true,
    pool_size: env!("POOL_SIZE", :integer, 10)
end

if config_env() == :test do
  config :app_name, AppName.Repo,
    username: env!("DATABASE_USER", :string, "postgres"),
    password: env!("DATABASE_PASS", :string, "postgres"),
    hostname: env!("DATABASE_HOST", :string, "localhost"),
    database: "APP_NAME#{branch_suffix}_test#{System.get_env("MIX_TEST_PARTITION")}",
    pool: Ecto.Adapters.SQL.Sandbox,
    pool_size: env!("POOL_SIZE", :integer, 16)
end

if config_env() == :prod do
  config :app_name, AppName.Repo,
    url: env!("DATABASE_URL", :string!),
    pool_size: env!("POOL_SIZE", :integer, 10)
end
```

> **NOTE**: If `config/dev.exs` and `config/test.exs` already configure the Repo, remove those blocks to avoid conflicts. The runtime.exs config takes precedence but duplicates cause confusion.

### A5. Workie Config for Dotenvy

```yaml
files_to_copy:
  - envs/.dev.env
  - envs/.test.env
  - envs/.dev.overrides.env
```

### A6. Gitignore for Dotenvy

```
# Dotenvy env files (keep .env shared defaults)
envs/.dev.env
envs/.test.env
envs/.dev.overrides.env
envs/.prod.env
envs/*.overrides.env
.branch
```

### A7. Example Env File (Optional)

Create `envs/.dev.env.example` (committed) listing all expected vars:

```bash
# Copy to envs/.dev.env and fill in values
SOME_API_KEY=
ANOTHER_SECRET=
```

---

## Strategy B: Elixir Script Import

### B1. Create Env Script Files

**`.env.dev.exs`** (gitignored):
```elixir
# Dev environment secrets - DO NOT COMMIT
# System.put_env("SOME_API_KEY", "your-key-here")
```

**`.env.test.exs`** (gitignored):
```elixir
# Test environment secrets - DO NOT COMMIT
```

### B2. Import in config.exs

Add to the **bottom** of `config/config.exs`:

```elixir
if File.exists?("../.env.#{config_env()}.exs") do
  import_config "../.env.#{config_env()}.exs"
end
```

> **IMPORTANT**: This must be the last line in `config.exs` so env vars are set before `dev.exs`/`test.exs` run.

### B3. Branch-Aware Database Naming

**Replace** the hardcoded database name in `config/dev.exs`:

```elixir
db_name =
  if File.exists?(".branch") do
    branch_id = File.read!(".branch") |> String.trim()
    "APP_NAME_#{branch_id}_dev"
  else
    System.get_env("DB_NAME", "APP_NAME_dev")
  end

config :app_name, AppName.Repo,
  database: db_name,
  # ... rest of existing config
```

**Same pattern** in `config/test.exs`:

```elixir
db_name =
  if File.exists?(".branch") do
    branch_id = File.read!(".branch") |> String.trim()
    "APP_NAME_#{branch_id}_test#{System.get_env("MIX_TEST_PARTITION")}"
  else
    System.get_env("DB_NAME", "APP_NAME_test#{System.get_env("MIX_TEST_PARTITION")}")
  end

config :app_name, AppName.Repo,
  database: db_name,
  # ... rest of existing config
```

### B4. Workie Config for Elixir Script Strategy

```yaml
files_to_copy:
  - .env.dev.exs
  - .env.test.exs
```

### B5. Gitignore for Elixir Script Strategy

```
.env*
!.env.example
.branch
```

---

## Strategy C: Plain System.get_env

### C1. Branch-Aware Database Naming Only

Same as Strategy B, Step B3 — add the `.branch` file check to `config/dev.exs` and `config/test.exs`. No env file changes needed since secrets are managed externally.

### C2. Workie Config for Plain Strategy

No `files_to_copy` needed (or copy whatever external config the project uses like `.envrc`).

```yaml
files_to_copy: []
```

### C3. Gitignore

```
.branch
```
