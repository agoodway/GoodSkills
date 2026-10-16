# Tango

Work with Tango -- per-tenant OAuth connections from a Phoenix app to third-party APIs.

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

| Subcommand      | Purpose                                                                           |
|-----------------|-----------------------------------------------------------------------------------|
| `bootstrap`     | Add Tango to a Phoenix app (dep, config, encryption key, install migration)       |
| `providers`     | Add OAuth2 providers from the Nango catalog or a custom config                    |
| `flow`          | Server-side redirect flow: `create_session`, `authorize_url`, `exchange_code`     |
| `authorization` | Popup completion: verifier, `multi_finalize_authorization`, cleanup               |
| `api`           | Mount `Tango.API.Router` with API key, tenant, and CORS settings                  |
| `liveview`      | Add `Tango.Live.OAuthComponent` and the `TangoOAuth` JS hook                      |
| `connections`   | Read, refresh, revoke connections and report provider auth failures               |
| `upgrade`       | Pinned schema upgrades and migrating a legacy popup callback                      |
| `debug`         | Diagnose error atoms, origin/repo mismatches, and missing callbacks               |
