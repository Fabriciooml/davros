#!/usr/bin/env bash
set -euo pipefail

dest_root="${DEST_ROOT:-/mnt/hd2tb-backup/k8s-data}"
sources="${SOURCES:-/mnt/hd2tb-k8s-appdata}"
keep="${KEEP:-7}"
stamp="${STAMP:-$(date +%Y-%m-%d)}"
backup_mount="${BACKUP_MOUNT-/mnt/hd2tb-backup}"
source_mount_check="${SOURCE_MOUNT_CHECK:-1}"

if ! [[ "$keep" =~ ^[1-9][0-9]*$ ]]; then
  echo "KEEP must be a positive integer, got '$keep'" >&2
  exit 1
fi

if [ -n "$backup_mount" ] && ! mountpoint -q "$backup_mount"; then
  echo "backup storage $backup_mount is not mounted, refusing to run" >&2
  exit 1
fi

if [ "$source_mount_check" != "0" ]; then
  for src in $sources; do
    if ! mountpoint -q "$src"; then
      echo "$src is not mounted, refusing to run" >&2
      exit 1
    fi
  done
fi

mkdir -p "$dest_root"

previous=$(find "$dest_root" -mindepth 1 -maxdepth 1 -type d -name '[0-9]*' ! -name "$stamp" | sort | tail -n 1)
target="$dest_root/$stamp"
mkdir -p "$target"

for src in $sources; do
  name=$(basename "$src")
  mkdir -p "$target/$name"
  link_args=()
  if [ -n "$previous" ] && [ -d "$previous/$name" ]; then
    link_args=(--link-dest="$previous/$name")
  fi
  rsync_rc=0
  rsync -aHAX --numeric-ids --delete "${link_args[@]}" "$src/" "$target/$name/" || rsync_rc=$?
  if [ "$rsync_rc" -eq 24 ]; then
    echo "warning: rsync exit 24 (some source files vanished) for $src, continuing" >&2
  elif [ "$rsync_rc" -ne 0 ]; then
    echo "rsync failed for $src with exit $rsync_rc, refusing to continue" >&2
    exit "$rsync_rc"
  fi
done

find "$dest_root" -mindepth 1 -maxdepth 1 -type d -name '[0-9]*' | sort | head -n "-$keep" | xargs -r rm -rf
