#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: env-to-fly-secrets.sh -f .env [-a app-name] [-n batch-size] [--execute]

Converts a .env file into one or more flyctl secrets commands.

Options:
  -f, --file FILE       Path to .env file (required)
  -a, --app APP         Fly app name (adds --app APP)
  -n, --batch-size N    Number of secrets per command (default: 10)
      --execute         Execute commands instead of printing them
  -h, --help            Show this help

Example:
  ./env-to-fly-secrets.sh -f .env.prod -a my-app -n 8
EOF
}

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

file=""
app=""
batch_size=10
execute=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -f|--file)
      file="${2:-}"
      shift 2
      ;;
    -a|--app)
      app="${2:-}"
      shift 2
      ;;
    -n|--batch-size)
      batch_size="${2:-}"
      shift 2
      ;;
    --execute)
      execute=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$file" ]]; then
  echo "Error: --file is required" >&2
  usage
  exit 1
fi

if [[ ! -f "$file" ]]; then
  echo "Error: file not found: $file" >&2
  exit 1
fi

if ! [[ "$batch_size" =~ ^[1-9][0-9]*$ ]]; then
  echo "Error: --batch-size must be a positive integer" >&2
  exit 1
fi

declare -a pairs=()
line_no=0

while IFS= read -r raw_line || [[ -n "$raw_line" ]]; do
  line_no=$((line_no + 1))
  line="$(trim "$raw_line")"

  [[ -z "$line" ]] && continue
  [[ "${line:0:1}" == "#" ]] && continue

  if [[ "$line" == export[[:space:]]* ]]; then
    line="$(trim "${line#export}")"
  fi

  if [[ "$line" != *"="* ]]; then
    echo "Warning: skipping invalid line $line_no (no '='): $raw_line" >&2
    continue
  fi

  key="${line%%=*}"
  value="${line#*=}"

  key="$(trim "$key")"
  value="${value#"${value%%[![:space:]]*}"}"

  if [[ -z "$key" ]]; then
    echo "Warning: skipping invalid line $line_no (empty key): $raw_line" >&2
    continue
  fi

  if ! [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
    echo "Warning: skipping invalid key on line $line_no: $key" >&2
    continue
  fi

  pairs+=("$key=$value")
done < "$file"

if [[ "${#pairs[@]}" -eq 0 ]]; then
  echo "No valid secrets found in $file" >&2
  exit 1
fi

for ((i=0; i<${#pairs[@]}; i+=batch_size)); do
  cmd=(fly secrets set)
  if [[ -n "$app" ]]; then
    cmd+=(--app "$app")
  fi

  end=$((i + batch_size))
  if (( end > ${#pairs[@]} )); then
    end=${#pairs[@]}
  fi

  chunk=("${pairs[@]:i:end-i}")

  if (( execute )); then
    "${cmd[@]}" "${chunk[@]}"
  else
    printf '%q ' "${cmd[@]}" "${chunk[@]}"
    printf '\n'
  fi
done
