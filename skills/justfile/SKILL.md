---
name: justfile
description: "Generate a justfile for the current project based on detected project type and deployment method."
---

# Generate Justfile

Generate a `justfile` for this project with standard recipes based on the detected project type.

## Instructions

1. **Detect project type** by checking for these files (in order):
   - `mix.exs` → Elixir/Phoenix
   - `package.json` → Node.js
   - `pyproject.toml` or `requirements.txt` → Python
   - `go.mod` → Go
   - `Cargo.toml` → Rust

2. **Detect deployment method** by checking for:
   - `fly.toml` → use `fly deploy`
   - `Dockerfile` with no fly.toml → use `docker build` placeholder
   - `package.json` with deploy script → use that script
   - `deploy.sh` → use `./deploy.sh`
   - Otherwise → placeholder with TODO

3. **Generate justfile** with these recipes:

## Project-Specific Commands

### Elixir/Phoenix
```just
# Start development server
up:
    mix phx.server

# Deploy to production
deploy:
    fly deploy

# Run tests
test:
    mix test

# Run quality checks
check:
    mix check

# Compile the project
build:
    mix compile

# Clean build artifacts
clean:
    mix clean
    rm -rf _build deps
```

### Node.js
```just
# Start development server
up:
    npm run dev

# Deploy to production
deploy:
    npm run deploy

# Run tests
test:
    npm test

# Run linting
check:
    npm run lint

# Build the project
build:
    npm run build

# Clean build artifacts
clean:
    rm -rf node_modules dist build .next
```

### Python
```just
# Start development server
up:
    python -m uvicorn main:app --reload

# Deploy to production
deploy:
    # TODO: Configure deployment

# Run tests
test:
    pytest

# Run linting
check:
    ruff check .

# Build the project
build:
    pip install -e .

# Clean build artifacts
clean:
    rm -rf __pycache__ .pytest_cache .ruff_cache dist build *.egg-info
```

### Go
```just
# Start development server
up:
    go run .

# Deploy to production
deploy:
    # TODO: Configure deployment

# Run tests
test:
    go test ./...

# Run linting
check:
    go vet ./...

# Build the project
build:
    go build -o bin/app .

# Clean build artifacts
clean:
    rm -rf bin
```

### Rust
```just
# Start development server
up:
    cargo run

# Deploy to production
deploy:
    # TODO: Configure deployment

# Run tests
test:
    cargo test

# Run linting
check:
    cargo clippy

# Build the project
build:
    cargo build --release

# Clean build artifacts
clean:
    cargo clean
```

## Additional Guidelines

- If `fly.toml` exists, always use `fly deploy` for the deploy recipe
- For Node.js, check `package.json` scripts and use the actual script names (e.g., `dev`, `start`, `serve`)
- For Phoenix projects, check if `mix check` alias exists in mix.exs; if not, use `mix credo --strict`
- Add a comment at the top of the justfile: `# Project automation recipes`
- If the project type cannot be determined, ask the user what type of project it is

## Output

Write the justfile to the project root. If a justfile already exists, ask before overwriting.
