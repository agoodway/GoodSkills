# searchapi command reference

Base: `https://www.searchapi.io/api/v1`  
Config: `~/.searchapi.json`  
Binary: `searchapi` (install: `cd cli-rust && just install`)

## configure

| Action | Command |
|--------|---------|
| Set env | `searchapi configure set --env <name> --base-url <url> --api-key <key>` |
| Show | `searchapi configure show` |
| Default | `searchapi configure use <name>` |

## locations — `GET /locations` (free)

| Flag | API |
|------|-----|
| `--q` / positional | `q` (required) |
| `--limit` | `limit` (max 100) |
| `--zero-retention` | `zero_retention=true` |

Table: NAME, CANONICAL, TYPE, COUNTRY, REACH, LAT, LON  
Use **CANONICAL** as `--location` on Google engines.

## Shared Google flags (jobs, events, news)

| Flag | API |
|------|-----|
| `--q` / positional | `q` |
| `--location` | `location` |
| `--uule` | `uule` |
| `--hl` | `hl` |
| `--gl` | `gl` |

Engines (set by command, not user):

| Command | engine |
|---------|--------|
| jobs | `google_jobs` |
| events | `google_events` |
| news | `google_news_light` |
| maps | `google_maps` |
| maps-reviews | `google_maps_reviews` |
| zillow | `zillow` |

## jobs

Extra: `--next-page-token` → `next_page_token`  
Client filter (not sent to API): `--location-contains <text>` — keep jobs whose `location` contains text (case-insensitive)  
**Single location only:** `--location` / `--uule` accept one value per request (API + CLI). Multi-city = one call per location.  
Table: POS, TITLE, COMPANY, LOCATION, VIA, SCHEDULE, SALARY  
Footer: `next_page_token` when present

## events

Extra: `--chips`, `--page`  
Client filter: `--location-contains <text>` — match `location`, `venue.name`, or `title`  
Table: POS, TITLE, DATE, LOCATION, VENUE, LINK

## news

Extra: `--page`, `--time-period`, `--sort-by`, `--nfpr`, `--filter`  
Client filter: `--location-contains <text>` — match `title`, `source`, `snippet`, or `link` (no dedicated location field)  
`time_period`: last_hour, last_day, last_week, last_month, last_year  
`sort_by`: most_recent  
Table: POS, TITLE, SOURCE, DATE, LINK  
JSON array field: `organic_results`

## maps

Engine: `google_maps` (`GET /search`)

| Flag | API |
|------|-----|
| `--q` / positional | `q` (required) |
| `--ll` | `ll` — `@lat,lon,zoomz` or `@lat,lon,metersm` |
| `--hl` | `hl` |
| `--gl` | `gl` |
| `--page` | `page` |
| `--location-contains` | client filter on title/address/city/type/description |

Table: POS, TITLE, TYPE, RATING, REVIEWS, ADDRESS, PHONE, PLACE_ID  
JSON array field: `local_results`  
Cross-link: use PLACE_ID with `maps-reviews --place-id`

## maps-reviews

Engine: `google_maps_reviews` (`GET /search`)

| Flag | API |
|------|-----|
| `--place-id` | `place_id` (require place_id and/or data_id) |
| `--data-id` | `data_id` |
| `--hl` | `hl` |
| `--gl` | `gl` |
| `--topic-id` | `topic_id` (KGMID) |
| `--sort-by` | `sort_by` — most_relevant, newest, highest_rating, lowest_rating |
| `--num` | `num` (1–20, default 10) |
| `--next-page-token` | `next_page_token` |

Table: RATING, USER, GUIDE, DATE, LIKES, SOURCE, TEXT  
Footer: `next_page_token` when present  
JSON array field: `reviews`

## fetch-images

Local HTTP downloads (no SearchAPI engine).

| Flag | Effect |
|------|--------|
| positional / `--url` | Image URL(s) |
| `--from-json <file\|->` | Extract URLs from JSON (`-` = stdin) |
| `--keys a,b` | Only those object keys (else auto image-URL detect) |
| `--out <dir>` | Output dir (default `./searchapi-images`) |
| `--prefix` | Filename prefix |
| `--limit` | Max downloads |
| `--timeout` | Seconds (default 30) |
| `--dry-run` | List only |
| `--overwrite` | Replace existing files |

Table: STATUS, BYTES, FILE, URL

## zillow

| Flag | API |
|------|-----|
| `--page` | `page` (1–24) |
| `--sort-by` | `sort_by` |
| `--listing-status` | `listing_status` (for_sale, for_rent, sold) |
| `--home-type` | `home_type` |
| `--price-min` / `--price-max` | `price_min` / `price_max` |
| `--rent-min` / `--rent-max` | `rent_min` / `rent_max` |
| `--beds-min` / `--baths-min` | `beds_min` / `baths_min` |
| `--sqft-min` / `--sqft-max` | `sqft_min` / `sqft_max` |
| `--lot-size-min` / `--lot-size-max` | `lot_size_min` / `lot_size_max` |
| `--year-built-min` / `--year-built-max` | `year_built_min` / `year_built_max` |
| `--days-on-zillow` | `days_on_zillow` |
| `--parking-spots` | `parking_spots` |
| `--keywords` | `keywords` |
| `--has-pool` etc. | boolean `true` when flag present |
| `--is-waterfront` etc. | boolean |
| `--zero-retention` | `zero_retention` |

Table: POS, ADDRESS, PRICE, BEDS, BATHS, SQFT, TYPE, STATUS  
JSON array field: `properties`

## Specs (repo)

- `specs/google_jobs_openapi_spec.yaml`
- `specs/google_events_openapi_spec.yaml`
- `specs/google_news_light_openapi_spec.yaml`
- `specs/google_maps_openapi_spec.yaml`
- `specs/google_maps_reviews_openapi_spec.yaml`
- `specs/zillow_openapi_spec.yaml`
- `specs/locations_openapi_spec.yaml`
