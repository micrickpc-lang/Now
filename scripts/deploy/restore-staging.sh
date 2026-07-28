#!/usr/bin/env sh
set -eu

usage() {
  echo "Usage: ./scripts/deploy/restore-staging.sh --backup /opt/now/backups/<file>.dump --confirm RESTORE_STAGING [--env-file <path>]"
}

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH= cd -- "$script_dir/../.." && pwd)
env_file="$root/.env.staging"
backup=
confirmation=
while [ "$#" -gt 0 ]; do
  case "$1" in
    --backup) [ "$#" -ge 2 ] || exit 2; backup=$2; shift ;;
    --confirm) [ "$#" -ge 2 ] || exit 2; confirmation=$2; shift ;;
    --env-file) [ "$#" -ge 2 ] || exit 2; env_file=$2; shift ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

[ "$confirmation" = RESTORE_STAGING ] || { echo "Explicit --confirm RESTORE_STAGING is required" >&2; exit 2; }
case "$backup" in /opt/now/backups/*.dump) ;; *) echo "Backup must be an absolute .dump under /opt/now/backups" >&2; exit 2 ;; esac
[ -f "$backup" ] && [ -s "$backup" ] || { echo "Backup does not exist or is empty" >&2; exit 1; }
[ -f "$env_file" ] || { echo "Staging env file not found: $env_file" >&2; exit 1; }
if [ -f "$backup.sha256" ]; then (cd "$(dirname -- "$backup")" && sha256sum -c "$(basename -- "$backup.sha256")"); fi

compose() {
  docker compose --env-file "$env_file" -f "$root/docker-compose.staging.yml" "$@"
}
compose stop nginx api worker
compose exec -T postgres sh -c \
  'exec pg_restore --clean --if-exists --exit-on-error --no-owner --no-privileges --username="$POSTGRES_USER" --dbname="$POSTGRES_DB"' \
  < "$backup"
compose up -d --wait --wait-timeout 600
echo "Staging database restore completed and the stack is healthy."
