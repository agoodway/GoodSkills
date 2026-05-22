# inspector flows

Generate detailed ASCII diagrams of **every** process workflow proposed in an OpenSpec change. Where `/inspector explain` includes a summary architecture diagram, `flows` produces a comprehensive set covering every user flow, data pipeline, state machine, and system interaction.

This is a read-only operation. The only file written is `openspec/changes/<change-id>/inspector-flows.md`.

## Inputs

- **Arg form**: `/inspector flows <change-id>` — use the provided change ID directly.
- **No arg**: list active changes (`ls openspec/changes/` minus `archive/`) and ask the user which to diagram.
- If the given change-id doesn't exist under `openspec/changes/`, stop and report.

## Workflow

### 1. Pre-read all files (parallel)

Read everything in a single parallel batch:

**Change artifacts** (from `openspec/changes/<change-id>/`):
- `proposal.md` (requirements, user stories, acceptance criteria)
- `design.md` (if present — architectural decisions, sequence descriptions)
- `tasks.md` (implementation plan — reveals processing steps and order)
- All delta specs under `specs/<capability>/spec.md`

**Surrounding context** (parallel with above):
- **Canonical specs**: for each capability the change touches, read `openspec/specs/<capability>/spec.md` to understand pre-change behavior.
- **Existing code**: use Grep/Glob to find related modules, contexts, workers, controllers, LiveViews. Read enough to understand current process flows.
- **Supervision trees / Oban workers / GenServers**: search for background processing that the change introduces or modifies.

### 2. Identify all flows

From the artifacts, enumerate every distinct process the change introduces or modifies:

- **User flows** — step-by-step user journeys (e.g., signup, purchase, onboarding)
- **Data flows** — how data moves through the system (e.g., ingest → validate → transform → store)
- **Request/response cycles** — HTTP or WebSocket interactions (e.g., API call → auth → context → response)
- **Background processes** — async jobs, scheduled tasks, event handlers (e.g., Oban worker pipeline)
- **State machines** — entities with lifecycle states (e.g., draft → published → archived)
- **Event chains** — telemetry events, PubSub broadcasts, webhook cascades
- **Error/retry flows** — what happens on failure, retry logic, dead letter handling

Create a numbered inventory before drawing anything. Include the inventory in the output.

### 3. Generate flow diagrams

Write `openspec/changes/<change-id>/inspector-flows.md` with this structure:

```markdown
# Flows — <change-id>

**Generated:** <YYYY-MM-DD>

## Inventory

| # | Flow | Type | Notes |
|---|------|------|-------|
| 1 | User creates a project | User flow | Happy path + validation errors |
| 2 | Webhook delivery pipeline | Data flow | Ingest → queue → deliver → retry |
| 3 | Project lifecycle | State machine | draft → active → archived |
| 4 | Nightly usage aggregation | Background | Oban cron worker |
| ... | ... | ... | ... |

## Flows

### 1. User creates a project

Type: **User flow**
Actors: User, Browser, Server, Database

```
User              Browser            Server             Database
 │                  │                  │                   │
 │  fills form      │                  │                   │
 │─────────────────▶│                  │                   │
 │                  │  POST /projects  │                   │
 │                  │─────────────────▶│                   │
 │                  │                  │  validate params   │
 │                  │                  │──┐                 │
 │                  │                  │◀─┘                 │
 │                  │                  │                    │
 │                  │                  │  INSERT project    │
 │                  │                  │───────────────────▶│
 │                  │                  │    {:ok, project}  │
 │                  │                  │◀───────────────────│
 │                  │                  │                    │
 │                  │  redirect /projects/:id               │
 │                  │◀─────────────────│                    │
 │  sees detail     │                  │                    │
 │◀─────────────────│                  │                    │
```

**Steps:**
1. User fills out the create project form
2. Browser submits POST to `/projects`
3. Server validates params — on failure, re-renders form with errors
4. Server inserts project into database
5. On success, redirects to project detail page

**Error path:**
- Validation failure → re-render form with `changeset.errors`
- Database constraint violation → flash error, re-render form

### 2. Webhook delivery pipeline

Type: **Data flow**

```
┌──────────┐     ┌───────────┐     ┌───────────┐     ┌──────────┐
│ Ingest   │────▶│ Validate  │────▶│ Enqueue   │────▶│ Deliver  │
│ endpoint │     │ payload   │     │ Oban job  │     │ webhook  │
└──────────┘     └─────┬─────┘     └───────────┘     └────┬─────┘
                       │                                   │
                       ▼                                   ▼
                 ┌───────────┐                       ┌───────────┐
                 │ Reject    │                       │ Retry     │
                 │ 422       │                       │ w/ backoff│
                 └───────────┘                       └─────┬─────┘
                                                           │
                                                           ▼ (max 5)
                                                     ┌───────────┐
                                                     │ Dead      │
                                                     │ letter    │
                                                     └───────────┘
```

**Steps:**
1. External system sends payload to ingest endpoint
2. Validate schema and auth — reject with 422 if invalid
3. Enqueue Oban job for async delivery
4. Worker delivers webhook to target URL
5. On failure, retry with exponential backoff (max 5 attempts)
6. After max retries, move to dead letter for manual review

### 3. Project lifecycle

Type: **State machine**
Entity: `Project`

```
                    create
                      │
                      ▼
                 ┌─────────┐
                 │  draft   │
                 └────┬─────┘
                      │ publish
                      ▼
                 ┌─────────┐    suspend     ┌───────────┐
                 │  active  │──────────────▶│ suspended │
                 └────┬─────┘               └─────┬─────┘
                      │                           │ reactivate
                      │ archive                   │
                      ▼                           ▼
                 ┌─────────┐              (back to active)
                 │ archived │
                 └──────────┘
```

**Transitions:**
| From | Event | To | Guard |
|------|-------|----|-------|
| — | create | draft | — |
| draft | publish | active | has required fields |
| active | suspend | suspended | admin only |
| active | archive | archived | no active subscriptions |
| suspended | reactivate | active | admin only |

...continue for each flow in the inventory...
```

### Diagram type conventions

**Sequence diagrams** (for request/response and user flows):
- Actors across the top, separated by columns
- Time flows downward
- Use `│` for lifelines, `─────▶` for messages
- Use `──┐` / `◀─┘` for self-calls
- Label every arrow

**Flowcharts** (for data flows and pipelines):
- Use boxes: `┌───┐ │   │ └───┘`
- Use arrows: `──▶`, `──▶`, `▼`, `▲`
- Branch with decision diamonds or labeled fork arrows
- Show error/failure paths branching off the main flow

**State diagrams** (for lifecycles):
- States in boxes: `┌────────┐ │ state  │ └────────┘`
- Transitions as labeled arrows between states
- Include a transitions table with From, Event, To, Guard columns

**Architecture diagrams** (for system interactions):
- Components in boxes
- Arrows showing data direction
- Label protocols/transports (HTTP, PubSub, SQL, etc.)

### Section rules for each flow

Each flow entry MUST include:
1. **Title** with inventory number
2. **Type** label (user flow, data flow, state machine, background process, etc.)
3. **Actors or components** involved (listed before the diagram)
4. **ASCII diagram** — the actual flow visualization
5. **Steps** — numbered prose walkthrough of the flow
6. **Error paths** — what happens on failure (if applicable)

### General conventions

- Use box-drawing characters: `┌ ┐ └ ┘ ├ ┤ ┬ ┴ ┼ │ ─`
- Use arrows: `──▶`, `◀──`, `▼`, `▲`
- Label EVERY arrow and box — no unlabeled elements
- Keep diagrams under 70 chars wide for terminal readability
- Use `(new)` or `(changed)` annotations for elements this change introduces
- Show realistic function/module names from the codebase where known
- Include timing/async markers where relevant (e.g., "async", "5s timeout")

### 4. Summarize in chat

After writing, print to chat:
- Total number of flows diagrammed
- List the flows by name and type
- Path to the full flows file
- One line: "Run `/inspector mockups <change-id>` for UI wireframes."

## Guardrails

- **Read-only on OpenSpec**: do not edit `proposal.md`, `tasks.md`, `design.md`, or any delta spec.
- **No td issues, no git commits, no branch changes**: flows is a pure documentation tool.
- **Accuracy over aesthetics**: only diagram processes that the change artifacts describe. Do not invent flows not in the proposal.
- **Scope to this change**: do not diagram unrelated parts of the system.
- **Use real names**: reference actual module names, function names, and routes from the codebase where they exist or are specified in the change.
