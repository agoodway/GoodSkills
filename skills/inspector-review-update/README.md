# Inspector Review-Update

Quick-review an OpenSpec change, auto-patch mechanical findings, then resolve design-decision findings by asking you or by applying the model's recommended answers.

Edits stay inside the target change directory (`proposal.md`, `design.md`, `tasks.md`, and delta specs). The report is written to `openspec/changes/<change-id>/inspector-review-update.md`.

## Install

Install this skill globally:

```bash
npx skills add agoodway/GoodSkills --skill inspector-review-update -g
```

Install into the current project:

```bash
npx skills add agoodway/GoodSkills --skill inspector-review-update
```

## Usage

```
/inspector-review-update [change-id] [--ask | --auto]
```

`/inspector review-update …` is the legacy entry point and follows this skill.

Run it in the app repo that contains `openspec/changes/`. If `change-id` is omitted, the skill lists active changes and asks which one to update.

## Modes

| Flag | Behavior |
|------|----------|
| `--auto` | Default. Auto-patch mechanical findings. Apply the recommended answer for each design question and record the rationale. |
| `--ask` | Auto-patch mechanical findings. Ask one design question at a time, then apply your answer. |
| (omitted) | Same as `--auto`. A missing change-id is still chosen by you. |
