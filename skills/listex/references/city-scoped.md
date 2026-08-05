# listex — city-scoped commands

Covers `neighborhoods`, `listicles`, `places`, `content-pages`.

These differ from the content commands in one structural way: **every operation needs a city context**. Run `listex help <command>` for the full flag list.

---

## The `--city` requirement

`neighborhoods`, `listicles`, and `places` require `--city <id-or-slug>` on **every** operation, including list and show. Omitting it is an error (exit 1), not an "all cities" query.

Two equivalent forms for showing one record:

```bash
listex places --city deltona-fl joes-diner   # explicit --city + slug or UUID
listex places deltona-fl/joes-diner          # combined shorthand
```

The positional argument accepts either a UUID or a slug *within that city*. Slugs are only unique per-city, which is why the context is mandatory.

Verbs come **after** the identifier, not before:

```bash
listex places --city deltona-fl <uuid> publish     # correct
listex places --city deltona-fl publish <uuid>     # wrong
```

except for `create`, which takes no identifier:

```bash
listex places --city deltona-fl create --data @place.json
```

Common status values across these three: `pending`, `draft`, `published`, `archived`. Delete is permanent and does **not** require `--confirm` — confirm with the user first.

---

## neighborhoods

```bash
listex neighborhoods --city deltona-fl
listex neighborhoods --city deltona-fl --json
listex neighborhoods deltona-fl/riverside
listex neighborhoods --city deltona-fl create --data @neigh.json
echo '{"neighborhood":{"name":"Downtown","summary":"…"}}' | listex neighborhoods --city deltona-fl create
listex neighborhoods --city deltona-fl riverside publish
listex neighborhoods --city deltona-fl riverside archive
listex neighborhoods --city deltona-fl riverside delete
```

Envelope: `{"neighborhood": {…}}`. Cities also carry a `neighborhoods` feature flag that defaults **off** — if a city has no neighborhoods, check `listex cities <slug>` to see whether the feature was ever turned on before assuming data is missing.

---

## listicles

```bash
listex listicles --city deltona-fl
listex listicles --city deltona-fl --status published --category food_and_drink --featured
listex listicles deltona-fl/best-coffee
listex listicles --city deltona-fl create --data @listicle.json
listex listicles --city deltona-fl <uuid> publish
listex listicles --city deltona-fl <uuid> unpublish
listex listicles --city deltona-fl <uuid> delete
```

Envelope: `{"listicle": {…}}` — **required**, bare fields are not auto-wrapped here.

**Items are embedded**, not separate resources. They live in the `items` array on the listicle, each with a `position`:

```bash
listex listicles --city deltona-fl create --data '{
  "listicle": {
    "title": "Best Coffee",
    "intro": "…",
    "category": "food_and_drink",
    "items": [{"position": 0, "title": "Jo'\''s"}, {"position": 1, "title": "Bean Co"}]
  }
}'
```

**Reordering** has its own verb — don't rewrite the whole `items` array to change order:

```bash
listex listicles --city deltona-fl <uuid> reorder-items --ids id-c,id-a,id-b
# or equivalently
listex listicles --city deltona-fl <uuid> reorder-items --data '{"item_ids":["id-c","id-a","id-b"]}'
```

Status here is just `draft` | `published` (narrower than the other city-scoped resources), and `unpublish` is the reverse verb rather than `archive`.

---

## places

```bash
listex places --city deltona-fl
listex places --city deltona-fl --status published
listex places --city deltona-fl --type restaurant
listex places --city deltona-fl --search "diner"     # searches name, description, address
listex places deltona-fl/joes-diner
listex places --city deltona-fl create --data '{"place":{"name":"Joe'\''s Diner"}}'
echo '{"name":"Joe'\''s Diner"}' | listex places --city deltona-fl create
listex places --city deltona-fl <uuid> publish
listex places --city deltona-fl <uuid> archive
listex places --city deltona-fl <uuid> delete
```

Envelope: `{"place": {…}}`, and bare place fields **are** auto-wrapped (as the stdin example shows). `--type` filters by primary type (`restaurant`, `park`, …).

---

## content-pages

The strictest command in the CLI, and the one with a different shape from everything else: scope comes first, then the verb.

```bash
listex content-pages site <verb> [options]
listex content-pages city --city <id-or-slug> <verb> [options]
```

- **`site`** — site-wide pages, where `city_id` is null.
- **`city`** — city-scoped pages, requires `--city`.

Verbs (both scopes): `list`, `show <uuid-or-path>`, `create`, `update <uuid-or-path>`, `publish <uuid-or-path>`, `unpublish <uuid-or-path>`, `delete <uuid-or-path>`.

```bash
listex content-pages site list --status published
listex content-pages site show about/team
listex content-pages city --city deltona-fl list --page 2 --per-page 50
listex content-pages city --city deltona-fl create --data @page.json
listex content-pages city --city deltona-fl publish guides/moving-here
listex content-pages site delete legacy/old-page
```

**Identifiers can be a UUID or a nested path** (`about/team`, `guides/moving-here`).

**Body validation is strict and local** — the CLI rejects a bad body before making a request:

- The envelope must be exactly `{"content_page": {…}}`. Bare attributes are rejected. Extra top-level keys alongside `content_page` are rejected.
- `city create` injects `city_id` when it's missing or null, and **rejects a conflicting UUID** — don't set `city_id` yourself to something other than the `--city` you passed.
- `site create` rejects a non-null `city_id`.

**Scopes required** (relevant when a key returns 403):

| Scope | Grants |
|-------|--------|
| `content_pages:read` | list, show, by-path, and the preflight for every mutation |
| `content_pages:write` | create, update, publish, unpublish |
| `content_pages:delete` | delete |
| `cities:read` | only when `--city` is a slug — UUID selectors skip the lookup |

Both path-aware and UUID mutations preflight through show/by-path, so **every** mutation needs `content_pages:read` in addition to write or delete. A key with write but not read will fail on update.

List options are `--status draft|published`, `--page`, `--per-page`, `--json`.
