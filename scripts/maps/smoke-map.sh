#!/usr/bin/env sh
set -eu

usage() {
  cat <<'EOF'
Usage: ./scripts/maps/smoke-map.sh [options]

Probe staging health and versioned map resources. The report records HTTP
status, content type and byte count; it does not claim visual rendering works.

Options:
  --base-url <url>  Staging origin (default: http://127.0.0.1)
  --timeout <sec>   Per-request timeout (default: 15)
  --help            Show this help
EOF
}

base_url=http://127.0.0.1
timeout=15
while [ "$#" -gt 0 ]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --base-url)
      [ "$#" -ge 2 ] || { echo "--base-url requires a URL" >&2; exit 2; }
      base_url=$2
      shift
      ;;
    --timeout)
      [ "$#" -ge 2 ] || { echo "--timeout requires seconds" >&2; exit 2; }
      timeout=$2
      shift
      ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

case "$base_url" in
  http://*|https://*) ;;
  *) echo "--base-url must be HTTP(S)" >&2; exit 2 ;;
esac
case "$base_url" in
  *\?*|*\#*) echo "--base-url must not contain query or fragment data" >&2; exit 2 ;;
esac
case "$timeout" in
  ''|*[!0-9]*) echo "--timeout must be a positive integer" >&2; exit 2 ;;
esac
[ "$timeout" -gt 0 ] || { echo "--timeout must be positive" >&2; exit 2; }
if ! command -v curl >/dev/null 2>&1; then
  echo "curl is required" >&2
  exit 1
fi

base_url=${base_url%/}
temporary=$(mktemp -d "${TMPDIR:-/tmp}/seychas-map-smoke.XXXXXX")
trap 'rm -rf -- "$temporary"' EXIT HUP INT TERM
failures=0

printf '%-52s %6s %-40s %10s\n' PATH STATUS CONTENT_TYPE BYTES
probe() {
  path=$1
  kind=$2
  minimum=$3
  expected_status=${4:-200}
  expected_body=${5:-}
  headers="$temporary/headers"
  body="$temporary/body"
  : > "$headers"
  : > "$body"
  status=$(curl --silent --show-error --max-time "$timeout" \
    --dump-header "$headers" --output "$body" --write-out '%{http_code}' \
    "$base_url$path") || status=000
  content_type=$(tr -d '\r' < "$headers" | awk -F ': *' \
    'tolower($1)=="content-type" { value=$2 } END { print value }')
  bytes=$(wc -c < "$body" | tr -d ' ')
  printf '%-52s %6s %-40s %10s\n' "$path" "$status" "${content_type:--}" "$bytes"

  valid_type=false
  case "$kind:$content_type" in
    json:application/json*|json:application/*+json*) valid_type=true ;;
    png:image/png*) valid_type=true ;;
    pbf:application/x-protobuf*|pbf:application/vnd.mapbox-vector-tile*|pbf:application/octet-stream*) valid_type=true ;;
  esac
  body_matches=true
  if [ -n "$expected_body" ] && ! grep -F -q -- "$expected_body" "$body"; then
    body_matches=false
  fi
  if [ "$status" != "$expected_status" ] || [ "$valid_type" != true ] || \
    [ "$bytes" -lt "$minimum" ] || [ "$body_matches" != true ]; then
    failures=$((failures + 1))
  fi
}

probe /health json 2
probe /api/v1/maps/style.json json 100 200 '/maps/v1/tiles/{z}/{x}/{y}.pbf'
probe /api/v1/maps/tilejson.json json 100 200 '/api/v1/maps/tiles/{z}/{x}/{y}.pbf'
probe /api/v1/maps/tiles/14/8529/5974.pbf pbf 1
probe /api/v1/maps/search json 2 401
probe /api/v1/maps/reverse json 2 401
probe /maps/v1/style.json json 100 200 '/maps/v1/sprites/sprite'
probe /maps/v1/sprites/sprite.json json 2
probe /maps/v1/sprites/sprite.png png 16
probe /maps/v1/sprites/sprite@2x.json json 2
probe /maps/v1/sprites/sprite@2x.png png 16
probe '/maps/v1/glyphs/Noto%20Sans%20Regular/0-255.pbf' pbf 8
probe /maps/v1/tiles/14/8529/5974.pbf pbf 1

if [ "$failures" -ne 0 ]; then
  echo "$failures map smoke probe(s) failed" >&2
  exit 1
fi
echo "Transport smoke passed. Device/MapLibre rendering remains a separate acceptance check."
