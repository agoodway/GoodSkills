# Inspector Review-Update Report Template

Use this structure when writing `openspec/changes/<change-id>/inspector-review-update.md`. Replace bracketed placeholders. Keep empty severity sections as `_None._`.

```markdown
# Inspector Review-Update — <change-id>

**Reviewed:** <YYYY-MM-DD>
**Reviewer:** inspector-review-update
**Mode:** <ask | auto>
**Verdict:** <Ready to implement | Needs revision | Blocked>

## Summary

<2–4 sentences: what the change proposes, overall health after patches, headline remaining issue if any.>

**Original counts:** Critical: N · Warning: N · Suggestion: N
**Patches:** Auto-patched: N · User-guided: M · Model-recommended: P · Skipped: K

## Scope inspected

- Proposal: `openspec/changes/<id>/proposal.md`
- Design: `openspec/changes/<id>/design.md` <or "(none)">
- Tasks: `openspec/changes/<id>/tasks.md`
- Deltas:
  - `openspec/changes/<id>/specs/<capability>/spec.md`
- Canonical specs consulted:
  - `openspec/specs/<capability>/spec.md`
- Other active changes consulted: <list or "none">

## Patches applied

N findings were auto-patched. M were patched after user guidance. P were patched from model recommendations. K were skipped.

### Auto-patched

1. **<title>** — `file:line` → <what was changed>

### User-guided patches

1. **<title>** — `file:line` → <what was changed> (user chose: <summary>)

_Omit this subsection when mode is `auto` and M is 0._

### Model-recommended patches

1. **<title>** — `file:line` → <what was changed>
   - **Chose:** <recommended option>
   - **Rationale:** <1–2 sentences>

_Omit this subsection when mode is `ask` and P is 0._

### Skipped

1. **<title>** — `file:line` → <why skipped; if auto mode, what human input is still needed>

## Critical

_Only unpatched remaining findings._

1. **<short title>** — `path/to/file:line`
   - **Finding:** <what is wrong>
   - **Evidence:** <quote or cite>
   - **Suggested fix:** <concrete action>

## Warning

1. **<short title>** — `path/to/file:line`
   - **Finding:** <what is wrong>
   - **Suggested fix:** <concrete action>

## Suggestion

1. **<short title>** — `path/to/file:line`
   - <what and why>

## Alignment notes

- **Other active changes:** <conflict/no conflict, with citations>
- **Canonical specs:** <consistent/drifted, with citations>
- **Codebase assumptions verified:** <yes / list of verified items>

## What looks good

<Bulleted list of things the change gets right.>
```
