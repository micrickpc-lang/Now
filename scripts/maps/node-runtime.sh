#!/usr/bin/env sh

# Source this file after defining `root`. It keeps map commands usable on the
# deployment host without installing Node system-wide. Generated files retain
# the invoking user's uid/gid.
map_node() {
  if command -v node >/dev/null 2>&1 && node -e 'process.exit(Number(process.versions.node.split(".")[0]) >= 24 ? 0 : 1)' >/dev/null 2>&1; then
    node "$@"
    return
  fi
  if ! command -v docker >/dev/null 2>&1; then
    echo "Node.js 24+ or Docker is required" >&2
    return 1
  fi
  docker run --rm --init \
    --user "$(id -u):$(id -g)" \
    --volume "$root:/workspace" \
    --workdir /workspace \
    "${MAP_NODE_IMAGE:-node:24-bookworm-slim}" \
    node "$@"
}
