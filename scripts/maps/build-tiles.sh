#!/usr/bin/env sh
set -eu

usage() {
  cat <<'EOF'
Usage: ./scripts/maps/build-tiles.sh [options]

Build infra/maps/data/seychas-v1.mbtiles with the repository-pinned Tilemaker
image and profile. The verified PBF and checksum sidecar must already exist.

Options:
  --force  Atomically replace an existing v1 MBTiles file
  --help   Show this help
EOF
}

force=false
while [ "$#" -gt 0 ]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --force) force=true ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

command -v docker >/dev/null 2>&1 || { echo "docker is required" >&2; exit 1; }

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH= cd -- "$script_dir/../.." && pwd)
. "$root/scripts/maps/node-runtime.sh"
data="$root/infra/maps/data"
source="$data/region.osm.pbf"
output="$data/seychas-v1.mbtiles"
partial="$output.partial"
tilemaker="$root/infra/maps/tilemaker"
image=$(tr -d '\r\n' < "$tilemaker/image.txt")

if ! printf '%s\n' "$image" | grep -Eq '^ghcr\.io/systemed/tilemaker@sha256:[a-f0-9]{64}$'; then
  echo "Tilemaker image must be pinned to an immutable sha256 digest" >&2
  exit 1
fi
if [ -e "$output" ] && [ "$force" != true ]; then
  echo "Versioned MBTiles already exists; pass --force to replace it" >&2
  exit 1
fi

cd "$root"
map_node scripts/maps/download-region.mjs --verify-only
map_node scripts/maps/generate-assets.mjs
rm -f -- "$partial"
docker run --rm --network none --cpus 1.5 --memory 768m --pids-limit 256 \
  --user "$(id -u):$(id -g)" \
  -v "$data:/data" \
  -v "$tilemaker:/config:ro" \
  "$image" \
  /data/region.osm.pbf \
  --output /data/seychas-v1.mbtiles.partial \
  --config /config/config.json \
  --process /config/process.lua

if [ ! -f "$partial" ]; then
  echo "Tilemaker failed to produce the versioned MBTiles file" >&2
  exit 1
fi
map_node scripts/maps/validate-map-style.mjs \
  --mbtiles infra/maps/data/seychas-v1.mbtiles.partial
mv -f -- "$partial" "$output"
echo "Built $output with $image"
