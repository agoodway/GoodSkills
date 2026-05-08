---
name: check
description: "Run project quality checks via `just check`. Use when the user says '/check', 'run checks', 'quality checks', 'lint', or wants to run the project's check suite. Requires a justfile with a check recipe."
---

# Check

Run the project's quality checks via `just check`.

## Instructions

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

4. **If justfile exists with a `check` recipe**, run `just check` and report the results.

5. If the check command fails (non-zero exit):
   - Show the full output so the user can see what failed.
   - Do NOT automatically fix issues — just report them.
   - Suggest `/credo fix` if the failures are Credo-related (Elixir projects).

$ARGUMENTS
