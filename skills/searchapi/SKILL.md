---
name: searchapi
description: >
  Use the searchapi CLI to search SearchAPI.io (Google Jobs, Events, News Light,
  Maps, Maps Reviews, Zillow) and free Locations geo-targeting. Triggers: "/searchapi",
  "searchapi", "search jobs", "google jobs api", "search events", "google news",
  "google maps", "maps search", "maps reviews", "google maps reviews", "local business",
  "place_id", "zillow search", "searchapi locations", "canonical location",
  "SearchAPI.io CLI", configure searchapi API key, or when the user wants
  terminal/API searches via the local searchapi binary. Prefer this skill over
  raw curl against searchapi.io.
---

# searchapi

Agent guide for the **searchapi** Rust CLI (SearchAPI.io). Prefer the installed binary over reimplementing HTTP calls.

## Binary resolution

1. Prefer `searchapi` on `PATH` (often `~/.local/bin/searchapi` after `just install`).
2. If missing and the searchapi repo is available: `cd cli-rust && just install` (or `just run -- <args>`).
3. If missing and no repo checkout: tell the user to clone the searchapi project and run `cd cli-rust && just install` (requires Rust toolchain + `just`).
4. Confirm: `searchapi --version` and `searchapi configure show`.

Never print full API keys. `configure show` masks them; do not dump `~/.searchapi.json`.

## Config

Stored at `~/.searchapi.json` (multi-env, listex-style).

```bash
searchapi configure set --env prod \
  --base-url https://www.searchapi.io/api/v1 \
  --api-key <key>
searchapi configure show
searchapi configure use prod
```

- Global override: `--env <name>`
- Default base URL: `https://www.searchapi.io/api/v1`
- Auth: Bearer header (CLI handles this)

If commands fail with “no environment configured”, run `configure set` (ask the user for a key if needed — do not invent keys).

## Global flags

| Flag | Effect |
|------|--------|
| `--json` | Raw JSON on stdout (use when parsing/scripting) |
| `--env <name>` | Pick config environment |
| `--help` / `searchapi help <cmd>` | Command-specific help |

**Human vs agent:**
- Tables for the user to read in the terminal.
- `--json` when you need to parse, summarize, filter, or chain results.

## Commands

### locations (free)

Resolve a place to a **canonical_name** for Google engines.

```bash
searchapi locations --q "austin" --limit 10
searchapi locations "london" --json
```

Use the **CANONICAL** column value as `--location` on jobs/events/news.

### jobs

```bash
searchapi jobs --q "nurse" --location "Austin,Texas,United States"
searchapi jobs "software engineer" --location "Remote" --json
searchapi jobs --q "nurse" --next-page-token <token>
# City-only rows (client-side filter; Google may still return metro results without this)
searchapi jobs --q "jobs in Deltona FL" \
  --location "Deltona,Florida,United States" \
  --location-contains "Deltona"
```

Flags: `--q`, `--location`, `--location-contains`, `--uule`, `--hl`, `--gl`, `--next-page-token`

`--location` localizes the Google search (one location per request — neither the CLI nor the SearchAPI Google Jobs API accepts multiple locations in a single call). `--uule` is also single-value and overrides `--location`. `--location-contains <text>` filters result rows client-side (case-insensitive match on each job’s `location` field); it does not search additional places.

**Multiple locations:** run one request per location (loop/script), e.g.:

```bash
for loc in "Austin,Texas,United States" "Dallas,Texas,United States"; do
  searchapi jobs --q "nurse" --location "$loc" --json
done
```

### events

```bash
searchapi events --q "concerts" --location "New York,New York,United States"
searchapi events "farmers market" --page 2
searchapi events --q "events in Deltona FL" \
  --location "Deltona,Florida,United States" \
  --location-contains "Deltona"
```

Flags: shared Google flags + `--chips`, `--page`, `--location-contains`  
`--location-contains` matches event `location`, venue name, or title.

### news

```bash
searchapi news --q "local elections" --time-period last_week
searchapi news "AI regulation" --sort-by most_recent --json
searchapi news --q "Deltona FL" --location "Deltona,Florida,United States" \
  --location-contains "Deltona"
```

Flags: shared Google flags + `--page`, `--time-period` (`last_hour|last_day|last_week|last_month|last_year`), `--sort-by most_recent`, `--nfpr`, `--filter`, `--location-contains`  
News has no dedicated city field; `--location-contains` matches **title, source, snippet, or link**.

### maps

```bash
searchapi maps --q "coffee" --ll "@28.9005,-81.2637,14z"
searchapi maps "plumber near me" --gl us --page 1
searchapi maps --q "restaurants" --ll "@28.9,-81.26,12z" --location-contains "Deltona" --json
```

Flags: `--q`, `--ll` (`@lat,lon,zoomz` or `@lat,lon,metersm`), `--hl`, `--gl`, `--page`, `--location-contains`  
Engine: `google_maps`. Table includes `place_id` for `maps-reviews`.  
Filter matches title, address, city, type, or description.

### maps-reviews

```bash
# place_id from maps search results
searchapi maps-reviews --place-id "ChIJ..." 
searchapi maps-reviews --place-id "ChIJ..." --sort-by newest --num 20
searchapi maps-reviews --data-id "0x..." --json
searchapi maps-reviews --place-id "ChIJ..." --next-page-token <token>
```

Flags: `--place-id` and/or `--data-id` (at least one required), `--hl`, `--gl`, `--topic-id`,  
`--sort-by` (`most_relevant|newest|highest_rating|lowest_rating`), `--num` (1–20), `--next-page-token`  
Engine: `google_maps_reviews`. Table: RATING, USER, GUIDE, DATE, LIKES, SOURCE, TEXT.  
Footer prints `next_page_token` when present. JSON array field: `reviews`.

### zillow

```bash
searchapi zillow --q "Austin, TX" --listing-status for_sale --price-max 500000
searchapi zillow "78701" --beds-min 3 --has-pool --json
```

Many filters: `--sort-by`, `--listing-status`, `--home-type`, price/rent/beds/baths/sqft/lot/year-built, `--days-on-zillow`, `--keywords`, boolean `--has-*` / `--is-*`. See `searchapi help zillow`.

### fetch-images

Generic image downloader (no SearchAPI request). Accepts URLs or extracts them from any CLI JSON.

```bash
searchapi fetch-images "https://photos.zillowstatic.com/fp/abc-p_e.jpg" --out ./imgs
searchapi zillow --q "Deltona, FL" --json \
  | searchapi fetch-images --from-json - --keys thumbnail --out ./thumbs --limit 10
searchapi maps-reviews --place-id "ChIJ..." --json \
  | searchapi fetch-images --from-json - --keys image --out ./review-imgs
```

Flags: `--url`, `--from-json <file|->`, `--keys`, `--out`, `--prefix`, `--limit`, `--timeout`, `--dry-run`, `--overwrite`, `--json`  
Without `--keys`, walks JSON and keeps strings that look like image URLs.

## Recommended workflows

### 1. Localized Google search

1. `searchapi locations --q "<city>" --limit 5`
2. Pick a `canonical_name` (prefer City / relevant `target_type`)
3. `searchapi jobs|events|news --q "..." --location "<canonical_name>"`

### 2. Answer a research question

1. Run the relevant command with `--json`
2. Summarize titles, links, companies, prices, etc. for the user
3. Offer follow-ups (next page token, tighter location, filters)

### 3. Scripting / pipelines

```bash
searchapi news --q "topic" --json | jq '.organic_results[:5] | .[] | {title, source, link}'
```

Exit non-zero on missing config, missing `--q`, or HTTP/API errors — check `$?` when chaining.

## Agent rules

1. **Use the CLI**, not hand-rolled curl/reqwest, unless the CLI cannot express the request.
2. **Resolve locations** before Google searches when the user names a city/region.
3. **Prefer `--json`** when you will interpret results; use tables when the user is watching live output.
4. **Never commit or echo API keys.** Do not read `~/.searchapi.json` into chat.
5. **Check help** with `searchapi help <command>` if a flag is unclear — keep this skill as the playbook, live help as truth.
6. OpenAPI sources (repo): `specs/*_openapi_spec.yaml` including `locations_openapi_spec.yaml`.
7. If the binary is outdated vs repo changes: `cd cli-rust && just install`.
8. **Maps → reviews:** `maps` for places/`place_id`, then `maps-reviews --place-id <id>` for review text.

## Slash usage

If the user runs `/searchapi ...`, treat everything after `/searchapi` as CLI args:

- `/searchapi locations --q austin` → `searchapi locations --q austin`
- `/searchapi jobs --q nurse --location "Austin,Texas,United States"` → same as CLI

## Quick reference

See [references/commands.md](references/commands.md) for a compact flag map.
