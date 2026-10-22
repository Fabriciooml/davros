#!/usr/bin/env bash
set -euo pipefail

container_id="${1:-104}"

if [ "$(id -u)" -ne 0 ]; then
  echo "run this as root on the proxmox host" >&2
  exit 1
fi

pct exec "$container_id" -- docker ps --format '{{.Names}}' | sort | while read -r name; do
  pct exec "$container_id" -- docker inspect "$name" --format \
    '{{.Name}}|{{.Config.Image}}|{{index .Config.Labels "org.opencontainers.image.version"}}|{{.Image}}|{{.Created}}'
done
