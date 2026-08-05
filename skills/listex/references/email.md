# listex — email commands

Covers `audiences`, `email-templates`, `broadcasts`, `weekly`.

> **Everything in this file can send real email.** `broadcasts test` is not a dry run — it delivers to the addresses you pass. `send` and `weekly send --send` deliver to the whole audience. Confirm with the user before running any of them, and treat `--confirm` as the user's authorization, never a flag you add to get past an error.

Run `listex help <command>` for the full flag list.

---

## Weekly broadcast runbook

`listex weekly send` is the wrapper for the whole flow: it resolves the city, loads its audience, creates a v2 broadcast, optionally sends tests, then schedules or sends.

**The safe sequence:**

```bash
# 1. Confirm the city and its audience exist
listex cities tampa-fl --json
listex audiences city tampa-fl --json

# 2. See what auto-curation would pull in (inspect content before it ships)
listex news   --city tampa-fl --status published --start-date <last-week-iso> --json
listex events --city tampa-fl --status published --start-date <today-iso> --json
listex jobs   --city tampa-fl --status active --json

# 3. Test send to internal addresses — ASK THE USER FIRST, this is real email
listex weekly send --city tampa-fl --auto-curate --test-emails ops@example.com

# 4. Schedule (preferred) — a human reviews before delivery
listex weekly send --city tampa-fl --auto-curate --schedule 2026-06-20T14:00:00Z

# 5. Only on explicit user go-ahead: immediate send
listex weekly send --city tampa-fl --auto-curate --send --confirm --json
```

**Content selection.** Either curate explicitly or let it auto-select — **without `--auto-curate`, at least one explicit content ID flag is required**:

- `--news-ids <id1,id2>` — comma-separated published news IDs
- `--event-ids <id1,id2>` — comma-separated published event IDs
- `--job-ids <id1,id2>` — comma-separated active job IDs
- `--auto-curate` — picks published news/events and active jobs automatically

Auto-curation tuning: `--news-limit <n>` (default 10), `--jobs-limit <n>` (default 5), `--events-days <n>` (event lookahead window).

**Constraints worth memorizing:**

- `--schedule` and `--send` are **mutually exclusive**.
- `--send` requires `--confirm`.
- `--city` takes a UUID or state-qualified slug and is required.
- `--json` emits a machine-readable summary only — use it when you need the resulting broadcast ID.
- `--stagger-minutes <n>` documents a delay between cities for shell loops over multiple cities; it's for automation scripts, not enforced by a single invocation.

---

## audiences

```bash
listex audiences                              # table of all audiences
listex audiences --city <uuid> --search tampa # --city here is a LIST FILTER (UUID only)
listex audiences <audience-uuid> --json
listex audiences city tampa-fl                # resolve a CITY's audience (slug or UUID)
listex audiences create --data '{"audience":{"name":"Tampa Weekly"}}'
listex audiences update <id> --data '{"default_subject_line":"This Week"}'
```

**The `city` subcommand and the `--city` flag are different things.** `listex audiences city <city-id-or-slug>` resolves the audience belonging to that city — this is what you want when preparing a send. `--city <uuid>` is only a filter on the list view and takes a UUID.

Envelope `{"audience": {…}}`; bare payloads are auto-wrapped. There is no delete.

---

## email-templates

Per-city MJML templates.

```bash
listex email-templates --city tampa-fl                    # list city templates
listex email-templates <template-uuid> --json             # flat detail, no --city needed
listex email-templates --city tampa-fl <id>               # city-scoped detail
listex email-templates --city <uuid> create --data '{"name":"Weekly","mjml_code":"<mjml>…"}'
listex email-templates --city tampa-fl <id> update --data '{"subject_template":"This Week"}'
listex email-templates --city tampa-fl <id> set-default
listex email-templates --city tampa-fl <id> delete
```

- `--city` is **required** for list, create, update, delete, and set-default. Only a bare `<id>` detail lookup works without it.
- `set-default` makes the template the city's default broadcast template — this changes what every future broadcast for that city renders with. Confirm before running it.
- Envelope `{"email_template": {…}}`; bare payloads are auto-wrapped.
- MJML is large. Pass it via `--data @template.json` or stdin, not inline, and read it back with `--json` (detail output truncates it).

---

## broadcasts

```bash
listex broadcasts --status scheduled
listex broadcasts --audience <uuid>
listex broadcasts --city <uuid>                        # filter by the audience's city UUID
listex broadcasts <id>                                 # detail (large bodies summarized)
listex broadcasts <id> --json                          # full MJML/HTML/text content
listex broadcasts create --data '{"broadcast":{"name":"Weekly","audience_id":"<uuid>"}}'
listex broadcasts update <id> --data '{"subject":"Updated"}'
listex broadcasts status <id>                          # poll aggregate delivery status
listex broadcasts deliveries <id> --status bounced --page 2
```

Dangerous verbs — **user confirmation required**:

```bash
listex broadcasts test <id> --emails ops@example.com,editor@example.com   # REAL email
listex broadcasts send <id> --confirm                                     # entire audience
listex broadcasts delete <id> --confirm                                   # drafts only
```

- `test` delivers real mail, up to the API's recipient limit. Use internal addresses only.
- `send` queues audience delivery and treats HTTP **202 Accepted** as success — a 202 means "queued", not "delivered". Follow with `broadcasts status <id>`.
- `send` and `delete` require `--confirm`; without it they print a warning and exit 1. That warning is a stop sign — report it to the user rather than re-running with the flag.
- Envelope `{"broadcast": {…}}`; bare payloads are auto-wrapped.

**After a send**, monitor rather than assuming success:

```bash
listex broadcasts status <id> --json                    # aggregate counts
listex broadcasts deliveries <id> --status bounced      # per-recipient logs
listex broadcasts deliveries <id> --status failed
```

`--status` filters broadcasts on the list view and delivery logs on the `deliveries` view.
