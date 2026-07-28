#!/usr/bin/env sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH= cd -- "$script_dir/../.." && pwd)
env_file="$root/.env.staging"
state_root=/opt/now/data/deployments
image_tag=

while [ "$#" -gt 0 ]; do
  case "$1" in
    --env-file) [ "$#" -ge 2 ] || exit 2; env_file=$2; shift ;;
    --image-tag) [ "$#" -ge 2 ] || exit 2; image_tag=$2; shift ;;
    --help|-h)
      echo "Usage: ./scripts/deploy/rollback-staging.sh [--image-tag <previous-tag>] [--env-file <path>]"
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

[ -f "$env_file" ] || { echo "Staging env file not found: $env_file" >&2; exit 1; }
if [ -z "$image_tag" ] && [ -f "$state_root/previous" ]; then
  image_tag=$(sed -n 's/^IMAGE_TAG=//p' "$state_root/previous")
fi
case "$image_tag" in ''|*[!A-Za-z0-9_.-]*) echo "A valid previous image tag is required" >&2; exit 2 ;; esac

export IMAGE_TAG="$image_tag"
docker image inspect "seychas-api:$image_tag" >/dev/null
docker image inspect "seychas-worker:$image_tag" >/dev/null
docker compose --env-file "$env_file" -f "$root/docker-compose.staging.yml" up -d --no-build --wait --wait-timeout 600
echo "Rolled staging application images back to $image_tag. Database migrations were not reversed."
