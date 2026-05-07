# inspector explain

Explain a single OpenSpec change using a combination of **prose**, **ASCII diagrams**, and **ASCII mockups** so that any team member can quickly understand what the change does, why it matters, and how it affects the system.

This is a read-only operation. The only file written is `openspec/changes/<change-id>/inspector-explain.md`.

## Inputs

- **Arg form**: `/inspector explain <change-id>` — use the provided change ID directly.
- **No arg**: list active changes (`ls openspec/changes/` minus `archive/`) and ask the user which to explain.
- If the given change-id doesn't exist under `openspec/changes/`, stop and report.

## Workflow

### 1. Pre-read all files (parallel)

Read everything in a single parallel batch:

**Change artifacts** (from `openspec/changes/<change-id>/`):
- `proposal.md` (why + what)
- `design.md` (if present — architectural decisions, alternatives)
- `tasks.md` (implementation plan, checked state shows progress)
- All delta specs under `specs/<capability>/spec.md`

**Surrounding context** (parallel with above):
- **Canonical specs**: for each capability the change touches, read `openspec/specs/<capability>/spec.md` to understand the pre-change state.
- **Codebase exploration**: use Grep/Glob to find the key modules, schemas, and files the change modifies. Read enough to understand the current shape.

### 2. Generate the explanation

Write `openspec/changes/<change-id>/inspector-explain.md` with the following structure:

```markdown
# Explain — <change-id>

**Generated:** <YYYY-MM-DD>

## TL;DR

<2-3 sentences: what does this change do and why does it matter? Write for someone with zero context.>

## Context — Why this change exists

<3-5 sentences on the problem or opportunity. What's broken, missing, or needed?>

## What changes

### Data / Schema

<If the change introduces or modifies schemas, migrations, or data models, show an ASCII diagram of the before/after. If not applicable, omit this section.>

```
BEFORE:                          AFTER:
┌──────────────┐                 ┌──────────────┐
│   users      │                 │   users      │
├──────────────┤                 ├──────────────┤
│ id           │                 │ id           │
│ email        │                 │ email        │
│ name         │                 │ name         │
└──────────────┘                 │ org_id (FK)  │
                                 └──────┬───────┘
                                        │
                                 ┌──────┴───────┐
                                 │   orgs       │
                                 ├──────────────┤
                                 │ id           │
                                 │ name         │
                                 └──────────────┘
```

### System / Architecture

<If the change affects how components interact, data flows, or introduces new services/modules, show an ASCII architecture or sequence diagram.>

```
┌─────────┐     ┌──────────┐     ┌──────────┐
│ Client  │────▶│ API      │────▶│ Worker   │
└─────────┘     └──────────┘     └────┬─────┘
                                      │
                                      ▼
                                ┌──────────┐
                                │ External │
                                │ Service  │
                                └──────────┘
```

### UI / User-facing

<If the change affects a user interface, show an ASCII wireframe/mockup of the key screens or components. Show before/after if modifying existing UI.>

```
┌─────────────────────────────────────┐
│ Dashboard                    [+ New]│
├─────────────────────────────────────┤
│                                     │
│  ┌───────────┐  ┌───────────┐      │
│  │ Card A    │  │ Card B    │      │
│  │           │  │           │      │
│  │  metric   │  │  metric   │      │
│  └───────────┘  └───────────┘      │
│                                     │
│  ┌──────────────────────────────┐   │
│  │ New Component (added)        │   │
│  │ ░░░░░░░░░░░░░░░░░░░░░░░░░░ │   │
│  └──────────────────────────────┘   │
│                                     │
└─────────────────────────────────────┘
```

### Logic / Behavior

<Explain any new business rules, state machines, or behavioral changes in prose. Use an ASCII state diagram or flowchart if it clarifies transitions.>

```
[idle] ──trigger──▶ [processing] ──success──▶ [complete]
                         │
                         └──failure──▶ [failed] ──retry──▶ [processing]
```

## Implementation path

<Brief ordered list of implementation steps derived from tasks.md. Group by layer (schema → backend → frontend → tests). Keep to 5-8 bullet points max.>

## Risks & trade-offs

<2-4 bullets on what could go wrong, what was deliberately left out, or what constraints shaped the design.>

## Open questions

<Any ambiguities spotted during explanation. Omit if none.>
```

### Section selection rules

- **Include only sections that are relevant** to this specific change. A pure backend change should omit "UI / User-facing". A schema-only migration should omit "System / Architecture" if architecture doesn't change.
- **Always include**: TL;DR, Context, Implementation path.
- **Include if applicable**: Data/Schema, System/Architecture, UI/User-facing, Logic/Behavior, Risks & trade-offs, Open questions.
- **Diagrams must be accurate**: base them on actual file contents, not guesses. If you can't determine the exact shape, say what you verified and what you inferred.

### Diagram conventions

- Use box-drawing characters: `┌ ┐ └ ┘ ├ ┤ ┬ ┴ ┼ │ ─`
- Use arrows: `──▶`, `◀──`, `───`, `│`, `▼`, `▲`
- Label everything — no unlabeled boxes
- Keep diagrams under 60 chars wide for terminal readability
- Use `(new)` or `(changed)` annotations to highlight what the change introduces
- Use `░` fill for placeholder/content areas in UI mockups

### 3. Summarize in chat

After writing, print to chat:
- The TL;DR section verbatim
- Which diagram types were included (e.g. "Includes: schema diagram, UI mockup")
- Path to the full explanation file
- One line: "Run `/inspector review <change-id>` for a detailed audit."

## Guardrails

- **Read-only on OpenSpec**: do not edit `proposal.md`, `tasks.md`, `design.md`, or any delta spec.
- **No td issues, no git commits, no branch changes**: explain is a pure documentation tool.
- **Accuracy over aesthetics**: only diagram what you can verify from the actual artifacts and codebase. Do not invent details for the sake of a prettier diagram.
- **Scope to this change**: do not explain unrelated systems or propose improvements.
