---
name: listex
description: >
  Use the listex CLI to manage the Listex/Yocal city platform via its v2 API — cities,
  jobs, homes, news, events, tips, neighborhoods, listicles, places, content pages,
  zip codes, and the email stack (audiences, templates, broadcasts, weekly sends).
  Triggers: "/listex", "listex", "list cities", "create a job listing", "publish news",
  "publish an event", "city tips", "neighborhoods", "listicles", "places for a city",
  "content pages", "zip code demographics", "email audience", "email template",
  "broadcast", "weekly newsletter", "send the weekly", "yocal", configure listex
  environments, or when the user wants to read or edit Listex platform data from the
  terminal. Prefer this skill over raw curl against the Listex API.
---

# listex

Agent guide for the **listex** Rust CLI (Listex / Yocal city platform, API v2). Prefer the installed binary over hand-rolling HTTP calls — it handles auth, city slug resolution, request envelopes, and pagination.

## Binary resolution

1. Prefer `listex` on `PATH` (usually `~/.local/bin/listex`).
2. If missing, install from a release:
   ```bash
   curl -fsSL https://raw.githubusercontent.com/agoodway/listex/main/cli-rust/install.sh | sh
   ```
3. Or from a local checkout of the listex repo (`cli-rust/` is the canonical tree; the Zig `cli/` tree is deprecated):
   ```bash
   cd cli-rust && just release && LISTEX_LOCAL_BIN=./target/release/listex ./install.sh
   ```
4. Windows: `install.ps1` (supports `LISTEX_LOCAL_BIN` the same way).
5. Confirm: `listex --version` and `listex configure show`.

## Config

Stored at `~/.listex.json` (Windows: `%USERPROFILE%\.listex.json`). Multi-environment, shared with the legacy Zig binary.

```bash
listex configure set --env dev --base-url http://localhost:4000/api/v2 --api-key <key>
listex configure set --env prod --base-url https://yocal.vip/api/v2 --api-key <key>
listex configure show      # table of envs, API keys masked
listex configure use prod  # set the default env
```

- Base URLs **must** include the `/api/v2` prefix.
- Override per-invocation with the global `--env <name>`.
- The first environment added becomes the default.

**Never print full API keys.** `configure show` masks them — do not `cat ~/.listex.json` or echo a key into the transcript. If commands fail with a missing-config error, run `configure show` and ask the user for a key; never invent one.

## Safety rules — read before any write

These operations are irreversible or contact real people. **Get explicit confirmation from the user in the conversation before running any of them**, even if the surrounding task seems to imply it:

| Command | Why it's dangerous |
|---------|--------------------|
| `broadcasts test <id> --emails …` | Sends **real email** to those addresses. Not a dry run. |
| `broadcasts send <id> --confirm` | Queues delivery to the entire audience. |
| `weekly send … --send --confirm` | Same, via the weekly workflow. |
| `broadcasts delete <id> --confirm` | Permanent. |
| `jobs/news/events/homes/places/neighborhoods/listicles/content-pages delete` | Permanent, and **does not require `--confirm`** — a bare `delete` goes through immediately. |

Rules:

- `--confirm` is the **user's** flag to authorize an action, not one you add to satisfy the CLI. If a command fails for want of `--confirm`, report that to the user and ask — do not re-run with it appended.
- Prefer `--schedule <iso>` over `--send` so a human can review before delivery. They are mutually exclusive.
- Before any `delete`, show the record first (`listex <cmd> <id>`) so the user can confirm it's the right one.
- Before a broadcast, list what will be affected (audience, recipient count, content IDs) and show it to the user.

## Cross-cutting rules

**`--json` for anything you parse.** Bare output is column-aligned tables meant for a human reading the terminal. Use `--json` whenever you need to extract an ID, count, filter, or chain a result into the next command. Detail views also summarize large MJML/HTML bodies unless you pass `--json`.

**Request envelopes vary by resource — this is the most common failure.** Most `create`/`update` bodies must be wrapped; a few must not be:

| Resource | Envelope |
|----------|----------|
| cities | `{"city": {…}}` — bare fields auto-wrapped |
| jobs | `{"job": {…}}` |
| news | `{"news": {…}}` |
| events | `{"event": {…}}` |
| tips | `{"tip": {…}}` |
| places | `{"place": {…}}` — bare fields auto-wrapped |
| neighborhoods | `{"neighborhood": {…}}` |
| listicles | `{"listicle": {…}}` |
| audiences | `{"audience": {…}}` — bare auto-wrapped |
| email-templates | `{"email_template": {…}}` — bare auto-wrapped |
| broadcasts | `{"broadcast": {…}}` — bare auto-wrapped |
| **homes** | **flat JSON, no envelope** |
| **content-pages** | **`{"content_page": {…}}` exactly** — bare attributes and extra top-level keys are rejected locally, before the request |

**City selectors are a UUID or a state-qualified slug.** `deltona-fl`, `austin-tx`, `tampa-fl` — never a bare `deltona`. Slugs cost an extra `cities:read` lookup to resolve; UUIDs skip it. Some commands (`neighborhoods`, `listicles`, `places`, `email-templates`) **require** `--city` on every operation, and several accept a `<city>/<slug>` shorthand for show.

**`--data` accepts three forms:** inline JSON (`--data '{"job":{…}}'`), a file (`--data @payload.json`), or stdin (`echo '{…}' | listex …`). Prefer a file or stdin for anything with quotes or newlines.

**Lifecycle changes use dedicated verbs, not `update`.** `publish`, `archive`, `unpublish`, `enable`/`disable`, `feature`/`unfeature`, `status`, `set-default` all hit their own endpoints. Setting a status field via `update` is not equivalent.

**Pagination** is `--page <n>` and `--per-page <n>` (default 20, max 100) on every list.

**Exit codes** are `0` success, `1` for anything else (missing config, validation, API error, not found). Check the exit code; don't infer success from output.

## `listex help <command>` is authoritative

Every command ships detailed help covering usage, flags, behavior notes, and examples. It is generated from the same source as the CLI's own routing, so it never drifts. **Run `listex help <command>` rather than guessing a flag name** — it is cheap and current. The references below capture the workflows and gotchas that help text doesn't cover.

## Command index

| Command | Purpose | Detail |
|---------|---------|--------|
| `cities` | List/show cities, enable/disable, toggle feature flags | [references/content.md](references/content.md) |
| `jobs` | Job listings; `match` for dedupe, `enrich` | [references/content.md](references/content.md) |
| `homes` | Home listings; `upsert` by zpid, `status`, `feature` | [references/content.md](references/content.md) |
| `news` | News articles; `match`, `publish`, `archive` | [references/content.md](references/content.md) |
| `events` | Events; `match`, `publish`, `archive` | [references/content.md](references/content.md) |
| `tips` | User-submitted city tips (triage queue) | [references/content.md](references/content.md) |
| `zip-codes` | ZIP codes and demographics (read-only) | [references/content.md](references/content.md) |
| `neighborhoods` | City neighborhoods | [references/city-scoped.md](references/city-scoped.md) |
| `listicles` | City listicles + embedded item reordering | [references/city-scoped.md](references/city-scoped.md) |
| `places` | City places (restaurants, parks, …) | [references/city-scoped.md](references/city-scoped.md) |
| `content-pages` | Site-wide and city-scoped editorial pages | [references/city-scoped.md](references/city-scoped.md) |
| `audiences` | Email audiences | [references/email.md](references/email.md) |
| `email-templates` | Per-city MJML templates | [references/email.md](references/email.md) |
| `broadcasts` | Broadcasts, test sends, delivery logs | [references/email.md](references/email.md) |
| `weekly` | Weekly city broadcast workflow | [references/email.md](references/email.md) |
| `configure` | Environments and credentials | (above) |

## Key workflows

- **Never create a job, news article, or event without checking for duplicates first.** Use the `match` subcommand — see [references/content.md](references/content.md#dedupe-before-create).
- **Weekly newsletter** — resolve city, confirm audience, test, then schedule. See [references/email.md](references/email.md#weekly-broadcast-runbook).
