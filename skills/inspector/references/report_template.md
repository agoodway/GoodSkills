# Inspector Review Report Template

Use this exact structure when writing `openspec/changes/<change-id>/inspector-review.md`. Replace bracketed placeholders. Omit sections that have zero findings (keep the heading and write `_None._`).

```markdown
# Inspector Review — <change-id>

**Reviewed:** <YYYY-MM-DD>
**Reviewer:** inspector/review
**Verdict:** <Ready to implement | Needs revision | Blocked>

## Summary

<2–4 sentences: what the change proposes, overall health, and the headline issue if any.>

**Counts:** Critical: N · Warning: N · Suggestion: N

## Scope inspected

- Proposal: `openspec/changes/<id>/proposal.md`
- Design: `openspec/changes/<id>/design.md` <or "(none)">
- Tasks: `openspec/changes/<id>/tasks.md`
- Deltas:
  - `openspec/changes/<id>/specs/<capability>/spec.md`
- Canonical specs consulted:
  - `openspec/specs/<capability>/spec.md`
- Other active changes consulted: <list or "none">

## Critical

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

## Clarifying questions

Numbered list of questions the change author must answer before this review can be fully resolved. Use for genuine ambiguities the reviewer cannot decide alone: unclear scope, missing rationale, undefined acceptance criteria, unstated trade-offs. Skip questions you can answer yourself by reading the code or specs. Each question should cite the artifact that prompted it.

1. **<short title>** — `path/to/file:line`
   - <the question, phrased so a yes/no or short answer resolves it>
   - **Why it matters:** <what decision is blocked until this is answered>

## Alignment notes

- **Other active changes:** <conflict/no conflict, with citations>
- **Canonical specs:** <consistent/drifted, with citations>
- **Codebase assumptions verified:** <yes / list of verified items>

## What looks good

<Bulleted list of things the change gets right — do not skip this; it calibrates the findings and saves the reader time.>
```
