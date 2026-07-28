#!/usr/bin/env sh
set -eu

usage() {
  cat <<'EOF'
Usage: ./scripts/maps/update-map-data.sh [options]

Download a checksum-verified Monaco PBF, rebuild v1 tiles, validate the result,
publish artifacts atomically to staging data, and restart Martin only.

Options:
  --env-file <path>   Staging env file (default: .env.staging)
  --data-root <path>  Persistent root (default: NOW_DATA_ROOT or /opt/now/data)
  --no-restart        Publish files without restarting Martin
  --help              Show this help

Nominatim is not re-imported by this command. Use the explicit maps-import
maintenance procedure for geocoder data changes.
EOF
}

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH= cd -- "$script_dir/../.." && pwd)
env_file="$root/.env.staging"
data_root=${NOW_DATA_ROOT:-/opt/now/data}
restart=true

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
    --no-restart) restart=false ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

case "$data_root" in ''|/) echo "--data-root cannot be empty or /" >&2; exit 2 ;; esac
command -v docker >/dev/null 2>&1 || { echo "docker is required" >&2; exit 1; }
. "$root/scripts/maps/node-runtime.sh"

cd "$root"
map_node scripts/maps/download-region.mjs --force
sh "$root/scripts/maps/build-tiles.sh" --force
map_node scripts/maps/validate-map-style.mjs --mbtiles infra/maps/data/seychas-v1.mbtiles

target="$data_root/maps"
mkdir -p -- "$target"
for name in region.osm.pbf region.osm.pbf.metadata.json seychas-v1.mbtiles; do
  cp -- "$root/infra/maps/data/$name" "$target/$name.new"
  mv -f -- "$target/$name.new" "$target/$name"
done

if [ "$restart" = true ]; then
  [ -f "$env_file" ] || { echo "Staging env file not found: $env_file" >&2; exit 1; }
  docker compose --env-file "$env_file" -f "$root/docker-compose.staging.yml" restart martin
fi
echo "Map tiles updated. Nominatim data was not re-imported."
