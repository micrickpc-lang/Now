#!/usr/bin/env sh
set -eu

usage() {
  cat <<'EOF'
Usage: ./scripts/maps/start-map-stack.sh [options]

Start the internal Martin and Nominatim runtime services from the standalone
staging Compose file. A completed Nominatim import is required.

Options:
  --env-file <path>   Staging env file (default: .env.staging)
  --data-root <path>  Persistent root (default: NOW_DATA_ROOT or /opt/now/data)
  --no-wait           Do not wait for service health
  --help              Show this help
EOF
}

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH= cd -- "$script_dir/../.." && pwd)
env_file="$root/.env.staging"
data_root=${NOW_DATA_ROOT:-/opt/now/data}
wait_for_health=true

while [ "$#" -gt 0 ]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --env-file)
      [ "$#" -ge 2 ] || { echo "--env-file requires a path" >&2; exit 2; }
      env_file=$2
      shift
      ;;
    --data-root)
      [ "$#" -ge 2 ] || { echo "--data-root requires a path" >&2; exit 2; }
      data_root=$2
      shift
      ;;
    --no-wait) wait_for_health=false ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

[ -f "$env_file" ] || { echo "Staging env file not found: $env_file" >&2; exit 1; }
command -v docker >/dev/null 2>&1 || { echo "Docker Compose v2 is required" >&2; exit 1; }
export NOW_DATA_ROOT="$data_root"

compose() {
  docker compose --env-file "$env_file" -f "$root/docker-compose.staging.yml" "$@"
}

for required in \
  "$data_root/maps/region.osm.pbf" \
  "$data_root/maps/seychas-v1.mbtiles"; do
  if [ ! -f "$required" ]; then
    echo "Required map runtime artifact is missing: $required" >&2
    echo "Complete the maps-import profile first." >&2
    exit 1
  fi
done
for marker in PG_VERSION import-finished; do
  if ! compose run --rm --no-deps --entrypoint test nominatim \
    -f "/var/lib/postgresql/16/main/$marker"; then
    echo "Required Nominatim readiness marker is missing: $marker" >&2
    echo "Complete the maps-import profile first." >&2
    exit 1
  fi
done

set -- docker compose --env-file "$env_file" -f "$root/docker-compose.staging.yml" up -d
if [ "$wait_for_health" = true ]; then set -- "$@" --wait; fi
set -- "$@" martin nominatim
exec "$@"
