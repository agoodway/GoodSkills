# Tango

Work with Tango -- per-tenant OAuth connections and optional one-time external identity proofs from a Phoenix app.

## Install

Install this skill globally:

```bash
npx skills add agoodway/GoodSkills --skill tango -g
```

Install into the current project:

```bash
npx skills add agoodway/GoodSkills --skill tango
```

## Usage

```
/tango help
```

## Subcommands

| Subcommand      | Purpose                                                                                    |
| --------------- | ------------------------------------------------------------------------------------------ |
| `bootstrap`     | Add Tango to a Phoenix app (dep, config, encryption key, install migration)                |
| `providers`     | Add OAuth2 providers from the Nango catalog or a custom config; request options            |
| `flow`          | Server-side redirect flow: `create_session`, `authorize_url`, `exchange_code`              |
| `authorization` | Popup completion: verifier, connection finalization or one-time proof consumption, cleanup |
| `consume`       | One-time account or organization-admin proof without a durable connection (0.4.1)          |
| `api`           | Mount `Tango.API.Router` with API key, tenant, and CORS settings                           |
| `liveview`      | Add `Tango.Live.OAuthComponent` and the `TangoOAuth` JS hook                               |
| `connections`   | Credential-free info, generation locks, refresh policy and tenant-scoped revoke            |
| `testing`       | Consumer provider/connection fixtures with explicit nullable fields                        |
| `upgrade`       | Release-to-schema map, pinned migrations, verification, and rollback                       |
| `debug`         | Diagnose error atoms, origin/repo mismatches, and missing callbacks                        |

For one-time account links or organization administrator proofs without a durable Tango connection, see [references/consumption.md](references/consumption.md). This requires the verified 0.4.1 API and revised V04 schema; check [references/upgrading.md](references/upgrading.md) before adoption.
