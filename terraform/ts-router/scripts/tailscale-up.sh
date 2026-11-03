#!/usr/bin/env bash
# Usage: tailscale-up.sh <proxmox_host> <vm_id> <advertise_route> <hostname>
# Needs TS_AUTHKEY in the environment. The key goes over ssh stdin so it never
# shows up in a process list or in tofu state.
set -euo pipefail

host=$1 vm_id=$2 route=$3 name=$4

if [ -z "${TS_AUTHKEY:-}" ]; then
  echo "TS_AUTHKEY is not set: generate a one-time auth key in the Tailscale admin console and export it (or put it in .env)" >&2
  exit 1
fi

printf '%s\n' "$TS_AUTHKEY" | ssh "root@${host}" \
  "pct exec ${vm_id} -- sh -c 'read -r key && tailscale up --auth-key=\"\$key\" --advertise-routes=${route} --hostname=${name} --accept-dns=false'"
