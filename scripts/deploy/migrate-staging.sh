#!/usr/bin/env sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH= cd -- "$script_dir/../.." && pwd)
env_file=${1:-"$root/.env.staging"}
[ -f "$env_file" ] || { echo "Staging env file not found: $env_file" >&2; exit 1; }
exec docker compose --env-file "$env_file" -f "$root/docker-compose.staging.yml" run --rm migrate
