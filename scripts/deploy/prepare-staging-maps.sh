#!/usr/bin/env sh
set -eu

usage() {
  cat <<'EOF'
Usage: ./scripts/deploy/prepare-staging-maps.sh [options]

Download and verify the pinned pilot extract, build MBTiles, publish artifacts
to persistent staging storage, and perform the one-time Nominatim import.

Options:
  --env-file <path>   Staging env file (default: .env.staging)
  --data-root <path>  Persistent data root (default: /opt/now/data)
  --force-import      Re-import only when no completed Nominatim DB exists
  --help              Show this help
EOF
}

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH= cd -- "$script_dir/../.." && pwd)
env_file="$root/.env.staging"
data_root=${NOW_DATA_ROOT:-/opt/now/data}
force_import=false

while [ "$#" -gt 0 ]; do
  case "$1" in
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
    --force-import) force_import=true ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

[ -f "$env_file" ] || { echo "Staging env file not found: $env_file" >&2; exit 1; }
case "$data_root" in ''|/) echo "Unsafe data root" >&2; exit 2 ;; esac
command -v docker >/dev/null 2>&1 || { echo "Docker Compose v2 is required" >&2; exit 1; }

cd "$root"
sh scripts/maps/download-region.sh
sh scripts/maps/build-tiles.sh --force
sh scripts/maps/validate-map.sh --mbtiles infra/maps/data/seychas-v1.mbtiles

map_target="$data_root/maps"
mkdir -p -- "$map_target" "$data_root/nominatim" "$data_root/nginx-map-cache"
for name in region.osm.pbf region.osm.pbf.metadata.json seychas-v1.mbtiles; do
  cp -- "$root/infra/maps/data/$name" "$map_target/$name.new"
  mv -f -- "$map_target/$name.new" "$map_target/$name"
done

# nginx-unprivileged runs as uid/gid 101. Prepare only its non-sensitive cache
# bind mount; map/database directories keep their service-specific ownership.
docker run --rm --network none --user 0:0 \
  --volume "$data_root/nginx-map-cache:/cache" \
  nginxinc/nginx-unprivileged:1.29-alpine \
  chown -R 101:101 /cache

if [ -f "$data_root/nominatim/import-finished" ] && [ "$force_import" != true ]; then
  echo "Nominatim import already exists; verified map artifacts were refreshed only."
  exit 0
fi
if [ "$force_import" = true ]; then
  echo "Refusing an in-place destructive Nominatim re-import. Move the existing data directory to a backup first." >&2
  [ ! -e "$data_root/nominatim/import-finished" ] || exit 1
fi

# PG_VERSION alone is not proof of a usable import: initdb creates it before
# Nominatim loads any OSM data. Refuse to reuse a partial cluster so operators
# can move/remove that generated directory explicitly and retry from the PBF.
if [ -e "$data_root/nominatim/PG_VERSION" ]; then
  echo "Incomplete Nominatim database found (missing import-finished); move or remove the partial directory before retrying." >&2
  exit 1
fi

compose() {
  docker compose --env-file "$env_file" -f "$root/docker-compose.staging.yml" "$@"
}
compose --profile maps-import config --quiet
compose --profile maps-import up -d --wait --wait-timeout 3600 nominatim-import
compose --profile maps-import stop nominatim-import
compose --profile maps-import rm -f nominatim-import
[ -f "$data_root/nominatim/PG_VERSION" ] && [ -f "$data_root/nominatim/import-finished" ] || {
  echo "Nominatim import did not complete" >&2
  exit 1
}
echo "Verified pilot tiles and Nominatim database are ready in $data_root."
