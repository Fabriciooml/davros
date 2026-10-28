#!/usr/bin/env bash
set -euo pipefail

storage_id="hd2tb-backup"
script_src="$(cd "$(dirname "$0")" && pwd)/k8s-data-backup.sh"
script_dst="/usr/local/sbin/k8s-data-backup.sh"
cron_file="/etc/cron.d/k8s-data-backup"
cron_line="45 2 * * * root flock -n /run/k8s-data-backup.lock ${script_dst} >> /var/log/k8s-data-backup.log 2>&1"

if [ "$(id -u)" -ne 0 ]; then
  echo "run this as root on the proxmox host" >&2
  exit 1
fi

if ! pvesm status --storage "$storage_id" >/dev/null 2>&1; then
  echo "storage $storage_id not found, run setup-backup-storage.sh first" >&2
  exit 1
fi

if [ ! -f "$script_src" ]; then
  echo "backup script $script_src not found, copy k8s-data-backup.sh next to this installer" >&2
  exit 1
fi

for tool in rsync flock; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "$tool is not installed, install it before running this installer" >&2
    exit 1
  fi
done

install -m 0755 "$script_src" "$script_dst"

if [ "$(cat "$cron_file" 2>/dev/null || true)" != "$cron_line" ]; then
  echo "$cron_line" > "$cron_file"
  chmod 0644 "$cron_file"
fi

cat "$cron_file"
