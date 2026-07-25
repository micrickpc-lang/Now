#!/usr/bin/env sh
set -eu

usage() {
  cat <<'EOF'
Usage: ./scripts/deploy/deploy-staging.sh [options]

Build immutable API/worker images for the current Git revision, apply
migrations, start the isolated staging stack and wait for all healthchecks.

Options:
  --env-file <path>  Staging env file (default: .env.staging)
  --image-tag <tag>  Override immutable image tag (default: current Git SHA)
  --help              Show this help
EOF
}

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH= cd -- "$script_dir/../.." && pwd)
env_file="$root/.env.staging"
image_tag=

while [ "$#" -gt 0 ]; do
  case "$1" in
    --env-file)
      [ "$#" -ge 2 ] || { echo "--env-file requires a path" >&2; exit 2; }
      env_file=$2
      shift
      ;;
    --image-tag)
      [ "$#" -ge 2 ] || { echo "--image-tag requires a value" >&2; exit 2; }
      image_tag=$2
      shift
      ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

[ -f "$env_file" ] || { echo "Staging env file not found: $env_file" >&2; exit 1; }
command -v git >/dev/null 2>&1 || { echo "git is required" >&2; exit 1; }
command -v docker >/dev/null 2>&1 || { echo "Docker Compose v2 is required" >&2; exit 1; }
if [ -z "$image_tag" ]; then image_tag=$(git -C "$root" rev-parse --short=12 HEAD); fi
case "$image_tag" in ''|*[!A-Za-z0-9_.-]*) echo "Invalid image tag" >&2; exit 2 ;; esac

for artifact in \
  /opt/now/data/maps/region.osm.pbf \
  /opt/now/data/maps/seychas-v1.mbtiles \
  /opt/now/data/nominatim/PG_VERSION; do
  [ -f "$artifact" ] || { echo "Required runtime artifact missing: $artifact" >&2; exit 1; }
done

export IMAGE_TAG="$image_tag"
compose() {
  docker compose --env-file "$env_file" -f "$root/docker-compose.staging.yml" "$@"
}
cd "$root"
compose config --quiet
compose build migrate api worker
compose up -d --wait --wait-timeout 600

state_root=/opt/now/data/deployments
mkdir -p -- "$state_root"
if [ -f "$state_root/current" ]; then cp -- "$state_root/current" "$state_root/previous"; fi
{
  printf 'IMAGE_TAG=%s\n' "$image_tag"
  printf 'GIT_SHA=%s\n' "$(git rev-parse HEAD)"
} > "$state_root/current.new"
chmod 600 "$state_root/current.new"
mv -f -- "$state_root/current.new" "$state_root/current"
echo "Staging deployment is healthy (image tag: $image_tag)."
