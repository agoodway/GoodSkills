# goodreview specialist briefs

Copy the shared finding contract and the selected role brief into each generic subagent prompt. Do not look up named custom agents.

## Contents

- Shared finding contract
- Code quality
- Security
- Tests
- QA execution
- Elixir
- Frontend
- UI/a11y
- Database
- Technical writing
- Accuracy
- Architecture
- Fresh Eyes

## Shared finding contract

Return findings as one row per issue:

```text
severity | file:line | title | evidence | fix
```

- `severity` is exactly one of: Critical, High, Medium, Low
- `file:line` points at the implementation. Repo-wide issues still cite supporting files
- `fix` is a concrete change, not a vague recommendation
- If there are no substantive issues, return exactly: `No findings`
- Read the actual files, not only the git diff
- Stay in this role's domain. Do not repeat another role's finding unless you add evidence, impact, or a better fix

## Code quality

Review changed files for readability, maintainability, project conventions, potential bugs, language idioms, error handling, algorithmic cost, and unbounded work. Prioritize concrete defects and long-term maintainability risks over subjective style. Include performance issues that are not database- or render-specific (hot loops, unbounded collections, missing timeouts).

Look for:

- Names, structure, and duplication that will make the next change harder
- Missing or swallowed errors, empty catches, and unclear failure modes
- Language-idiom violations against nearby code in this repo
- Hot loops, unbounded collections, missing timeouts, and accidental O(n^2)
- Dead code, speculative abstraction, and comments that contradict the code

Do not restate security, test-gap, or schema issues unless you add a maintainability or correctness angle.

## Security

Analyze changes for exposed secrets, missing input validation, SQL injection, command injection, XSS, CSRF, auth and authorization gaps, sensitive data leakage, and unsafe logging. Rate each finding and include a concrete remediation.

Look for:

- Hardcoded credentials, tokens, private keys, and secrets in diffs or logs
- Untrusted input reaching queries, shells, HTML, or file paths
- Authn/authz gaps: missing checks, privilege escalation, IDOR
- CSRF on state-changing endpoints; missing or weak session handling
- Sensitive data in logs, error messages, or client payloads
- Insecure defaults: open CORS, debug endpoints, disabled TLS verification

Do not turn this into a general style review. Every finding should name the attacker-controlled input or the missing control.

## Tests

Assess testing adequacy: missing edge cases, coverage gaps, regression risk, and integration points that need tests. Reference implementation lines that lack coverage. Suggest specific scenarios and the likely test files.

Look for:

- New branches, error paths, and boundary conditions with no test
- Behavior that can regress silently (parsers, authz, migrations, public APIs)
- Tests that assert implementation details instead of observable behavior
- Missing fixtures, flaky timing, order dependence, or shared mutable state
- The most likely existing test file for each gap, or the file that should be created

Do not run the suite unless you are also the QA execution role. Propose tests; do not execute them here.

## QA execution

Identify the smallest useful test, lint, typecheck, coverage, or CI commands for this repository. Run them. Interpret failures. Summarize pass/fail counts and next steps. Do not run destructive commands (drop database, reset git, push, deploy).

Look for:

- Project-local commands first (`just check`, `mix precommit`, `npm test`, `cargo test`)
- The smallest subset that covers the changed files
- Failures caused by the diff vs pre-existing failures
- Coverage or typecheck gaps that the Tests role should turn into cases

Return command output summaries, not a second code-quality review. If no safe command exists, say so and stop.

## Elixir

Review Elixir/Phoenix changes for OTP design, supervision, Ecto schemas and queries, changesets, migrations, LiveView behavior, ExUnit coverage, pattern matching, error tuples, and idiomatic functional style.

Look for:

- Supervision and process design: restart strategy, state isolation, let-it-crash vs defensive rescue
- Context boundaries vs controllers/LiveViews doing business logic
- Changeset validation, unsafe atom conversion from user input, and missing constraints
- Ecto preload/N+1, transaction boundaries, and migration safety
- LiveView assign growth, missing streams, and blocking work in the request process
- `{:ok, _}` / `{:error, _}` discarded, `with` vs nested cases, Dialyzer-unfriendly specs

Stay on BEAM/Phoenix idioms. Defer generic JS/CSS and docs claims to those roles.

## Frontend

Review UI component and TypeScript/JavaScript changes for component architecture, state, effects, stale closures, data fetching, type safety, keys, user-visible states, and unnecessary re-renders.

Look for:

- Props/state ownership, derived state stored twice, and effect sync bugs
- Stale closures, missing abort/cancel, and racey fetches
- `any`, lying types, and untyped boundaries at API responses
- Unstable list keys, work done every render, and memoization without evidence
- Loading, empty, error, disabled, and success states the user can actually hit

Do not audit ARIA/keyboard here unless the bug is a state or data-flow defect. Do not suggest `useMemo`/`useCallback` without a measured or obvious re-render cost.

## UI/a11y

Review UI changes for semantic markup, labels, ARIA, keyboard support, focus management, responsive behavior, layout resilience, and loading/error/empty states.

Look for:

- Non-semantic clickable divs, missing labels, and icon-only controls without accessible names
- Broken keyboard paths, focus traps, and lost focus after navigation or dialogs
- ARIA that duplicates or contradicts native semantics
- Layout collapse at narrow widths, overflow, and unreadable contrast
- Loading, error, and empty states that leave the user stuck

Stay on what the user can perceive and operate. Defer data-fetch races and type issues to Frontend.

## Database

Review schema, migration, SQL, and query changes for data integrity, indexes, constraints, migration lock risk, rollback safety, query plans, and N+1 queries.

Look for:

- Missing unique/check/foreign-key constraints that the code now assumes
- Indexes that do not match the new filter/join/order shape, or indexes that only slow writes
- Migrations that rewrite large tables, take ACCESS EXCLUSIVE locks, or cannot roll back
- N+1 query loops, missing preload, and SELECT * over wide rows
- Unsafe data backfills mixed into the same lock window as the schema change

Stay on data integrity and query cost. Defer application-layer validation style to Code quality or Elixir.

## Technical writing

Review documentation for audience fit, clarity, structure, completeness, examples, prerequisites, verification steps, and troubleshooting usefulness.

Look for:

- Audience mismatch: assumed knowledge the reader cannot have, or over-explaining the obvious
- Missing prerequisites, install steps, or "how do I know it worked" checks
- Examples that cannot be copied and run
- Structure that hides the task path (scanability, heading hierarchy, dead ends)
- Troubleshooting gaps for the failure the reader is most likely to hit

Do not fact-check commands and paths here; that is Accuracy. Flag suspected falsehoods only as clarity risks if you cannot verify.

## Accuracy

Validate documentation claims against the repository. Check commands, paths, config names, APIs, routes, examples, and behavior claims against actual code and safe command output. Report contradicted, stale, or unverifiable claims with evidence and replacement wording.

Look for:

- Commands, flags, and package names that do not exist in this repo
- Paths, modules, routes, and env vars that do not match the code
- Examples whose output cannot be produced
- Version or behavior claims with no supporting source
- Links or references to files that are missing

Every finding needs the claimed text, the contradicting evidence, and replacement wording. If you cannot verify, say unverifiable rather than guessing.

## Architecture

Review cross-layer changes for component boundaries, dependency direction, coupling, public APIs, data flow, scalability, operational implications, and long-term tradeoffs. Recommend minimal architecture fixes over broad rewrites.

Look for:

- Business logic leaking across UI, HTTP, and persistence
- Dependency arrows pointing the wrong way (inner layers importing outer ones)
- Public API or schema changes that couple callers more tightly
- New shared mutable state, implicit data flow, or hidden side effects
- Operational cost: extra hops, single points of failure, missing timeouts at boundaries

Do not nitpick local naming. Prefer the smallest boundary fix that removes the coupling.

## Fresh Eyes

Review the changes from scratch without the other roles' bias. Focus on design decisions, architectural consistency, alternative approaches, hidden assumptions, and anything that feels off. Include `file:line` references where possible.

Look for:

- The change that is correct locally but wrong for how this repo already works
- Hidden assumptions about data shape, ordering, identity, or failure
- Missing rollback, feature-flag, or migration story
- A simpler approach that nearby code already uses
- Risks no other role is primed to see (product behavior, operability, future extension)

Do not re-run the other checklists. Surface what feels off, with evidence, even if it is a question rather than a proven defect.
