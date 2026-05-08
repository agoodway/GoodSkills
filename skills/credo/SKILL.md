---
name: credo
description: "Run Credo static analysis on Elixir projects. Dispatches subcommands via `/credo [subcommand]`. Use when the user says '/credo check', '/credo fix', '/credo help', 'run credo', 'credo issues', or wants to check or fix Credo warnings in an Elixir project."
---

# Credo

Run Credo static analysis checks and fix issues in Elixir projects. Expects Credo to be a dependency in the project's `mix.exs`.

## Subcommands

| Subcommand | Purpose |
|------------|---------|
| `check` | Run `mix credo --strict` and report issues |
| `fix` | Run Credo, then fix all reported issues |

### `/credo help`

Display a list of all available subcommands. Output the following exactly:

```
/credo subcommands:

  check   — Run mix credo --strict and report issues
  fix     — Run Credo, then fix all reported issues
  help    — Show this help message
```

If `/credo` is invoked without a subcommand, default to `check`.

## Dispatch

1. Parse the subcommand from the user's invocation. Examples:
   - `/credo` → default to `check`
   - `/credo check` → subcommand `check`
   - `/credo fix` → subcommand `fix`
   - `/credo help` → show help
2. If the subcommand is unknown, list available subcommands and stop.
3. Follow the matching workflow below.

## `/credo check`

Run Credo analysis and report results.

1. Run `mix credo --strict` in the project root.
2. If Credo exits cleanly with no issues, report success and stop.
3. If issues are found, present a concise summary:
   - Total issue count grouped by category (Consistency, Design, Readability, Refactor, Warning)
   - List each issue with file, line, and message
4. Do NOT fix anything — just report.

## `/credo fix`

Run Credo and fix all reported issues.

1. **Check for existing Credo output** — if `/credo check` was already run in this conversation and the results are still available:
   - Show the user the issue count from the previous run.
   - Ask the user: "Credo check was already run with **N issues** found. Do you want to re-run the check or proceed with fixing the existing issues?"
   - If the user chooses to proceed, skip to step 3 using the existing results.
   - If the user chooses to re-run, continue to step 2.
2. Run `mix credo --strict --format json` in the project root. If Credo exits cleanly with no issues, report success and stop.
3. If issues are found:
   - Parse the JSON output to get the list of issues with file paths, line numbers, check names, and messages.
   - Group issues by file.
   - For each file, read the file and fix all Credo issues in that file:
     - **Consistency issues** (e.g., `SpaceAroundOperators`, `SpaceInParentheses`): apply the consistent style.
     - **Readability issues** (e.g., `AliasOrder`): reorder aliases alphabetically. For `ModuleDoc`: add `@moduledoc false` if the module is internal/private, otherwise add a meaningful `@moduledoc`. For `MaxLineLength`: break long lines.
     - **Refactor issues** (e.g., `Nesting`, `CyclomaticComplexity`): refactor to reduce complexity. For `WithClauses`: simplify `with` blocks. For `Nesting`: extract helper functions.
     - **Warning issues** (e.g., `IoInspect`, `IExPry`): remove debug statements. For `UnusedEnumOperation` and similar: ensure return values are used or remove dead code.
     - **Design issues** (e.g., `AliasUsage`): add missing aliases. For `TagTODO`/`TagFIXME`: ask the user whether to resolve or suppress.
     - **ExSlop issues** (AI slop detection): fix the specific anti-pattern identified by the check message.
   - After fixing all issues in a file, save the file.
4. After all files are fixed, run `mix credo --strict` again to verify.
5. If issues remain, report them and attempt a second pass on the remaining issues.
6. Report final results: how many issues were fixed, how many remain (if any).

## Notes

- Always use `--strict` flag to catch all issues including low-priority ones.
- For `--format json`, if the project's Credo version doesn't support it, fall back to parsing the standard text output.
- When fixing, preserve the existing code style and intent — only change what Credo flags.
- If a fix would change behavior (not just style), ask the user before applying.
- ExSlop checks (AI slop detection) are custom checks from the `ex_slop` dependency — treat them like standard Credo checks.

$ARGUMENTS
