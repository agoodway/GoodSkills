# listex

Agent guide for the **listex** Rust CLI — manage the Listex / Yocal city platform via its v2 API: cities, jobs, homes, news, events, tips, neighborhoods, listicles, places, content pages, ZIP demographics, and the email stack (audiences, templates, broadcasts, weekly sends).

## Install skill

Install this skill globally:

```bash
npx skills add agoodway/skills --skill listex -g
```

Install into the current project:

```bash
npx skills add agoodway/skills --skill listex
```

## Install CLI

The skill expects the `listex` binary on `PATH` (typically `~/.local/bin/listex`).

From a release:

```bash
curl -fsSL https://raw.githubusercontent.com/agoodway/listex/main/cli-rust/install.sh | sh
```

From a local checkout of the [listex](https://github.com/agoodway/listex) repo (`cli-rust/` is the canonical tree; the Zig `cli/` tree is deprecated):

```bash
cd cli-rust && just release && LISTEX_LOCAL_BIN=./target/release/listex ./install.sh
```

Windows uses `install.ps1`, which supports `LISTEX_LOCAL_BIN` the same way.

Confirm:

```bash
listex --version
listex configure show
```

## Configure

Config lives at `~/.listex.json` and supports multiple environments. Base URLs must include the `/api/v2` prefix.

```bash
listex configure set --env dev  --base-url http://localhost:4000/api/v2 --api-key <key>
listex configure set --env prod --base-url https://yocal.vip/api/v2     --api-key <key>
listex configure use prod
listex configure show   # API keys are masked
```

Override per-invocation with `--env <name>`.

## Contents

| File | Purpose |
|------|---------|
| `SKILL.md` | Binary resolution, config, safety rules, envelope table, command index |
| `references/content.md` | `cities`, `jobs`, `homes`, `news`, `events`, `tips`, `zip-codes` — plus the dedupe-before-create workflow |
| `references/city-scoped.md` | `neighborhoods`, `listicles`, `places`, `content-pages` — the `--city` requirement and content-pages' strict validation |
| `references/email.md` | `audiences`, `email-templates`, `broadcasts`, `weekly` — plus the weekly broadcast runbook |

## Notes for agents

- `listex help <command>` is authoritative and generated from the CLI's own source — run it instead of guessing a flag.
- Use `--json` for anything you parse; bare output is human-readable tables.
- Request envelopes vary per resource (`homes` is flat, `content-pages` is strict). See the table in `SKILL.md`.
- City selectors are UUIDs or **state-qualified** slugs (`deltona-fl`, not `deltona`).
- `broadcasts test` sends real email. `send`, `weekly send --send`, and all `delete`s are irreversible — get explicit user confirmation first, and never add `--confirm` on your own initiative.
