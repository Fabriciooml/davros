#!/usr/bin/env bash
# Chaptarr Connect custom script: hardlink newly imported ebooks into the CWA ingest folder.
# Files are staged outside the watched ingest folder and then renamed into it, so CWA sees
# a close_write/moved_to event only once the file is complete. Hardlink is atomic and free;
# falls back to copy when ln fails. STAGE_DIR must be on the same dataset as the sources.
set -euo pipefail

INGEST_DIR=${INGEST_DIR:-/data/media/books-ingest}
STAGE_DIR=${STAGE_DIR:-/data/media/.books-ingest-staging}
EBOOK_ROOT=${EBOOK_ROOT:-/data/media/books-chaptarr}
LOG_FILE=${LOG_FILE:-/config/hardlink-to-cwa.log}
EXTENSIONS=${EXTENSIONS:-epub mobi azw3 azw kepub pdf fb2 cbz djvu}

log() { printf '%s %s\n' "$(date -u +%FT%TZ)" "$*" >> "$LOG_FILE" 2>/dev/null || true; }

event=${chaptarr_eventtype:-${readarr_eventtype:-}}
log "event=${event:-unset}"
log "env: $(env | grep -iE '^(chaptarr|readarr)_' | sort | tr '\n' ' ')"

[ "$event" = "Download" ] || exit 0

paths=${chaptarr_addedbookpaths:-${readarr_addedbookpaths:-${chaptarr_bookfile_path:-${readarr_bookfile_path:-}}}}
[ -n "$paths" ] || { log "no book paths in env"; exit 0; }

mkdir -p "$STAGE_DIR"
failed=0
IFS='|' read -r -a files <<< "$paths"
for src in "${files[@]}"; do
  [ -f "$src" ] || { log "skip (missing): $src"; continue; }
  case "$src" in "$EBOOK_ROOT"/*) ;; *) log "skip (outside ebook root): $src"; continue ;; esac
  name=$(basename "$src")
  ext=$(printf '%s' "${name##*.}" | tr '[:upper:]' '[:lower:]')
  case " $EXTENSIONS " in *" $ext "*) ;; *) log "skip (not an ebook): $src"; continue ;; esac
  dest="$INGEST_DIR/$name"
  [ -e "$dest" ] && { log "skip (exists): $dest"; continue; }
  stage="$STAGE_DIR/$name"
  if ln "$src" "$stage" 2>/dev/null; then
    how="linked"
  elif cp -p "$src" "$stage" 2>/dev/null; then
    how="copied (ln failed)"
  else
    rm -f "$stage"
    log "FAILED (stage): $src"
    failed=1
    continue
  fi
  if mv "$stage" "$dest"; then
    log "$how: $src -> $dest"
  else
    rm -f "$stage"
    log "FAILED (move): $src -> $dest"
    failed=1
  fi
done
exit "$failed"
