#!/usr/bin/env sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH= cd -- "$script_dir/../.." && pwd)
env_file=${1:-"$root/.env.staging"}
[ -f "$env_file" ] || { echo "Staging env file not found: $env_file" >&2; exit 1; }
docker compose --env-file "$env_file" -f "$root/docker-compose.staging.yml" ps
curl --fail --silent --show-error --max-time 15 http://127.0.0.1/ready >/dev/null
exec sh "$root/scripts/maps/smoke-map.sh" --base-url http://127.0.0.1
