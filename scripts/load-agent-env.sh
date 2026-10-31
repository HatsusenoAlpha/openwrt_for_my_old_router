#!/usr/bin/env sh
set -eu

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
root="$(CDPATH= cd -- "$script_dir/.." && pwd)"
env_file="${1:-$root/.env.local}"

if [ ! -f "$env_file" ] && [ -f "$root/.env" ]; then
  env_file="$root/.env"
fi
if [ ! -f "$env_file" ]; then
  echo "Environment file not found. Copy .env.example to .env.local first." >&2
  exit 1
fi

while IFS= read -r line || [ -n "$line" ]; do
  case "$line" in
    ''|'#'*) continue ;;
  esac
  name=${line%%=*}
  value=${line#*=}
  case "$name" in
    ''|*[!A-Za-z0-9_]*) continue ;;
  esac
  value=$(printf '%s' "$value" | sed "s/^['\"]//; s/['\"]$//")
  export "$name=$value"
done < "$env_file"

echo "Loaded environment variables from $env_file"
