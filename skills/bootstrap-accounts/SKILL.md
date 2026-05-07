---
name: bootstrap-accounts
description: >
  Bootstrap multi-tenant account-scoped dashboard with sidebar navigation, account switcher,
  theme toggle, and breadcrumbs in a Phoenix 1.8 app. Builds on top of phx.gen.auth to add
  accounts, memberships, and a dashboard shell. Use when the user says "bootstrap accounts",
  "add accounts", "multi-tenant setup", "account switcher", "account-scoped dashboard",
  or wants to add account/organization switching to a Phoenix app with existing auth and DaisyUI.
---

# Bootstrap Accounts

Add multi-tenant account support with a dashboard shell to a Phoenix 1.8 app that already has `phx.gen.auth` and DaisyUI installed.

## Prerequisites

Verify before starting:
1. `mix phx.new` completed
2. `mix phx.gen.auth Accounts User users` completed
3. DaisyUI installed (vendor JS plugin approach)

## App Name Detection

Detect the app module name from `mix.exs` (e.g., `MyApp`) and the OTP app name (e.g., `my_app`). Replace all occurrences of `MyApp`/`my_app`/`MyAppWeb`/`my_app_web` in reference templates with the actual names.

## Implementation Order

Execute in this exact order. Read the referenced file for each step's code templates.

### Phase 1: Data Layer
Read [references/database.md](references/database.md)

1. Create migration for `accounts` table (name, slug, status, timestamps)
2. Create migration for `account_users` join table (role, user_id, account_id, unique index)
3. Create `Account` schema with slug auto-generation from name
4. Create `AccountUser` schema with role enum

### Phase 2: Context Layer
Read [references/contexts.md](references/contexts.md)

5. Add query functions to `Accounts` context: `list_user_accounts/1`, `get_account/1`, `get_account_user/2`
6. Create `AccountContext` module (facade for account-scoped access)

### Phase 3: Auth Integration
Read [references/auth.md](references/auth.md)

7. Modify `renew_session/2` in `UserAuth` to preserve `last_account_id`
8. Add `:load_account_context` on_mount hook to `UserAuth`
9. Create `LoadAccount` plug
10. Create `DashboardRedirectController`

### Phase 4: UI Shell
Read [references/css-themes.md](references/css-themes.md)

11. Replace `assets/css/app.css` with themed version (DaisyUI light/dark themes, sidebar styles, responsive table)
12. Update `root.html.heex` with theme initialization script

Read [references/layouts.md](references/layouts.md)

13. Update `layouts.ex` with sidebar components, theme toggle, mobile sidebar JS
14. Create `dashboard.html.heex` layout template

Read [references/components.md](references/components.md)

15. Create `AccountSwitcher` LiveComponent
16. Add `breadcrumbs/1` component to `core_components.ex`

### Phase 5: Routes & Pages
Read [references/router-seeds.md](references/router-seeds.md)

17. Add router configuration (`:load_account` pipeline, account-scoped live_session, dashboard redirect)
18. Create `DashboardLive`
19. Create seed data (test user + 2 accounts + memberships)
20. Run migrations and verify with `mix test`

## Key Patterns

Every dashboard LiveView must assign in `mount/3`:
- `:active_nav` — atom matching sidebar item
- `:breadcrumbs` — list of `%{label: "...", to: path}` maps (last item has no `:to`)
- `:page_title` — browser tab title

Breadcrumb structure:
```elixir
[
  %{label: "Parent", to: ~p"/dashboard/accounts/#{account.id}/parent"},
  %{label: "Current Page"}  # Last item — no :to key
]
```

Page markup pattern:
```heex
<div class="space-y-6">
  <div class="flex items-end justify-between">
    <div>
      <h1 class="text-xl font-bold tracking-tight text-base-content">Title</h1>
      <p class="mt-0.5 text-sm text-base-content/50">Subtitle.</p>
    </div>
  </div>
  <div class="rounded-xl border border-base-300/60 bg-base-100">
    <div class="flex items-center justify-between border-b border-base-300/40 px-5 py-3.5">
      <h2 class="text-sm font-semibold text-base-content">Section</h2>
    </div>
    <div class="p-5"><!-- content --></div>
  </div>
</div>
```

Typography scale:
- Page title: `text-xl font-bold tracking-tight text-base-content`
- Subtitle: `text-sm text-base-content/50`
- Card title: `text-sm font-semibold text-base-content`
- Label: `text-xs font-medium text-base-content/50 uppercase tracking-wide`
- Meta: `text-xs text-base-content/40`
