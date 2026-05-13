# CanOpener

Create and update Elixir API client packages using CanOpener compile-time OpenAPI code generation.

## Install

Install this skill globally:

```bash
npx skills add agoodway/GoodSkills --skill can-opener -g
```

Install into the current project:

```bash
npx skills add agoodway/GoodSkills --skill can-opener
```

## Usage

```
/can-opener help
```

## Subcommands

| Subcommand | Purpose |
|------------|---------|
| `bootstrap` | Scaffold a new Elixir API client package from an OpenAPI spec |
| `update` | Update the OpenAPI spec and regenerate the client |
