# Tracker: local markdown

Tickets live inside the change, so they move with it on `openspec archive`:

```text
openspec/changes/<change>/
├── tickets.md            # the index from step 8
└── tickets/
    ├── 00-<change>.md    # parent
    ├── 01-<slug>.md
    └── 02-<slug>.md
```

- Number slices from `01` in dependency order, blockers first, one ticket per file.
- **Labels**: the `Status:` line carries the label; nothing needs creating.
- **Parent**: `00-<change>.md` uses the parent template under a `# 00: <change title>` heading.
- **Cross-change blockers**: reference `<other-change>#NN`.
- **Reference format** for `tickets.md`: the relative path, `tickets/NN-<slug>.md`.

Slice file template:

```markdown
# NN: <Ticket title>

**Parent:** 00-<change>

**What to build:** the end-to-end behaviour this ticket makes work, from the user's perspective.

**Blocked by:** NN, <other-change>#NN, or "None (can start immediately)".

**Status:** ready-for-agent

**Covers:** <Requirement>: <Scenario>, …

- [ ] WHEN … THEN …
- [ ] …
```
