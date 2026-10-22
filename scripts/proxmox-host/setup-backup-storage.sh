#!/usr/bin/env bash
set -euo pipefail

vg="HD_2TB"
lv="hd2tb-backup"
lv_size="300G"
mount_point="/mnt/hd2tb-backup"
storage_id="hd2tb-backup"
prune_options="keep-daily=7,keep-weekly=4"
device="/dev/${vg}/${lv}"
fstab_line="${device} ${mount_point} ext4 defaults,nofail 0 2"

if [ "$(id -u)" -ne 0 ]; then
  echo "run this as root on the proxmox host" >&2
  exit 1
fi

if ! lvs "${vg}/${lv}" >/dev/null 2>&1; then
  lvcreate -L "$lv_size" -n "$lv" "$vg"
fi

if ! blkid "$device" >/dev/null 2>&1; then
  mkfs.ext4 -L "$lv" "$device"
fi

mkdir -p "$mount_point"

if ! grep -qxF "$fstab_line" /etc/fstab; then
  echo "$fstab_line" >> /etc/fstab
  systemctl daemon-reload
fi

if ! mountpoint -q "$mount_point"; then
  mount "$mount_point"
fi

if ! pvesm status --storage "$storage_id" >/dev/null 2>&1; then
  pvesm add dir "$storage_id" \
    --path "$mount_point" \
    --content backup \
    --is_mountpoint yes \
    --prune-backups "$prune_options"
fi

pvesm status --storage "$storage_id"
df -h "$mount_point"
