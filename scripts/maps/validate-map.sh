#!/usr/bin/env sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH= cd -- "$script_dir/../.." && pwd)
. "$root/scripts/maps/node-runtime.sh"

cd "$root"
map_node scripts/maps/validate-map-style.mjs "$@"
