#!/usr/bin/env sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH= cd -- "$script_dir/../.." && pwd)

command -v node >/dev/null 2>&1 || { echo "Node.js 24+ is required" >&2; exit 1; }
exec node "$root/scripts/security/check-forbidden-map-dependencies.mjs" "$@"
