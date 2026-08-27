# pgflow job

Scaffold a new PgFlow job module and generate the database migration to compile it.

## Inputs

- **Arg form**: `/pgflow job MyApp.Jobs.SendEmail` — use the provided module name directly.
- **No arg**: Ask the user for the job module name. Suggest a name based on the app module detected from `mix.exs`.

## Workflow

### 1. Detect App Context

```bash
grep "app:" mix.exs | head -1
```

Extract the app module name (e.g., `MyApp`) and OTP app name (e.g., `my_app`).

### 2. Ask About the Job

If the user didn't describe the job's purpose, ask:
- What does this job do? (e.g., "send an email", "process an upload", "sync data")
- Should it run on a schedule? If yes, what schedule?

### 3. Generate the Job Module

Create `lib/<app>/jobs/<job_name>.ex`:

```elixir
defmodule MyApp.Jobs.SendEmail do
  use PgFlow.Job

  @job queue: :send_email, max_attempts: 5, base_delay: 10, timeout: 120

  perform :deliver do
    fn input, _ctx ->
      # TODO: Implement job logic
      # input["to"], input["subject"], input["body"]
      %{sent: true}
    end
  end
end
```

Rules for generating the module:
- Queue slug is the snake_case version of the last segment of the module name
- If the user wants a cron schedule, add `cron: [schedule: "...", input: %{}]` to `@job`
- Set `timeout` based on expected work duration (email: 120s, file processing: 300s, API sync: 60s)
- Set `max_attempts` based on idempotency (side-effect-free: 5+, external APIs: 3, payments: 1-2)
- Include TODO comments with expected input keys based on the user's description

### 4. Register in Config

Read `config/config.exs` and add the new module to the `jobs:` list:

```elixir
config :my_app, PgFlow,
  jobs: [MyApp.Jobs.SendEmail],  # add to existing list
  # ...
```

If PgFlow is not yet configured, tell the user to run `/pgflow bootstrap` first.

### 5. Compile to Database

```bash
mix pgflow.gen.job_migration MyApp.Jobs.SendEmail
mix ecto.migrate
```

### 6. Show Usage

Print how to enqueue the job:

```elixir
{:ok, run_id} = PgFlow.enqueue(MyApp.Jobs.SendEmail, %{
  "to" => "user@example.com",
  "subject" => "Welcome",
  "body" => "Hello!"
})
```

## Cron Schedule Reference

| Expression | Meaning |
|---|---|
| `"* * * * *"` | Every minute |
| `"*/5 * * * *"` | Every 5 minutes |
| `"@hourly"` | Every hour |
| `"0 9 * * *"` | Daily at 9am |
| `"0 0 * * 1"` | Weekly on Monday |
| `"0 0 1 * *"` | Monthly on the 1st |

## Guardrails

- Always use `use PgFlow.Job` and the `@job` module attribute
- Queue slugs must be unique across all flows and jobs
- All handler return values must be JSON-serializable
- Do not create the migration file manually — use `mix pgflow.gen.job_migration`
- For jobs that call external APIs, set appropriate timeouts and retry limits
