---
name: bootstrap-phoenix
description: "Bootstrap Phoenix Application"
---

# Bootstrap Phoenix Application

Set up a new Phoenix application with comprehensive code quality, testing, and development tooling including:
- Phoenix 1.8+ with LiveView
- PostgreSQL with binary_id
- Credo, ExDNA, ExSlop, Doctor, Dialyxir, and Sobelow for code quality
- PgFlow for background jobs and workflows (https://github.com/agoodway/pgflow)
- Req for HTTP (never HTTPoison/Tesla)
- Tidewave for AI agent integration
- Dotenvy for environment management
- Sentry error tracking
- Comprehensive quality check aliases

## Phase 0: Detect Existing Phoenix App

Before creating a new application, check if a Phoenix app already exists:

### 0.1 Detection Steps

1. **Check current directory** for `mix.exs` containing `{:phoenix,`
2. **Check immediate subdirectories** (one level deep) for `mix.exs` containing `{:phoenix,`

```bash
# Check current directory
grep -l "{:phoenix," mix.exs 2>/dev/null

# Check subdirectories (one level deep)
find . -maxdepth 2 -name "mix.exs" -exec grep -l "{:phoenix," {} \; 2>/dev/null
```

### 0.2 If Phoenix App Detected

If a Phoenix app is found:

1. **Extract the app name** from the `mix.exs` project configuration:
   ```elixir
   # Look for: app: :app_name in the project/0 function
   ```

2. **Set working directory** to the Phoenix app root (where `mix.exs` is located)

3. **Skip Phase 1** entirely and proceed directly to **Phase 2: Update Dependencies**

4. **Inform the user**: "Detected existing Phoenix app: `APP_NAME`. Skipping project creation and proceeding with dependency updates."

### 0.3 If No Phoenix App Detected

Proceed with **Phase 1: Create Phoenix Application** below.

---

## Phase 1: Create Phoenix Application (Skip if existing app detected)

### 1.1 Initialize Phoenix Project

```bash
mix phx.new APP_NAME --binary-id --database postgres
cd APP_NAME
```

**Note:** Replace `APP_NAME` with your actual application name (lowercase, underscores for spaces).

## Phase 2: Update Dependencies

### 2.1 Update mix.exs Dependencies

**File:** `mix.exs`

Replace the `deps/0` function with:

```elixir
defp deps do
  [
    # Phoenix Core
    {:phoenix, "~> 1.8"},
    {:phoenix_ecto, "~> 4.5"},
    {:ecto_sql, "~> 3.13"},
    {:postgrex, ">= 0.0.0"},
    {:phoenix_html, "~> 4.1"},
    {:phoenix_live_reload, "~> 1.2", only: :dev},
    {:phoenix_live_view, "~> 1.1"},
    {:phoenix_live_dashboard, "~> 0.8"},

    # Assets
    {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
    {:tailwind, "~> 0.3", runtime: Mix.env() == :dev},
    {:heroicons,
     github: "tailwindlabs/heroicons",
     tag: "v2.2.0",
     sparse: "optimized",
     app: false,
     compile: false,
     depth: 1},

    # HTTP Client (always use Req, never HTTPoison/Tesla)
    {:req, "~> 0.5"},

    # Email
    {:swoosh, "~> 1.16"},

    # Background Jobs — PgFlow (not Oban)
    {:pgflow, github: "agoodway/pgflow", branch: "main"},

    # Security
    {:bcrypt_elixir, "~> 3.0"},

    # Environment & Config
    {:dotenvy, "~> 1.1"},

    # Error Tracking
    {:sentry, "~> 12.0"},

    # Utilities
    {:telemetry_metrics, "~> 1.0"},
    {:telemetry_poller, "~> 1.0"},
    {:gettext, "~> 1.0"},
    {:jason, "~> 1.2"},
    {:dns_cluster, "~> 0.2.0"},
    {:bandit, "~> 1.5"},

    # Development Tools
    {:tidewave, "~> 0.5", only: :dev},

    # Code Quality (dev/test only)
    {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
    {:ex_dna, github: "dannote/ex_dna", branch: "master", only: [:dev, :test], runtime: false},
    {:ex_slop, github: "dannote/ex_slop", branch: "master", only: [:dev, :test], runtime: false},
    {:doctor, "~> 0.21", only: [:dev, :test], runtime: false},
    {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
    {:sobelow, "~> 0.13", only: [:dev, :test], runtime: false},

    # Testing
    {:lazy_html, ">= 0.1.0", only: :test},
    {:mimic, "~> 1.10", only: :test}
  ]
end
```

### 2.2 Update Project Configuration

**File:** `mix.exs`

Update the `project/0` function:

```elixir
def project do
  [
    app: :APP_NAME,
    version: "0.1.0",
    elixir: "~> 1.15",
    elixirc_paths: elixirc_paths(Mix.env()),
    start_permanent: Mix.env() == :prod,
    aliases: aliases(),
    deps: deps(),
    compilers: [:phoenix_live_view] ++ Mix.compilers(),
    listeners: [Phoenix.CodeReloader],
    dialyzer: [
      plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
      plt_add_apps: [:ex_unit]
    ]
  ]
end

def cli do
  [
    preferred_envs: [check: :test, precommit: :test]
  ]
end
```

### 2.3 Add Quality Check Aliases

**File:** `mix.exs`

Update the `aliases/0` function:

```elixir
defp aliases do
  [
    setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
    "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
    "ecto.reset": ["ecto.drop", "ecto.setup"],
    test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
    "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
    "assets.build": ["compile", "tailwind APP_NAME", "esbuild APP_NAME"],
    "assets.deploy": [
      "tailwind APP_NAME --minify",
      "esbuild APP_NAME --minify",
      "phx.digest"
    ],
    check: [
      "compile --warnings-as-errors",
      "deps.unlock --unused",
      "format --check-formatted",
      "credo --strict",
      "doctor",
      "sobelow --config",
      "dialyzer",
      "test"
    ],
    precommit: ["check"]
  ]
end
```

## Phase 3: Code Quality Configuration

### 3.1 Create Credo Configuration

**File:** `.credo.exs`

```elixir
%{
  configs: [
    %{
      name: "default",
      files: %{
        included: [
          "lib/",
          "src/",
          "test/",
          "web/",
          "apps/*/lib/",
          "apps/*/src/",
          "apps/*/test/",
          "apps/*/web/"
        ],
        excluded: [~r"/_build/", ~r"/deps/", ~r"/node_modules/"]
      },
      plugins: [],
      requires: ["deps/ex_dna/lib/ex_dna/integrations/credo.ex"],
      strict: true,
      parse_timeout: 5000,
      color: true,
      checks: %{
        enabled: [
          # Consistency Checks
          {Credo.Check.Consistency.ExceptionNames, []},
          {Credo.Check.Consistency.LineEndings, []},
          {Credo.Check.Consistency.ParameterPatternMatching, []},
          {Credo.Check.Consistency.SpaceAroundOperators, []},
          {Credo.Check.Consistency.SpaceInParentheses, []},
          {Credo.Check.Consistency.TabsOrSpaces, []},

          # Design Checks
          {Credo.Check.Design.AliasUsage,
           [priority: :low, if_nested_deeper_than: 2, if_called_more_often_than: 0]},
          {ExDNA.Credo, []},
          {Credo.Check.Design.TagTODO, [exit_status: 2]},
          {Credo.Check.Design.TagFIXME, []},

          # Readability Checks
          {Credo.Check.Readability.AliasOrder, []},
          {Credo.Check.Readability.FunctionNames, []},
          {Credo.Check.Readability.LargeNumbers, []},
          {Credo.Check.Readability.MaxLineLength, [priority: :low, max_length: 120]},
          {Credo.Check.Readability.ModuleAttributeNames, []},
          {Credo.Check.Readability.ModuleDoc, []},
          {Credo.Check.Readability.ModuleNames, []},
          {Credo.Check.Readability.ParenthesesInCondition, []},
          {Credo.Check.Readability.ParenthesesOnZeroArityDefs, []},
          {Credo.Check.Readability.PredicateFunctionNames, []},
          {Credo.Check.Readability.PreferImplicitTry, []},
          {Credo.Check.Readability.RedundantBlankLines, []},
          {Credo.Check.Readability.Semicolons, []},
          {Credo.Check.Readability.SpaceAfterCommas, []},
          {Credo.Check.Readability.StringSigils, []},
          {Credo.Check.Readability.TrailingBlankLine, []},
          {Credo.Check.Readability.TrailingWhiteSpace, []},
          {Credo.Check.Readability.UnnecessaryAliasExpansion, []},
          {Credo.Check.Readability.VariableNames, []},

          # ExSlop — Readability Checks (AI slop detection)
          {ExSlop.Check.Readability.NarratorDoc, []},
          {ExSlop.Check.Readability.NarratorComment, []},
          {ExSlop.Check.Readability.ObviousComment, []},
          {ExSlop.Check.Readability.StepComment, []},
          {ExSlop.Check.Readability.BoilerplateDocParams, []},
          {ExSlop.Check.Readability.DocFalseOnPublicFunction, []},

          # Refactoring Opportunities
          {Credo.Check.Refactor.Apply, []},
          {Credo.Check.Refactor.CondStatements, []},
          {Credo.Check.Refactor.CyclomaticComplexity, []},
          {Credo.Check.Refactor.FunctionArity, []},
          {Credo.Check.Refactor.LongQuoteBlocks, []},
          {Credo.Check.Refactor.MatchInCondition, []},
          {Credo.Check.Refactor.MapJoin, []},
          {Credo.Check.Refactor.NegatedConditionsInUnless, []},
          {Credo.Check.Refactor.NegatedConditionsWithElse, []},
          {Credo.Check.Refactor.Nesting, [max_nesting: 2]},
          {Credo.Check.Refactor.UnlessWithElse, []},
          {Credo.Check.Refactor.WithClauses, []},

          # ExSlop — Refactoring Checks (AI slop detection)
          {ExSlop.Check.Refactor.FilterNil, []},
          {ExSlop.Check.Refactor.RejectNil, []},
          {ExSlop.Check.Refactor.ReduceAsMap, []},
          {ExSlop.Check.Refactor.MapIntoLiteral, []},
          {ExSlop.Check.Refactor.IdentityPassthrough, []},
          {ExSlop.Check.Refactor.IdentityMap, []},
          {ExSlop.Check.Refactor.CaseTrueFalse, []},
          {ExSlop.Check.Refactor.TryRescueWithSafeAlternative, []},
          {ExSlop.Check.Refactor.WithIdentityElse, []},
          {ExSlop.Check.Refactor.WithIdentityDo, []},
          {ExSlop.Check.Refactor.SortThenReverse, []},
          {ExSlop.Check.Refactor.StringConcatInReduce, []},

          # Warnings
          {Credo.Check.Warning.ApplicationConfigInModuleAttribute, []},
          {Credo.Check.Warning.BoolOperationOnSameValues, []},
          {Credo.Check.Warning.ExpensiveEmptyEnumCheck, []},
          {Credo.Check.Warning.IExPry, []},
          {Credo.Check.Warning.IoInspect, []},
          {Credo.Check.Warning.OperationOnSameValues, []},
          {Credo.Check.Warning.OperationWithConstantResult, []},
          {Credo.Check.Warning.RaiseInsideRescue, []},
          {Credo.Check.Warning.SpecWithStruct, []},
          {Credo.Check.Warning.WrongTestFileExtension, []},
          {Credo.Check.Warning.UnusedEnumOperation, []},
          {Credo.Check.Warning.UnusedFileOperation, []},
          {Credo.Check.Warning.UnusedKeywordOperation, []},
          {Credo.Check.Warning.UnusedListOperation, []},
          {Credo.Check.Warning.UnusedPathOperation, []},
          {Credo.Check.Warning.UnusedRegexOperation, []},
          {Credo.Check.Warning.UnusedStringOperation, []},
          {Credo.Check.Warning.UnusedTupleOperation, []},
          {Credo.Check.Warning.UnsafeExec, []},

          # ExSlop — Warning Checks (AI slop detection)
          {ExSlop.Check.Warning.BlanketRescue, []},
          {ExSlop.Check.Warning.RescueWithoutReraise, []},
          {ExSlop.Check.Warning.RepoAllThenFilter, []},
          {ExSlop.Check.Warning.QueryInEnumMap, []},
          {ExSlop.Check.Warning.GenserverAsKvStore, []}
        ],
        disabled: [
          # Optional checks disabled for Phoenix projects
          {Credo.Check.Readability.Specs, []},
          {Credo.Check.Refactor.MapInto, []},
          {Credo.Check.Warning.LazyLogging, []},
          {Credo.Check.Refactor.AppendSingleItem, []},
          {Credo.Check.Refactor.DoubleBooleanNegation, []},
          {Credo.Check.Refactor.ModuleDependencies, []},
          {Credo.Check.Refactor.NegatedIsNil, []},
          {Credo.Check.Refactor.PipeChainStart, []},
          {Credo.Check.Refactor.VariableRebinding, []},
          {Credo.Check.Warning.LeakyEnvironment, []},
          {Credo.Check.Warning.MapGetUnsafePass, []},
          {Credo.Check.Warning.MixEnv, []},
          {Credo.Check.Warning.UnsafeToAtom, []}
        ]
      }
    }
  ]
}
```

### 3.2 Create Sobelow Configuration

**File:** `.sobelow-conf`

```
[
  verbose: false,
  private: false,
  skip: false,
  router: "",
  exit: "low",
  format: "txt",
  ignore: [],
  ignore_files: []
]
```

The `--config` flag in the check alias tells Sobelow to use this file. The `exit: "low"` setting ensures all findings (low, medium, high) cause a non-zero exit code.

### 3.3 Create Doctor Configuration

**File:** `.doctor.exs`

```elixir
%Doctor.Config{
  ignore_modules: [
    # Exclude test modules from documentation requirements
    ~r/.*Test$/,
    ~r/.*Fixtures$/,
    # Exclude generated Phoenix modules (update APP_NAME)
    ~r/^APP_NAMEWeb.Telemetry$/,
    ~r/^APP_NAMEWeb.Endpoint$/,
    ~r/^APP_NAME.DataCase$/,
    ~r/^APP_NAME.ConnCase$/,
    ~r/^APP_NAMEWeb.ConnCase$/
  ],
  ignore_paths: [
    "test/",
    "priv/",
    "deps/",
    "_build/"
  ],
  # Strict documentation coverage thresholds (80%+)
  min_module_doc_coverage: 80,
  min_module_spec_coverage: 0,
  min_overall_doc_coverage: 80,
  min_overall_moduledoc_coverage: 100,
  min_overall_spec_coverage: 0,
  # Don't raise on failures, just report
  raise: false,
  # Use full reporter for detailed output
  reporter: Doctor.Reporters.Full,
  # Don't require @type for structs (can be enabled later)
  struct_type_spec_required: false,
  # Not an umbrella project
  umbrella: false
}
```

### 3.4 Update Formatter Configuration

**File:** `.formatter.exs`

```elixir
[
  import_deps: [:ecto, :ecto_sql, :phoenix, :credo],
  subdirectories: ["priv/*/migrations"],
  plugins: [Phoenix.LiveView.HTMLFormatter],
  inputs: ["*.{heex,ex,exs}", "{config,lib,test}/**/*.{heex,ex,exs}", "priv/*/seeds.exs"]
]
```

## Phase 4: Environment Configuration

### 4.1 Create Environment Files

**File:** `.env.sample`

```bash
# APP_NAME Environment Variables Template
# Copy this file to .env and fill in your values
# DO NOT commit .env to version control

# Phoenix Server
PHX_SERVER=true
PHX_HOST=localhost
PORT=4000

# Database
DATABASE_URL=ecto://postgres:postgres@localhost/APP_NAME_dev
POOL_SIZE=10
ECTO_IPV6=false

# Security (generate with: mix phx.gen.secret)
SECRET_KEY_BASE=

# DNS Cluster (optional, for production clustering)
DNS_CLUSTER_QUERY=

# Feature Flags
ENABLE_BETA_FEATURES=false
MAINTENANCE_MODE=false

# Monitoring (optional)
SENTRY_DSN=
HONEYBADGER_API_KEY=

# Mailer Configuration (Development)
# For development, emails are logged by default
MAIL_FROM=noreply@example.com
```

**File:** `.env.dev`

```bash
DATABASE_URL=ecto://postgres:postgres@localhost/APP_NAME_dev
SECRET_KEY_BASE=your-dev-secret-key-base-generate-with-mix-phx-gen-secret
```

**File:** `.env.test`

```bash
DATABASE_URL=ecto://postgres:postgres@localhost/APP_NAME_test
SECRET_KEY_BASE=test-secret-key-base-minimum-64-characters-for-testing-purposes-only
```

### 4.2 Update Runtime Config

**File:** `config/runtime.exs`

Add this at the top (after `import Config`):

```elixir
import Config

# Load .env file for development and test environments
# In production, environment variables should be set by the deployment platform
if config_env() in [:dev, :test] do
  env_files = [
    ".env.#{config_env()}.local",
    ".env.#{config_env()}",
    ".env.local",
    ".env"
  ]

  existing_files = Enum.filter(env_files, &File.exists?/1)

  env_vars =
    existing_files
    |> Enum.reverse()
    |> Enum.reduce(%{}, fn file, acc ->
      case Dotenvy.source(file) do
        {:ok, vars} -> Map.merge(acc, vars)
        _ -> acc
      end
    end)

  Enum.each(env_vars, fn {key, value} ->
    if is_nil(System.get_env(key)) do
      System.put_env(key, value)
    end
  end)
end

# Rest of your runtime config continues below...
```

## Phase 5: Tidewave Configuration

### 5.1 Add Tidewave Plug to Endpoint

**File:** `lib/APP_NAME_web/endpoint.ex`

Add the Tidewave plug **before** the `if code_reloading? do` block:

```elixir
if Code.ensure_loaded?(Tidewave) do
  plug Tidewave
end

if code_reloading? do
  # ... existing code reloading configuration
```

### 5.2 Enable LiveView Debug Annotations

**File:** `config/dev.exs`

Add LiveView debug configuration for better Tidewave integration:

```elixir
# Tidewave works best with LiveView debug annotations enabled
config :phoenix_live_view,
  debug_heex_annotations: true,
  debug_attributes: true
```

## Phase 6: Sentry Error Tracking

### 6.1 Add Sentry Config

**File:** `config/config.exs`

Add at the end of the file (before any `import_config`):

```elixir
# Sentry error tracking
config :sentry,
  enable_source_code_context: true,
  root_source_code_paths: [File.cwd!()],
  included_environments: [:prod]

# Attach Sentry to Elixir's Logger so crashes/errors are captured automatically
config :APP_NAME, :logger, [
  {:handler, :sentry_handler, Sentry.LoggerHandler, %{config: %{metadata: [:request_id]}}}
]
```

### 6.2 Add Sentry Runtime Config

**File:** `config/runtime.exs`

Add after the Dotenvy loading block:

```elixir
# Sentry error tracking
if sentry_dsn = System.get_env("SENTRY_DSN") do
  config :sentry,
    dsn: sentry_dsn,
    environment_name: config_env()
end
```

### 6.3 Add Sentry Plug to Endpoint

**File:** `lib/APP_NAME_web/endpoint.ex`

Add `plug Sentry.PlugContext` **before** `plug Plug.MethodOverride`:

```elixir
  plug Sentry.PlugContext
  plug Plug.MethodOverride
```

### 6.4 Add Sentry LiveView Hook

**File:** `lib/APP_NAME_web.ex`

In the `live_view/0` macro, add `on_mount Sentry.LiveViewHook` inside the quote block:

```elixir
  defp live_view do
    quote do
      use Phoenix.LiveView

      on_mount Sentry.LiveViewHook

      unquote(html_helpers())
    end
  end
```

## Phase 7: PgFlow Background Jobs

Use [PgFlow](https://github.com/agoodway/pgflow) for background jobs and DAG workflows. Do not add Oban. Pattern matches the Goodviews Phoenix setup: enqueue without workers in test, start `{PgFlow, opts}` only when config is present.

### 7.1 Repo config (all environments)

**File:** `config/config.exs`

```elixir
# Repo for enqueue without a running PgFlow supervisor (tests).
config :pgflow, repo: APP_NAME.Repo
```

### 7.2 Supervisor config (non-test only)

**File:** `config/runtime.exs`

Add after the Dotenvy / Sentry blocks. Omit this in test so `Application` does not start workers:

```elixir
# Single source for non-test boots (dev + prod + releases). Omitted in test
# so APP_NAME.Application does not start PgFlow workers.
if config_env() != :test do
  config :APP_NAME, PgFlow,
    repo: APP_NAME.Repo,
    jobs: [],
    flows: [],
    max_concurrency: 10,
    signal_strategy: :notify
end
```

Do **not** set `:pubsub` unless you are adding LiveClient / dashboard. Do **not** call `Mix.env/0`.

### 7.3 Supervision tree

**File:** `lib/APP_NAME/application.ex`

Insert `pgflow_children()` into the existing children list (do not drop other children). Start PgFlow only when `Application.get_env(:APP_NAME, PgFlow)` is a keyword list:

```elixir
children =
  [
    APP_NAMEWeb.Telemetry,
    APP_NAME.Repo,
    {Phoenix.PubSub, name: APP_NAME.PubSub}
  ] ++
    pgflow_children() ++
    [
      {DNSCluster, query: Application.get_env(:APP_NAME, :dns_cluster_query) || :ignore},
      APP_NAMEWeb.Endpoint
    ]

defp pgflow_children do
  case Application.get_env(:APP_NAME, PgFlow) do
    opts when is_list(opts) -> [{PgFlow, opts}]
    _other -> []
  end
end
```

### 7.4 Database migrations

After `mix deps.get`:

```bash
mix pgflow.gen.postgres_extensions_migration
mix pgflow.gen.pgmq_migration
mix pgflow.setup
mix ecto.migrate
```

Then edit generated migrations:

- Rename modules to `APP_NAME.Repo.Migrations.*` if the generator emits `PgFlow.Repo.Migrations.*`
- Keep `@disable_ddl_transaction true` and `@disable_migration_lock true` on the extensions migration
- Wrap `CREATE EXTENSION pg_cron` (and later `cron.schedule` / `cron.unschedule`) so they run only when `current_setting('cron.database_name', true) IS NOT DISTINCT FROM current_database()` — worktree and test DBs still migrate
- Do **not** pass `--dashboard` to `mix pgflow.setup`
- On hosts without pg_cron, regenerate extensions with `mix pgflow.gen.postgres_extensions_migration --no-cron`
- On hosts that already ship pgmq (e.g. Supabase), skip `mix pgflow.gen.pgmq_migration` and `CREATE EXTENSION IF NOT EXISTS pgmq` instead

Later jobs/flows:

```bash
mix pgflow.gen.job_migration APP_NAME.Jobs.ExampleJob
mix pgflow.gen.flow_migration APP_NAME.Flows.ExampleFlow
mix ecto.migrate
```

Register each module in the `jobs:` / `flows:` lists in the `:APP_NAME, PgFlow` config.

### 7.5 Tests

- Do **not** start PgFlow workers in test (omit `:APP_NAME, PgFlow` in `config/test.exs`)
- Call `JobModule.perform(input, ctx)` (or `nil` if unused). `PgFlow.Context.new/1` needs `run_id`, `step_slug`, `task_index`, `attempt`, `repo`
- Assert enqueue by querying `pgflow.runs` (`flow_slug` + `input`), not an Oban helper
- Handler return is a JSON-serializable **map**, not `:ok`. Raise to retry; return a map to complete (including no-ops and permanent failures)
- Timeout is seconds on `@job`, read via `JobModule.__pgflow_definition__().opts[:timeout]`

## Phase 8: Finalize Setup

### 8.1 Update .gitignore

**File:** `.gitignore`

Add these lines:

```gitignore
# Environment files (keep samples)
.env
.env.local
.env.*.local
!.env.sample

# Dialyzer PLT files
/priv/plts/

# Editor and IDE
.idea/
*.swp
*.swo
.vscode/
```

### 8.2 Create Dialyzer PLT Directory

```bash
mkdir -p priv/plts
```

## Installation & Verification

After creating all files, run:

```bash
# Install dependencies
mix deps.get

# Setup database
mix ecto.setup

# Build assets
mix assets.setup
mix assets.build

# Build Dialyzer PLT (takes 5-10 minutes first time)
mix dialyzer --plt

# Run full quality check
mix check
```

## Checklist

After running this command, you should have:

- [ ] Phoenix project with binary_id and PostgreSQL
- [ ] All dependencies installed (Credo, ExDNA, ExSlop, Doctor, Dialyxir, Sobelow, PgFlow, Req, Sentry, Tidewave)
- [ ] PgFlow wired (dep from GitHub `agoodway/pgflow`, `config :pgflow, repo:`, non-test `{PgFlow, opts}` child, schema migrations, no workers in test)
- [ ] Credo configuration (.credo.exs)
- [ ] Sobelow configuration (.sobelow-conf)
- [ ] Doctor configuration (.doctor.exs)
- [ ] Updated formatter (.formatter.exs)
- [ ] Environment files (.env.sample, .env.dev, .env.test)
- [ ] Dotenvy integration in runtime.exs
- [ ] Tidewave plug in endpoint.ex
- [ ] LiveView debug annotations in dev.exs
- [ ] Sentry config in config.exs and runtime.exs
- [ ] Sentry.PlugContext in endpoint.ex
- [ ] Sentry.LiveViewHook in web module live_view macro
- [ ] Quality check aliases in mix.exs
- [ ] Updated .gitignore
- [ ] Dialyzer PLT directory created

## Placeholder Values to Update

Search and replace `APP_NAME` in these files:

- `mix.exs` (multiple locations)
- `.doctor.exs` (module ignore patterns)
- `lib/APP_NAME_web/endpoint.ex` (Tidewave plug)
- `lib/APP_NAME/application.ex` (PgFlow child)
- `config/config.exs` (`config :pgflow, repo:`)
- `config/runtime.exs` (`:APP_NAME, PgFlow`)
- `.env.sample`
- `.env.dev`
- `.env.test`

## Quick Reference Commands

```bash
# Development
mix phx.server              # Start server
iex -S mix phx.server       # Start with IEx

# Quality Checks
mix check                   # Run ALL quality checks (use before commits)
mix precommit               # Alias for mix check
mix format                  # Auto-format code
mix credo --strict          # Static analysis
mix doctor                  # Documentation coverage
mix sobelow --config        # Security analysis
mix dialyzer                # Type checking

# Testing
mix test                    # Run all tests
mix test --failed           # Re-run failed tests
mix test path/to/test.exs:42  # Run specific test at line

# Database
mix ecto.gen.migration name # Generate migration
mix ecto.migrate            # Run migrations
mix ecto.reset              # Drop and recreate DB
```

## Important Notes

- **Background jobs**: Always use PgFlow (`github: "agoodway/pgflow"`), never Oban
- **HTTP Client**: Always use `Req`, never `HTTPoison`, `Tesla`, or `:httpc`
- **Tailwind CSS v4**: Uses new import syntax - all vendor deps must be imported into `app.js` or `app.css`
- **Never write inline `<script>` tags** in templates
- **Run `mix check` before every commit** to catch issues early
- **First Dialyzer run** builds the PLT and takes several minutes
- **Tidewave**: Only runs in development, provides AI agent integration via MCP. Requires the endpoint plug and LiveView debug annotations for full functionality

---

**Note:** This bootstrap creates a production-ready Phoenix application with comprehensive quality tooling. After setup, always run `mix check` before committing code.
