# implement-openspec-changes

Implement one or more OpenSpec changes through a gated pipeline: apply, verify, fix all verify findings, run goodreview, fix all review findings, then git commit. Each pipeline step runs in its own subagent.

## Install

Install this skill globally:

```bash
npx skills add agoodway/GoodSkills --skill implement-openspec-changes -g
```

Install into the current project:

```bash
npx skills add agoodway/GoodSkills --skill implement-openspec-changes
```

Requires `openspec-apply-change` and `openspec-verify-change` from OpenSpec, plus the GoodSkills `goodreview` and `git` skills.

## Usage

```
/implement-openspec-changes [change-id ...]
```

Example:

```
/implement-openspec-changes copy-unassigned-athena-doc-to-chart
```
