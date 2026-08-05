# searchapi

Agent guide for the **searchapi** Rust CLI — SearchAPI.io (Google Jobs, Events, News Light, Maps, Maps Reviews, Zillow) and free Locations geo-targeting.

## Install skill

Install this skill globally:

```bash
npx skills add agoodway/skills --skill searchapi -g
```

Install into the current project:

```bash
npx skills add agoodway/skills --skill searchapi
```

## Install CLI

The skill expects the `searchapi` binary on `PATH` (typically `~/.local/bin/searchapi`).

From a checkout of the [searchapi](https://github.com/agoodway/searchapi) repo:

```bash
cd cli-rust && just install
```

Confirm:

```bash
searchapi --version
searchapi configure show
```

## Configure

```bash
searchapi configure set --env prod \
  --base-url https://www.searchapi.io/api/v1 \
  --api-key <key>
searchapi configure use prod
```

Config is stored at `~/.searchapi.json`. Never print full API keys.

## Usage

```
/searchapi help
/searchapi locations --q austin
/searchapi jobs --q nurse --location "Austin,Texas,United States"
/searchapi maps --q coffee --ll "@28.9005,-81.2637,14z"
```

Natural language also works: “search Google jobs for nurses in Austin”, “find Zillow listings under 500k”, “maps reviews for this place_id”.

## Commands

| Command | Purpose |
|---------|---------|
| `configure` | Multi-env API key / base URL |
| `locations` | Free canonical location names for Google engines |
| `jobs` | Google Jobs (`google_jobs`) |
| `events` | Google Events (`google_events`) |
| `news` | Google News Light (`google_news_light`) |
| `maps` | Google Maps local results (`google_maps`) |
| `maps-reviews` | Google Maps reviews (`google_maps_reviews`) |
| `zillow` | Zillow property search |
| `fetch-images` | Download image URLs (or extract from CLI JSON) |

## Quick reference

See [references/commands.md](references/commands.md) for a compact flag map.
