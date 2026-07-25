#!/usr/bin/env sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH= cd -- "$script_dir/../.." && pwd)
env_file=${1:-"$root/.env.staging"}
backup_root=${NOW_BACKUP_ROOT:-/opt/now/backups}
[ -f "$env_file" ] || { echo "Staging env file not found: $env_file" >&2; exit 1; }
case "$backup_root" in ''|/) echo "Unsafe backup root" >&2; exit 2 ;; esac
mkdir -p -- "$backup_root"
umask 077
stamp=$(date -u +%Y%m%dT%H%M%SZ)
destination="$backup_root/postgres-$stamp.dump"
temporary="$destination.partial"
trap 'rm -f -- "$temporary"' EXIT HUP INT TERM
docker compose --env-file "$env_file" -f "$root/docker-compose.staging.yml" exec -T postgres \
  sh -c 'exec pg_dump --format=custom --no-owner --no-privileges --username="$POSTGRES_USER" --dbname="$POSTGRES_DB"' \
  > "$temporary"
[ -s "$temporary" ] || { echo "Database backup is empty" >&2; exit 1; }
chmod 600 "$temporary"
mv -- "$temporary" "$destination"
sha256sum "$destination" > "$destination.sha256"
chmod 600 "$destination.sha256"
trap - EXIT HUP INT TERM
echo "Created restricted staging database backup: $destination"
