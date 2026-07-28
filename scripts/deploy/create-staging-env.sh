#!/usr/bin/env sh
set -eu

usage() {
  cat <<'EOF'
Usage: ./scripts/deploy/create-staging-env.sh --public-ip <IPv4> --phone-allowlist <E.164,...> [options]

Create a private standalone-staging environment file. All credentials and the
staging-only OTP are generated locally on the server and are never printed.

Options:
  --public-ip <IPv4>          Public staging address
  --phone-allowlist <list>    Comma-separated disposable E.164 test numbers
  --output <path>             Destination (default: .env.staging)
  --force                     Replace an existing destination atomically
  --help                      Show this help
EOF
}

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH= cd -- "$script_dir/../.." && pwd)
public_ip=
phone_allowlist=
output="$root/.env.staging"
force=false

while [ "$#" -gt 0 ]; do
  case "$1" in
    --public-ip)
      [ "$#" -ge 2 ] || { echo "--public-ip requires a value" >&2; exit 2; }
      public_ip=$2
      shift
      ;;
    --phone-allowlist)
      [ "$#" -ge 2 ] || { echo "--phone-allowlist requires a value" >&2; exit 2; }
      phone_allowlist=$2
      shift
      ;;
    --output)
      [ "$#" -ge 2 ] || { echo "--output requires a path" >&2; exit 2; }
      output=$2
      shift
      ;;
    --force) force=true ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

case "$public_ip" in
  ''|*[!0-9.]*) echo "--public-ip must be an IPv4 address" >&2; exit 2 ;;
esac
old_ifs=$IFS
IFS=.
set -- $public_ip
IFS=$old_ifs
[ "$#" -eq 4 ] || { echo "--public-ip must contain four octets" >&2; exit 2; }
for octet in "$@"; do
  case "$octet" in ''|*[!0-9]*) echo "Invalid IPv4 octet" >&2; exit 2 ;; esac
  [ "$octet" -le 255 ] || { echo "Invalid IPv4 octet" >&2; exit 2; }
done

[ -n "$phone_allowlist" ] || { echo "--phone-allowlist is required" >&2; exit 2; }
old_ifs=$IFS
IFS=,
set -- $phone_allowlist
IFS=$old_ifs
for phone in "$@"; do
  case "$phone" in
    +[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]*) ;;
    *) echo "Every allowlisted phone must be normalized E.164" >&2; exit 2 ;;
  esac
done

command -v openssl >/dev/null 2>&1 || { echo "openssl is required" >&2; exit 1; }
command -v od >/dev/null 2>&1 || { echo "od is required" >&2; exit 1; }
case "$output" in ''|/) echo "Unsafe output path" >&2; exit 2 ;; esac
if [ -e "$output" ] && [ "$force" != true ]; then
  echo "Destination already exists; pass --force to replace it" >&2
  exit 1
fi

umask 077
mkdir -p -- "$(dirname -- "$output")"
temporary="$output.new"
trap 'rm -f -- "$temporary"' EXIT HUP INT TERM

random_hex() { openssl rand -hex 32; }
location_key=$(openssl rand -base64 32 | tr -d '\r\n')
otp_source=$(od -An -N3 -tu4 /dev/urandom | tr -d ' ')
staging_otp=$(printf '%06d' "$((otp_source % 1000000))")

{
  printf '%s\n' "PUBLIC_IP=$public_ip"
  printf '%s\n' "STAGING_BIND_ADDRESS=0.0.0.0"
  printf '%s\n' "NOW_DATA_ROOT=/opt/now/data"
  printf '%s\n' "IMAGE_TAG=staging"
  printf '%s\n' "POSTGRES_DB=seychas"
  printf '%s\n' "POSTGRES_USER=seychas"
  printf '%s\n' "POSTGRES_PASSWORD=$(random_hex)"
  printf '%s\n' "NOMINATIM_PASSWORD=$(random_hex)"
  printf '%s\n' "JWT_SECRET=$(random_hex)"
  printf '%s\n' "TOKEN_HASH_SECRET=$(random_hex)"
  printf '%s\n' "PHONE_HASH_SECRET=$(random_hex)"
  printf '%s\n' "LOCATION_MASTER_KEY_BASE64=$location_key"
  printf '%s\n' "LOCATION_PRIVACY_SECRET=$(random_hex)"
  printf '%s\n' "ADMIN_SESSION_SECRET=$(random_hex)"
  printf '%s\n' "STAGING_TEST_PHONE_ALLOWLIST=$phone_allowlist"
  printf '%s\n' "STAGING_TEST_OTP=$staging_otp"
} > "$temporary"
chmod 600 "$temporary"
mv -f -- "$temporary" "$output"
trap - EXIT HUP INT TERM
echo "Created private staging environment at $output (mode 600); secret values were not printed."
