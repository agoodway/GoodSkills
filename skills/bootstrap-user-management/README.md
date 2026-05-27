# Bootstrap User Management

Add account member management (list, invite, remove) to a Phoenix 1.8 app with existing multi-tenant accounts.

## Install

Install this skill globally:

```bash
npx skills add agoodway/GoodSkills --skill bootstrap-user-management -g
```

Install into the current project:

```bash
npx skills add agoodway/GoodSkills --skill bootstrap-user-management
```

## Prerequisites

- `/bootstrap-accounts` already run (accounts, account_users tables, schemas, contexts)
- `phx.gen.auth` already run
- DaisyUI installed

## Usage

```
/bootstrap-user-management
```
