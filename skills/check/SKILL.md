---
name: check
description: "Run project quality checks via `just check`. Dispatches subcommands via `/check [subcommand]`. Use when the user says '/check', '/check fix', '/check help', 'run checks', 'quality checks', 'lint', or wants to run or fix the project's check suite. Requires a justfile with a check recipe."
---

# Check

Run the project's quality checks via `just check`, with an optional fix subcommand to auto-fix failures.

## Subcommands

| Subcommand | Purpose |
|------------|---------|
| `check` | Run `just check` and report results (default) |
| `fix` | Run `just check`, then fix all failures |

### `/check help`

Display a list of all available subcommands. Output the following exactly:

```
/check subcommands:

  check   — Run just check and report results (default)
  fix     — Run just check, then fix all failures
  help    — Show this help message
```

If `/check` is invoked without a subcommand, default to `check`.

## Dispatch

1. Parse the subcommand from the user's invocation. Examples:
   - `/check` → default to `check`
   - `/check fix` → subcommand `fix`
   - `/check help` → show help
2. If the subcommand is unknown, list available subcommands and stop.
3. Follow the matching workflow below.

## Prerequisites (both subcommands)

Before running either subcommand:

1. **Verify justfile exists** — look for a `justfile` in the project root.

2. **If no justfile found**, stop and tell the user:

   ```
   No justfile found in the project root.

   This skill requires a justfile with a `check` recipe. Install the justfile skill and generate one:

     npx skills add agoodway/GoodSkills --skill justfile -g

   Then run:

     /justfile

   This will detect your project type and generate a justfile with a `check` recipe that runs your project's linting and quality tools.
   ```

3. **If justfile exists but has no `check` recipe**, stop and tell the user:

   ```
   Your justfile does not have a `check` recipe.

   Add a check recipe to your justfile. Examples by project type:

     Elixir/Phoenix:  check:\n\tmix check
     Node.js:         check:\n\tnpm run lint
     Python:          check:\n\truff check .
     Go:              check:\n\tgo vet ./...
     Rust:            check:\n\tcargo clippy

   Or regenerate your justfile with `/justfile` to get one automatically.
   ```

## `/check check`

Run quality checks and report results.

1. Run `just check` in the project root.
2. If it exits cleanly, report success and stop.
3. If the check command fails (non-zero exit):
   - Show the full output so the user can see what failed.
   - Do NOT automatically fix issues — just report them.
   - Suggest `/check fix` to auto-fix the failures.

## `/check fix`

Run quality checks, then fix all failures.

1. **Check for existing output** — if `/check` or `/check check` was already run in this conversation and the output is still available:
   - Show the user what failed in the previous run.
   - Ask the user: "Checks were already run. Do you want to re-run or proceed with fixing the existing failures?"
   - If the user chooses to proceed, skip to step 3 using the existing output.
   - If the user chooses to re-run, continue to step 2.

2. Run `just check` in the project root. If it exits cleanly, report success and stop.

3. Parse the output to identify which tools failed. Fix each category:

   ### Elixir/Phoenix (`mix check` or similar)

   - **Compile warnings** (`--warnings-as-errors`): read the files with warnings and fix them — unused variables, missing imports, deprecated calls, etc.
   - **Format** (`mix format --check-formatted`): run `mix format` to auto-fix.
   - **Credo** (`mix credo --strict`): run `/credo fix` to handle Credo issues.
   - **Doctor** (`mix doctor`): fix documentation coverage — add `@moduledoc` and `@doc` where missing.
   - **Dialyzer** (`mix dialyzer`): fix type specs and type errors flagged by Dialyzer.
   - **Tests** (`mix test`): read failing tests, diagnose, and fix. If the fix requires changing application code (not just tests), ask the user before proceeding.

   ### Node.js (`npm run lint` or similar)

   - **ESLint/Prettier**: run the auto-fix command (e.g., `npx eslint --fix .`, `npx prettier --write .`).
   - **TypeScript** (`tsc --noEmit`): fix type errors in the flagged files.
   - **Tests**: read failing tests, diagnose, and fix.

   ### Python (`ruff check .` or similar)

   - **Ruff/Flake8**: run `ruff check --fix .` to auto-fix.
   - **Black/isort**: run `black .` and `isort .` to auto-format.
   - **mypy**: fix type errors in the flagged files.
   - **Tests**: read failing tests, diagnose, and fix.

   ### Go (`go vet ./...` or similar)

   - **go vet**: fix issues in the flagged files.
   - **golangci-lint**: run `golangci-lint run --fix` if available.
   - **Tests**: read failing tests, diagnose, and fix.

   ### Rust (`cargo clippy` or similar)

   - **Clippy**: run `cargo clippy --fix --allow-dirty` to auto-fix.
   - **rustfmt**: run `cargo fmt` to auto-format.
   - **Tests**: read failing tests, diagnose, and fix.

4. After fixing, run `just check` again to verify.
5. If issues remain, report what's left and attempt a second pass.
6. Report final results: what was fixed, what remains (if any).

$ARGUMENTS
