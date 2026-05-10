# Horde

Set up distributed process infrastructure using Horde -- a cluster-wide registry and dynamic supervisor for Elixir/Phoenix apps.

## Install

Install this skill globally:

```bash
npx skills add agoodway/GoodSkills --skill horde -g
```

Install into the current project:

```bash
npx skills add agoodway/GoodSkills --skill horde
```

## Usage

```
/horde help
```

## Subcommands

| Subcommand | Purpose |
|------------|---------|
| `bootstrap` | Add Horde to a Phoenix app (deps, registry, supervisor, cluster monitor, supervision tree) |
| `add <Module>` | Add Horde registration to an existing GenServer (via tuple, lookup, ensure_started) |
| `singleton <Module>` | Create a cluster-wide singleton GenServer managed by Horde |
