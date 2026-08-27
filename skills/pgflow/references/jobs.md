# PgFlow Job DSL Reference

Jobs are single-step background tasks — a simplified wrapper around flows for when you don't need multi-step DAGs.

## Defining a Job

```elixir
defmodule MyApp.Jobs.SendEmail do
  use PgFlow.Job

  @job queue: :send_email,
       max_attempts: 5,
       base_delay: 10,
       timeout: 120,
       cron: [schedule: "@hourly"]  # optional

  perform :deliver do
    fn input, ctx ->
      Mailer.send(input["to"], input["subject"], input["body"])
      %{sent: true, timestamp: DateTime.utc_now() |> DateTime.to_iso8601()}
    end
  end
end
```

### @job Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `queue` | atom | required | Unique queue identifier |
| `max_attempts` | integer | 3 | Maximum retry attempts |
| `base_delay` | integer | 5 | Initial backoff delay in seconds |
| `timeout` | integer | 60 | Execution timeout in seconds |
| `cron` | keyword | nil | Scheduled execution (`schedule:` cron expr, `input:` default input) |

### perform Block

The `perform` macro defines the job handler. The name argument is optional (defaults to queue slug):

```elixir
# Named perform
perform :deliver do
  fn input, ctx -> %{done: true} end
end

# Default name (uses queue slug)
perform do
  fn input, ctx -> %{done: true} end
end
```

The handler receives:
- `input` — the JSON-serializable map passed when enqueuing
- `ctx` — `PgFlow.Context` struct with run_id, attempt, repo, etc.

## Compiling Jobs

```bash
mix pgflow.gen.job_migration MyApp.Jobs.SendEmail
mix ecto.migrate
```

## Enqueuing Jobs

```elixir
{:ok, run_id} = PgFlow.enqueue(MyApp.Jobs.SendEmail, %{
  "to" => "user@example.com",
  "subject" => "Welcome",
  "body" => "Hello!"
})
```

## Cron Scheduling

```elixir
@job queue: :daily_report,
     cron: [schedule: "0 9 * * *", input: %{"type" => "daily"}]

# Standard cron expressions
# "0 9 * * *"    — daily at 9am
# "@hourly"      — every hour
# "*/5 * * * *"  — every 5 minutes
# "0 0 * * 1"    — weekly on Monday
```

## Configuration

Register jobs in config:

```elixir
config :my_app, PgFlow,
  repo: MyApp.Repo,
  jobs: [MyApp.Jobs.SendEmail, MyApp.Jobs.DailyReport],
  # ...
```

## When to Use Jobs vs Flows

| Use Case | Use |
|----------|-----|
| Single async task (send email, process upload) | **Job** |
| Multi-step pipeline with dependencies | **Flow** |
| Scheduled recurring task | **Job** with `cron:` |
| Scheduled recurring pipeline | **Flow** with `cron:` |
| Parallel processing of array items | **Flow** with `map` step |
