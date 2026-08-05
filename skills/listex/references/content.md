# listex — content commands

Covers `cities`, `jobs`, `homes`, `news`, `events`, `tips`, `zip-codes`.

Run `listex help <command>` for the full flag list. This file covers the workflows and the parts that bite.

---

## Dedupe before create

`jobs`, `news`, and `events` each expose a `match` subcommand that finds near-duplicates. **Run it before every create.** Imported feeds and scraped sources produce paraphrased duplicates constantly, and the API will happily accept them.

```bash
# 1. Look for an existing record
listex news match --city deltona-fl \
  --title "New riverside park opens downtown" \
  --url https://example.com/riverside-park \
  --json

# 2. Only create if nothing matched
listex news create --data @article.json
```

**Reading the results.** Human output is a table of `SCORE`, `MATCH_TYPE`, `TITLE`, `ID`. Use `--json` to branch on it.

- **Hard match** — a normalized URL, or (for events/jobs) `--external-id` combined with `--source`. This is an identity match: do not create, update the existing record instead.
- **Soft match** — title similarity, company/location similarity, and for events a ±24h window around `--start-datetime`.
- **`semantic_similarity`** — appears in soft scores and catches paraphrased near-duplicates that share no keywords. A high semantic score with a different title is still probably the same story. Surface it to the user rather than silently creating.

**`--mode`** on `match` is `candidates` (default, ranked list) or `exact`. Note `--mode` means something different on *list* operations, where it selects `keyword` vs `fuzzy` search.

**`--data` and flags combine**: `--data` is parsed first, then individual flags override it. A resolved `--city` always sets `city_id`, regardless of what's in `--data`.

`--limit <n>` caps results (default 10, max 50).

Per-resource match inputs:

| Resource | Hard match | Soft match |
|----------|-----------|------------|
| `jobs` | `--apply-url` / `--url`, or `--external-id` + city | `--title`, `--company`, `--description` |
| `news` | `--url` | `--title`, `--description` |
| `events` | `--url`, or `--external-id` + `--source` | `--title`, `--description`, `--start-datetime`, `--location-name` |

`--city` is **required** for `match` on all three.

---

## cities

```bash
listex cities                          # table: name, slug, state, enabled
listex cities deltona-fl               # detail, includes feature flag on/off
listex cities --enabled true
listex cities create --data '{"city":{"name":"Deltona","state_id":"<uuid>"}}'
listex cities update deltona-fl --data '{"city":{"timezone":"America/New_York"}}'
listex cities enable deltona-fl
listex cities disable deltona-fl
```

**Feature flags** are the subtle part. Valid keys: `events_enabled`, `news`, `jobs`, `discussions`, `newsletter`, `weather`, `link_pages`, `neighborhoods`.

- Set on create/update via `feature_flags`: `{"feature": {"enabled": true}}`.
- `update` **merges** into the existing map — omitted keys keep their current value.
- Omitted flags on create fall back to server defaults: `news` and `newsletter` default **on**; `jobs`, `events_enabled`, and `neighborhoods` default **off**.
- To toggle a single flag safely, use the dedicated verbs rather than hand-writing the map:
  ```bash
  listex cities enable-feature deltona-fl jobs
  listex cities disable-feature deltona-fl weather
  ```
- Use `listex cities <slug> --json` to read back the raw `feature_flags`.

---

## jobs

```bash
listex jobs                                   # id, title, company, city, status, type
listex jobs --status active                   # active | expired | filled | draft
listex jobs --city austin-tx
listex jobs --search elixir --mode keyword    # keyword | fuzzy
listex jobs <uuid>                            # by UUID
listex jobs austin-tx/software-engineer       # by city-slug/job-slug
listex jobs create --data '{"job":{"title":"Engineer"}}'
listex jobs update <id> --data '{"job":{"title":"Senior Engineer"}}'
listex jobs enrich <id>                       # POST /jobs/{id}/enrich
listex jobs delete <id>                       # permanent, no --confirm required
```

- A slash-separated argument routes to `/jobs/by-slug/{city}/{job}`; a bare UUID routes to `/jobs/{id}`.
- `enrich` triggers async enrichment — it does not return enriched data. Re-fetch the job afterward.

---

## homes

**The one resource with no envelope.** Create/update/upsert bodies are flat JSON.

```bash
listex homes
listex homes --city deltona-fl --listing-status for_sale --featured
listex homes <uuid>
listex homes deltona-fl/123-main-st
listex homes create --data '{"city_id":"<uuid>","zpid":"1","external_url":"https://zillow.com/x","listing_status":"for_sale","street":"1 Main"}'
listex homes upsert --data '{…same shape…}'   # idempotent by zpid
listex homes status <uuid> published           # pending | published | archived
listex homes feature <uuid>
listex homes unfeature <uuid>
listex homes delete <uuid>
```

- **Two independent status axes.** `--listing-status` is the market state (`for_sale`, `for_rent`, `sold`, `off_market`). `--status` is the editorial state (`pending`, `published`, `archived`). Don't conflate them.
- `upsert` keys on `zpid` — prefer it over `create` when ingesting from a feed.
- `status` uses `PATCH /homes/:id/status`; `feature`/`unfeature` are dedicated POSTs. None of these are reachable via `update`.
- `--featured` (alias `--is-featured`) maps to the `is_featured=true` query param.
- Filters: `--home-type`, `--beds-min`, `--price-min`, `--price-max`, `--search` (street / formatted address).

---

## news

```bash
listex news
listex news --status published                # pending | published | archived | draft
listex news --search park --mode fuzzy
listex news --start-date 2026-01-01T00:00:00Z --end-date 2026-02-01T00:00:00Z
listex news --source <import-source> --is-featured true
listex news <uuid>
listex news deltona-fl/new-park-opens
listex news create --data '{"news":{"title":"New park opens"}}'
listex news publish <id>
listex news archive <id>
listex news delete <id>                       # permanent
```

`publish` and `archive` hit explicit lifecycle endpoints. Date filters take ISO-8601 timestamps and filter on published date.

---

## events

```bash
listex events
listex events --status published              # pending | published | archived | cancelled | draft
listex events --search festival --mode keyword
listex events --start-date 2026-06-01T00:00:00Z --end-date 2026-07-01T00:00:00Z
listex events <uuid>
listex events deltona-fl/spring-festival
listex events create --data '{"event":{"title":"Spring Fest","city_id":"<uuid>"}}'
listex events publish <id>
listex events archive <id>
listex events delete <id>                     # permanent
```

`--start-date` filters events *starting* on/after; `--end-date` filters events *ending* on/before. `--source` filters by import source and also participates in hard matching alongside `--external-id`.

---

## tips

User-submitted leads — a triage queue, not published content. There is no delete.

```bash
listex tips
listex tips --status new --type event
listex tips <uuid>
listex tips create --data '{"tip":{"city_id":"<uuid>","title":"Lead title","description":"…","type":"news"}}'
listex tips update <id> --data '{"tip":{"status":"closed"}}'
```

- Status: `new`, `in_progress`, `closed`.
- Type: `news`, `event`, `gossip`, `recommendation`, `warning`, `other`.
- Typical flow: list `--status new` → investigate → create the real news/event record (running `match` first) → `update` the tip to `closed`.

---

## zip-codes

Read-only. ZIP codes with demographic data.

```bash
listex zip-codes 78701                    # global detail
listex zip-codes --city austin-tx         # all ZIPs for a city
listex zip-codes --city austin-tx 78701   # ZIP scoped to that city
listex zip-codes 78701 --json
```

A bare 5-digit code hits `/zip-codes/{code}` with no city context. With `--city` and a code, the lookup is scoped and returns 404 if the ZIP isn't associated with that city — that 404 is meaningful data, not necessarily an error to retry.
