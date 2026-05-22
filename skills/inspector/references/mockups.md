# inspector mockups

Generate detailed ASCII mockups of **every** UI surface proposed in an OpenSpec change. Where `/inspector explain` includes a single summary wireframe, `mockups` produces a comprehensive set covering every screen, modal, component, and state.

This is a read-only operation. The only file written is `openspec/changes/<change-id>/inspector-mockups.md`.

## Inputs

- **Arg form**: `/inspector mockups <change-id>` — use the provided change ID directly.
- **No arg**: list active changes (`ls openspec/changes/` minus `archive/`) and ask the user which to mockup.
- If the given change-id doesn't exist under `openspec/changes/`, stop and report.

## Workflow

### 1. Pre-read all files (parallel)

Read everything in a single parallel batch:

**Change artifacts** (from `openspec/changes/<change-id>/`):
- `proposal.md` (requirements, user stories, acceptance criteria)
- `design.md` (if present — component decisions, layout notes)
- `tasks.md` (implementation plan — identifies which screens/components are built)
- All delta specs under `specs/<capability>/spec.md`

**Surrounding context** (parallel with above):
- **Canonical specs**: for each capability the change touches, read `openspec/specs/<capability>/spec.md` to understand pre-change UI state.
- **Existing templates/components**: use Grep/Glob to find related `.heex`, `.html`, `.jsx`, `.tsx`, `.vue`, `.astro` files. Read them to understand current layout, component structure, and naming patterns.
- **Routes**: find and read the router to understand URL structure and navigation paths.

### 2. Identify all UI surfaces

From the artifacts, enumerate every distinct UI surface the change introduces or modifies:

- **Pages** — full-page views (e.g., index, show, new, edit)
- **Modals/Dialogs** — overlay interactions (e.g., confirm delete, create form)
- **Components** — reusable pieces (e.g., card, table row, status badge)
- **States** — key variations of the same surface (e.g., empty state, loading, error, populated, disabled)
- **Responsive breakpoints** — if the change specifies mobile/tablet behavior, mock those too

Create a numbered inventory before drawing anything. Include the inventory in the output.

### 3. Generate mockups

Write `openspec/changes/<change-id>/inspector-mockups.md` with this structure:

```markdown
# Mockups — <change-id>

**Generated:** <YYYY-MM-DD>

## Inventory

| # | Surface | Type | Notes |
|---|---------|------|-------|
| 1 | Project list page | Page | New page, index view |
| 2 | Project list — empty state | State | No projects yet |
| 3 | Create project modal | Modal | Triggered from list page |
| 4 | Project detail page | Page | Show view with tabs |
| 5 | Delete confirmation dialog | Modal | Destructive action |
| ... | ... | ... | ... |

## Mockups

### 1. Project list page

Route: `/projects`

```
┌─────────────────────────────────────────────────────┐
│ ☰  App Name                        user@email ▾     │
├──────────┬──────────────────────────────────────────┤
│          │                                          │
│ Dashboard│  Projects                    [+ Create]  │
│ Projects │  ─────────────────────────────────────   │
│ Settings │                                          │
│          │  ┌─────────────────────────────────────┐ │
│          │  │ Name          Status     Created    │ │
│          │  ├─────────────────────────────────────┤ │
│          │  │ Acme Corp     ● Active   2024-01-15 │ │
│          │  │ Beta Inc      ● Active   2024-02-20 │ │
│          │  │ Test Project  ○ Draft    2024-03-01 │ │
│          │  └─────────────────────────────────────┘ │
│          │                                          │
│          │  ← 1 2 3 →                               │
│          │                                          │
└──────────┴──────────────────────────────────────────┘
```

**Key elements:**
- Sidebar navigation with current page highlighted
- Table with sortable columns
- Status indicator (● filled = active, ○ empty = draft)
- Pagination controls
- Create button top-right

### 2. Project list — empty state

Route: `/projects`

```
┌─────────────────────────────────────────────────────┐
│ ☰  App Name                        user@email ▾     │
├──────────┬──────────────────────────────────────────┤
│          │                                          │
│ Dashboard│  Projects                    [+ Create]  │
│ Projects │  ─────────────────────────────────────   │
│ Settings │                                          │
│          │         ┌───────────────────┐            │
│          │         │                   │            │
│          │         │   No projects     │            │
│          │         │   yet.            │            │
│          │         │                   │            │
│          │         │  [Create first →] │            │
│          │         │                   │            │
│          │         └───────────────────┘            │
│          │                                          │
└──────────┴──────────────────────────────────────────┘
```

**Key elements:**
- Same shell/nav as populated state
- Centered empty state with CTA

...continue for each surface in the inventory...
```

### Section rules for each mockup

Each mockup entry MUST include:
1. **Title** with inventory number
2. **Route** or trigger (URL path, or "triggered from X")
3. **ASCII wireframe** — the actual mockup
4. **Key elements** — bulleted list calling out interactive elements, data shown, and behaviors

### Mockup conventions

- Use box-drawing characters: `┌ ┐ └ ┘ ├ ┤ ┬ ┴ ┼ │ ─`
- Use `[Button Text]` for buttons and CTAs
- Use `[________]` for text inputs
- Use `[▾]` or `▾` for dropdowns/selects
- Use `☐` for unchecked checkboxes, `☑` for checked
- Use `○` for unselected radio buttons, `●` for selected
- Use `░░░░░` for placeholder/content areas
- Use `●` / `○` for status indicators
- Use `☰` for hamburger/menu icons
- Use `←` `→` `▲` `▼` for navigation arrows
- Use `(new)` or `(changed)` annotations for elements this change introduces
- Keep mockups under 60 chars wide for terminal readability
- Show realistic sample data, not "lorem ipsum"
- Include header/navigation chrome to show context
- Label ALL interactive elements

### State coverage

For each page or component, consider and mock (where applicable):
- **Default/populated** — normal usage with data
- **Empty** — no data yet, first-run experience
- **Loading** — if async data fetch is involved
- **Error** — validation errors, failed states
- **Disabled/restricted** — permission-gated elements

Only mock states that the change actually specifies or implies. Do not invent states the proposal doesn't mention.

### 4. Summarize in chat

After writing, print to chat:
- Total number of surfaces mocked
- List the surfaces by name
- Path to the full mockups file
- One line: "Run `/inspector flows <change-id>` for process workflow diagrams."

## Guardrails

- **Read-only on OpenSpec**: do not edit `proposal.md`, `tasks.md`, `design.md`, or any delta spec.
- **No td issues, no git commits, no branch changes**: mockups is a pure documentation tool.
- **Accuracy over aesthetics**: only mock UI that the change artifacts describe. Do not invent screens or features not in the proposal.
- **Scope to this change**: do not mock unrelated parts of the application.
- **Realistic data**: use plausible sample data that matches the domain, not generic placeholders.
