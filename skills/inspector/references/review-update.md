# inspector review-update (legacy stub)

> **Moved.** This subcommand is now the standalone skill **`inspector-review-update`**.
>
> Prefer:
>
> ```text
> /inspector-review-update [change-id] [--ask | --auto]
> ```
>
> Or keep the legacy entry point (dispatcher only):
>
> ```text
> /inspector review-update [change-id] [--ask | --auto]
> ```
>
> Both should load and follow the `inspector-review-update` skill.

## What changed

| Before | After |
|--------|--------|
| Workflow lived only under `inspector/references/review-update.md` | Full workflow in skill `inspector-review-update` |
| Always asked the user about design-decision findings | **`--ask`** (interactive) or **`--auto`** (model applies recommended answers) |
| Report often written as `inspector-review.md` | Report: `openspec/changes/<change-id>/inspector-review-update.md` |

## Modes (summary)

- **`ask`** — auto-patch mechanical findings; ask one design question at a time.
- **`auto`** — auto-patch mechanical findings; for design questions, apply the model's recommended option and record rationale. Skip only when product intent is truly unknowable.

If mode is omitted, the standalone skill asks which mode to use.

## Install

```bash
npx skills add agoodway/GoodSkills --skill inspector-review-update -g
```

## Fallback

If you cannot load `inspector-review-update`, stop and request install. Do not invent a partial workflow here — the source of truth is the standalone skill.
