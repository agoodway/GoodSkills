---
name: bootstrap-user-management
description: >
  Bootstrap account user management UI and backend in a Phoenix 1.8 app.
  Adds LiveView for listing, inviting, and removing account members with
  role-based access control. Builds on top of bootstrap-accounts.
  Use when the user says "bootstrap user management", "add user management",
  "account users", "invite users", "member management", "manage account members",
  or wants to add user invitation and role management to an account-scoped Phoenix app.
---

# Bootstrap User Management

Add account member management to a Phoenix 1.8 app that already has multi-tenant accounts set up via `/bootstrap-accounts`. Provides a LiveView for listing members, inviting users by email, role assignment, and member removal with safety guards.

## Prerequisites

Verify before starting:
1. `/bootstrap-accounts` has been run (accounts table, account_users table, Account schema, AccountUser schema, Accounts context, AccountContext module, LoadAccount plug, account-scoped router all exist)
2. `phx.gen.auth` completed (User schema, UserAuth module exist)
3. DaisyUI installed

## App Name Detection

Detect the app module name from `mix.exs` (e.g., `MyApp`) and the OTP app name (e.g., `my_app`). Replace all occurrences of `MyApp`/`my_app`/`MyAppWeb`/`my_app_web` in reference templates with the actual names.

## Implementation Order

Execute in this exact order. Read the referenced file for each step's code templates.

### Phase 1: Context Functions
Read [references/context.md](references/context.md)

1. Add member management functions to the `Accounts` context: `list_account_members/1`, `get_account_member/2`, `invite_user_to_account/3`, `delete_account_member/1`, `count_account_owners/1`, `authorize_role_assignment/2`, `parse_member_role/1`

### Phase 2: Display Helpers
Read [references/helpers.md](references/helpers.md)

2. Create `MemberDisplayHelpers` module for shared role and date formatting

### Phase 3: LiveView & Form Component
Read [references/liveview.md](references/liveview.md)

3. Create `AccountUsersLive` LiveView with table display and delete action
4. Create `AccountUserFormComponent` for the invite modal

### Phase 4: Routes
Read [references/routes.md](references/routes.md)

5. Add routes for the user management pages inside the existing account-scoped `live_session`
6. Add email notification function for invited users

### Phase 5: Verify

7. Run `mix compile --warnings-as-errors` and fix any issues
8. Verify the routes exist: `mix phx.routes | grep users`

## Key Patterns

**Role hierarchy:**
- `:owner` — full access, can assign any role including owner
- `:admin` — can invite/remove users, cannot assign owner role
- `:member` — basic access, no management permissions

**Safety guards:**
- Cannot remove yourself
- Cannot remove the last owner
- Only admins/owners see the Add User button and Remove links
- Only owners can assign the owner role
- Duplicate member detection with friendly error message

**LiveView assigns in mount:**
- `:active_nav` — set to `:account_users`
- `:current_account_user` — the current user's membership in this account
- `:breadcrumbs` — navigation breadcrumbs
- `:page_title` — browser tab title
