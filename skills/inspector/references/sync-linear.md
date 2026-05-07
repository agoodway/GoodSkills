# inspector sync-linear

Sync an OpenSpec change to a Linear issue. Creates a new issue if none is linked, or updates the existing one with the current local state.

Writes a `linear-ref.md` tracker file in the change directory so future runs skip the search step.

## Inputs

- **Arg form**: `/inspector sync-linear <change-id>` — use the provided change ID directly.
- **No arg**: list active changes (`ls openspec/changes/` minus `archive/`) and ask the user which to sync.
- If the given change-id doesn't exist under `openspec/changes/`, stop and report.

## Workflow

### 1. Load the change

Read the key artifacts from `openspec/changes/<change-id>/`:
- `proposal.md` — extract the H1 title and full body
- `tasks.md` — extract task groups and checkbox state
- `linear-ref.md` — if it exists, read the stored Linear issue identifier

Count tasks: total, completed (`- [x]`), remaining (`- [ ]`).

### 2. Resolve the Linear issue

**If `linear-ref.md` exists** and contains an identifier (e.g. `GW-123`):
- Fetch the issue via the runtime's Linear integration if available. If no Linear MCP/tool is configured, stop and tell the user Linear is not configured.
- If found, proceed to step 3 (update path).
- If not found (deleted/moved), warn the user, remove the stale `linear-ref.md`, and fall through to the search path.

**If no `linear-ref.md`**:
- Search Linear with the runtime's Linear integration if available. If no Linear MCP/tool is configured, stop and tell the user Linear is not configured. Search using:
  - `query`: the change-id (kebab-case, which should match title keywords)
  - `label`: `openspec` (if the label exists)
- If exactly one match is found whose title closely matches the proposal title, confirm with the user via the runtime's question mechanism: "Found existing issue <ID> — <title>. Link this to change `<change-id>`?"
  - If confirmed, write `linear-ref.md` and proceed to step 3 (update).
  - If denied, proceed to step 4 (create).
- If zero matches or multiple ambiguous matches, proceed to step 4 (create).

### 3. Update the existing issue

Build the updated description (see **Description format** below).

Call the runtime's Linear save/update issue tool with:
- `id`: the stored identifier
- `description`: the rebuilt description

Do NOT update the title unless the proposal H1 has changed from what's currently on the issue — compare before updating to avoid churn.

Print a summary: "Updated <ID> — <completed>/<total> tasks complete."

Write the report file and stop.

### 4. Create a new issue

Before creating, ask the user which team to use via the runtime's question mechanism if not determinable from context (e.g. a `.linear.toml` in the project, or prior sync-linear runs in the same project). Cache the team choice in memory for the session.

Build the description (see **Description format** below).

Call the runtime's Linear save/create issue tool with:
- `title`: the H1 from `proposal.md`, prefixed with `[OpenSpec]` (e.g. `[OpenSpec] Add buyer outbound frequency caps`)
- `team`: the resolved team
- `description`: the built description
- `labels`: `["openspec"]`

From the response, extract the issue identifier.

Write `linear-ref.md` to `openspec/changes/<change-id>/linear-ref.md` with this content:

```markdown
---
linear-issue: <IDENTIFIER>
synced: <YYYY-MM-DD>
---
```

Print a summary: "Created <ID> — <title>. Linked via linear-ref.md."

Write the report file and stop.

## Description format

Build the Linear issue description as markdown:

```markdown
## Why

<The "Why" section from proposal.md, or the first paragraph if no explicit Why heading>

## What

<The "What" section from proposal.md, or a summary if no explicit What heading>

## Tasks

<Copy the full tasks.md content with checkbox state preserved>

---

*Synced from OpenSpec change `<change-id>` on <YYYY-MM-DD>.*
```

Keep descriptions under 10,000 characters. If the proposal is very long, summarize the What section and link to the local file path.

## Report file

Write a brief report to `openspec/changes/<change-id>/inspector-sync-linear.md`:

```markdown
# Inspector Sync-Linear — <change-id>

**Synced:** <YYYY-MM-DD>
**Action:** <Created | Updated>
**Linear issue:** <IDENTIFIER>
**Tasks:** <completed>/<total> complete

## Details

- Title: <issue title>
- Team: <team name>
- Labels: openspec
- Description length: <N> chars
```

## Guardrails

- **Read-only on OpenSpec content files**: never modify `proposal.md`, `tasks.md`, `design.md`, or delta specs. The only files written are `linear-ref.md` (tracker) and `inspector-sync-linear.md` (report).
- **One issue per change**: never create a second issue if one is already linked.
- **Confirm before linking**: if matching an existing issue by search, always confirm with the user.
- **Confirm team on first create**: ask the user which team to use if it can't be determined from project config.
- **Idempotent updates**: running sync-linear twice in a row with no local changes should produce no meaningful diff on the Linear side.
