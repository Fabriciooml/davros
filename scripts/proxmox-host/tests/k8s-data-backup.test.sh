#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
script="$here/../k8s-data-backup.sh"
# capture the real rsync before any test alters PATH
real_rsync=$(command -v rsync) || { echo "FAIL: rsync is required for this test"; exit 1; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/src/appdata" "$work/src/local"
echo one > "$work/src/appdata/a.txt"
echo two > "$work/src/local/b.txt"

run() {
  DEST_ROOT="$work/dest" SOURCES="$work/src/appdata $work/src/local" KEEP=2 BACKUP_MOUNT="" SOURCE_MOUNT_CHECK=0 STAMP="$1" bash "$script"
}

run 2026-01-01
[ "$(cat "$work/dest/2026-01-01/appdata/a.txt")" = "one" ] || { echo "FAIL: day 1 copy of appdata missing"; exit 1; }
[ "$(cat "$work/dest/2026-01-01/local/b.txt")" = "two" ] || { echo "FAIL: day 1 copy of local missing"; exit 1; }

run 2026-01-02
inode1=$(stat -c %i "$work/dest/2026-01-01/appdata/a.txt")
inode2=$(stat -c %i "$work/dest/2026-01-02/appdata/a.txt")
[ "$inode1" = "$inode2" ] || { echo "FAIL: unchanged file must be hardlinked to the previous day"; exit 1; }

echo changed > "$work/src/appdata/a.txt"
run 2026-01-03
[ "$(cat "$work/dest/2026-01-03/appdata/a.txt")" = "changed" ] || { echo "FAIL: day 3 must hold the new content"; exit 1; }
[ "$(cat "$work/dest/2026-01-02/appdata/a.txt")" = "one" ] || { echo "FAIL: older day must keep the old content"; exit 1; }

[ ! -e "$work/dest/2026-01-01" ] || { echo "FAIL: KEEP=2 must prune the oldest day"; exit 1; }
[ -d "$work/dest/2026-01-02" ] && [ -d "$work/dest/2026-01-03" ] || { echo "FAIL: the two newest days must remain"; exit 1; }

if err=$(DEST_ROOT="$work/dest" SOURCES="$work/src/appdata" KEEP=2 BACKUP_MOUNT="$work/not-a-mountpoint" SOURCE_MOUNT_CHECK=0 STAMP=2026-01-04 bash "$script" 2>&1); then
  echo "FAIL: must refuse to run when the backup storage is not a mountpoint"
  exit 1
fi
case "$err" in *"not mounted"*) ;; *) echo "FAIL: backup mount refusal must say 'not mounted', got: $err"; exit 1 ;; esac

if err=$(DEST_ROOT="$work/dest" SOURCES="$work/src/appdata" KEEP=2 BACKUP_MOUNT="" SOURCE_MOUNT_CHECK=1 STAMP=2026-01-04 bash "$script" 2>&1); then
  echo "FAIL: must refuse to run when a source is not a mountpoint"
  exit 1
fi
case "$err" in *"not mounted"*) ;; *) echo "FAIL: source refusal must say 'not mounted', got: $err"; exit 1 ;; esac
[ ! -e "$work/dest/2026-01-04" ] || { echo "FAIL: refused run must not create a snapshot"; exit 1; }

if err=$(DEST_ROOT="$work/dest" SOURCES="$work/src/appdata" KEEP=0 BACKUP_MOUNT="" SOURCE_MOUNT_CHECK=0 STAMP=2026-01-05 bash "$script" 2>&1); then
  echo "FAIL: KEEP=0 must be rejected"
  exit 1
fi
case "$err" in *"KEEP"*) ;; *) echo "FAIL: KEEP=0 rejection must name KEEP, got: $err"; exit 1 ;; esac

# stub rsync: runs the real rsync, then exits with the given code
stub_rsync() {
  mkdir -p "$1"
  printf '#!/usr/bin/env bash\n"%s" "$@"\nexit %s\n' "$real_rsync" "$2" > "$1/rsync"
  chmod +x "$1/rsync"
}
stub_rsync "$work/stub24" 24
stub_rsync "$work/stub23" 23

# rsync exit 24 (vanished files) must warn, keep going, and still prune
for d in 2026-02-01 2026-02-02 2026-02-03; do
  err=$(PATH="$work/stub24:$PATH" DEST_ROOT="$work/dest24" SOURCES="$work/src/appdata $work/src/local" KEEP=2 BACKUP_MOUNT="" SOURCE_MOUNT_CHECK=0 STAMP="$d" bash "$script" 2>&1 >/dev/null) \
    || { echo "FAIL: rsync exit 24 must not abort the run ($d)"; exit 1; }
done
case "$err" in *"vanished"*) ;; *) echo "FAIL: rsync exit 24 must print a vanished-files warning, got: $err"; exit 1 ;; esac
[ "$(cat "$work/dest24/2026-02-03/appdata/a.txt")" = "changed" ] || { echo "FAIL: run after exit 24 must still copy the sources"; exit 1; }
[ ! -e "$work/dest24/2026-02-01" ] || { echo "FAIL: run after exit 24 must still prune"; exit 1; }

# any other rsync failure (exit 23) must fail the run with that code
rc=0
PATH="$work/stub23:$PATH" DEST_ROOT="$work/dest23" SOURCES="$work/src/appdata" KEEP=2 BACKUP_MOUNT="" SOURCE_MOUNT_CHECK=0 STAMP=2026-02-01 bash "$script" >/dev/null 2>&1 || rc=$?
[ "$rc" = 23 ] || { echo "FAIL: rsync exit 23 must fail the run with exit 23, got $rc"; exit 1; }

# --delete: a same-day re-run drops files removed from the source
echo keep > "$work/src/appdata/keep.txt"
echo gone > "$work/src/appdata/gone.txt"
DEST_ROOT="$work/dest-del" SOURCES="$work/src/appdata" KEEP=2 BACKUP_MOUNT="" SOURCE_MOUNT_CHECK=0 STAMP=2026-03-01 bash "$script"
rm "$work/src/appdata/gone.txt"
DEST_ROOT="$work/dest-del" SOURCES="$work/src/appdata" KEEP=2 BACKUP_MOUNT="" SOURCE_MOUNT_CHECK=0 STAMP=2026-03-01 bash "$script"
[ ! -e "$work/dest-del/2026-03-01/appdata/gone.txt" ] || { echo "FAIL: same-day re-run must delete files removed from the source"; exit 1; }
[ -f "$work/dest-del/2026-03-01/appdata/keep.txt" ] || { echo "FAIL: same-day re-run must keep files still in the source"; exit 1; }

echo "PASS"
