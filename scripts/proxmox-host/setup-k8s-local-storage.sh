#!/usr/bin/env bash
set -euo pipefail

appdata_mount="/mnt/hd2tb-k8s-appdata"
host_dir="${appdata_mount}/local-pv"
container_id="240"
container_mount="/var/lib/local-pv"

if [ "$(id -u)" -ne 0 ]; then
  echo "run this as root on the proxmox host" >&2
  exit 1
fi

if ! mountpoint -q "$appdata_mount"; then
  echo "$appdata_mount is not mounted, refusing to create the directory on the root disk" >&2
  exit 1
fi

mkdir -p "$host_dir"

config="$(pct config "$container_id")"
current="$(sed -n 's/^mp0: //p' <<<"$config")"
want="${host_dir},mp=${container_mount}"

if [ -z "$current" ]; then
  pct set "$container_id" -mp0 "$want"
  echo "mount point added to LXC ${container_id}; run 'pct reboot ${container_id}' for it to take effect"
elif [[ "$current" != "$want" && "$current" != "$want,"* ]]; then
  echo "LXC ${container_id} already has a different mp0: ${current}" >&2
  exit 1
fi

df -h "$host_dir"
final_config="$(pct config "$container_id")"
grep "^mp0:" <<<"$final_config"
