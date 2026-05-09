# Shared Scripts and Configuration Reference

Database scripts, `.workie.yaml` template, and gitignore entries used by all strategies.

## Table of Contents

- [Database Setup Script](#database-setup-script)
- [Database Cleanup Script](#database-cleanup-script)
- [Workie Configuration](#workie-configuration)
- [How It Works](#how-it-works)
- [Placeholders to Replace](#placeholders-to-replace)

---

## Database Setup Script

Create `scripts/setup_branch_db.sh`:

```bash
#!/bin/bash

if [ ! -f .branch ]; then
    echo "Error: .branch file not found"
    exit 1
fi

BRANCH_ID=$(cat .branch)
echo "Setting up databases for branch: $BRANCH_ID"

# Database names - REPLACE APP_NAME
DEV_DB="APP_NAME_${BRANCH_ID}_dev"
TEST_DB="APP_NAME_${BRANCH_ID}_test"

# PostgreSQL connection parameters
PGUSER="postgres"
PGPASSWORD="postgres"
PGHOST="localhost"
export PGPASSWORD

echo "Creating development database: $DEV_DB"
createdb -U $PGUSER -h $PGHOST $DEV_DB 2>/dev/null || echo "Database $DEV_DB already exists"

echo "Creating test database: $TEST_DB"
createdb -U $PGUSER -h $PGHOST $TEST_DB 2>/dev/null || echo "Database $TEST_DB already exists"

echo "Running migrations for $DEV_DB"
MIX_ENV=dev DB_NAME=$DEV_DB mix ecto.migrate

echo "Running migrations for $TEST_DB"
MIX_ENV=test DB_NAME=$TEST_DB mix ecto.migrate

echo "Running seeds for $DEV_DB"
MIX_ENV=dev DB_NAME=$DEV_DB mix run priv/repo/seeds.exs

echo "Database setup complete for branch: $BRANCH_ID"
```

## Database Cleanup Script

Create `scripts/cleanup_branch_db.sh`:

```bash
#!/bin/bash

if [ ! -f .branch ]; then
    echo "Warning: .branch file not found, skipping database cleanup"
    exit 0
fi

BRANCH_ID=$(cat .branch)
echo "Cleaning up databases for branch: $BRANCH_ID"

# Database names - REPLACE APP_NAME
DEV_DB="APP_NAME_${BRANCH_ID}_dev"
TEST_DB="APP_NAME_${BRANCH_ID}_test"

PGUSER="postgres"
PGPASSWORD="postgres"
PGHOST="localhost"
export PGPASSWORD

echo "Dropping development database: $DEV_DB"
dropdb -U $PGUSER -h $PGHOST $DEV_DB 2>/dev/null || echo "Database $DEV_DB does not exist"

echo "Dropping test database: $TEST_DB"
dropdb -U $PGUSER -h $PGHOST $TEST_DB 2>/dev/null || echo "Database $TEST_DB does not exist"

echo "Database cleanup complete for branch: $BRANCH_ID"
```

Make both executable:

```bash
chmod +x scripts/setup_branch_db.sh scripts/cleanup_branch_db.sh
```

## Workie Configuration

Create `.workie.yaml` in the project root. Merge the strategy-specific `files_to_copy` from `bootstrap-strategies.md` with the shared hooks:

```yaml
# Workie Configuration
# Each worktree gets its own directory + isolated database

files_to_copy:
  # USE THE LIST FROM YOUR DETECTED STRATEGY (see bootstrap-strategies.md)

hooks:
  post_create:
    - "echo 'Setting up new worktree...'"
    - "branch_name=$(git branch --show-current); branch_name=${branch_name#*/}; echo \"${branch_name//[^a-zA-Z0-9]/_}\" | cut -c1-24 > .branch"
    - "mix deps.get"
    - "mix compile"
    - "./scripts/setup_branch_db.sh"
  pre_remove:
    - "./scripts/cleanup_branch_db.sh"

default_provider: github

providers:
  github:
    enabled: true
    settings:
      token_env: WORKIE_GITHUB_TOKEN
      owner: GITHUB_OWNER
      repo: GITHUB_REPO
```

## How It Works

1. **`workie begin my-feature`** creates a new git worktree in a sibling directory
2. Workie copies env files into the new worktree (strategy-dependent)
3. The post-create hook strips the conventional prefix (e.g., `feat/`, `fix/`), then writes a `.branch` file (sanitized branch name, alphanumeric + underscore, max 24 chars)
4. `mix deps.get` and `mix compile` bootstrap the worktree
5. `setup_branch_db.sh` creates isolated `APP_NAME_myfeature_dev` and `APP_NAME_myfeature_test` databases, runs migrations, and seeds dev
6. Config reads `.branch` to select the correct database name
7. The main worktree (no `.branch` file) continues using the default database names
8. **`workie finish my-feature`** runs `cleanup_branch_db.sh` to drop both databases

## Placeholders to Replace

| Placeholder | Replace With | Example |
|---|---|---|
| `APP_NAME` | Your app's database prefix (snake_case) | `my_app` |
| `app_name` | Your OTP app name (atom) | `my_app` |
| `AppName` | Your app module name | `MyApp` |
| `GITHUB_OWNER` | GitHub org or username | `myorg` |
| `GITHUB_REPO` | GitHub repository name | `my_app` |
