# openspec-ship

Ship one or more OpenSpec changes through a fixed pipeline. Rebase the current branch onto `origin/main`, then apply, verify, fix every verify issue, run goodreview, fix every review issue, archive after syncing specs, and commit. After the named changes finish, open one draft pull request for the commits this run made.

## Install

Install this skill globally:

```bash
npx skills add agoodway/GoodSkills --skill openspec-ship -g
```

Install into the current project:

```bash
npx skills add agoodway/GoodSkills --skill openspec-ship
```

Requires `openspec-apply-change`, `openspec-verify-change`, `openspec-archive-change`, and `openspec-sync-specs` from OpenSpec, plus the GoodSkills `goodreview` and `git` skills.

## Usage

```
/openspec-ship [change-id ...]
```

Example:

```
/openspec-ship copy-unassigned-athena-doc-to-chart
```

Run it in the app repo that contains `openspec/changes/`. If no change name is given, the skill lists active changes and asks which ones to ship. An optional `--store <id>` is passed through to every OpenSpec command.
