#!/usr/bin/env bash
set -euo pipefail

export_path="/pool/data"
client_cidr="192.168.31.240/29"
export_options="rw,sync,no_subtree_check,no_root_squash"
export_line="${export_path} ${client_cidr}(${export_options})"
exports_file="/etc/exports"

if [ "$(id -u)" -ne 0 ]; then
  echo "run this as root on the proxmox host" >&2
  exit 1
fi

if ! dpkg -s nfs-kernel-server >/dev/null 2>&1; then
  apt-get update
  apt-get install -y nfs-kernel-server
fi

if [ ! -f "$exports_file" ]; then
  touch "$exports_file"
fi

if ! grep -qxF "$export_line" "$exports_file"; then
  echo "$export_line" >> "$exports_file"
fi

systemctl enable --now nfs-kernel-server
exportfs -ra
exportfs -v
