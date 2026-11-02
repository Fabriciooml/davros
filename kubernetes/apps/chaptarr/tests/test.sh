#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# --- hook script behaviour -------------------------------------------------
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/root" "$work/ingest" "$work/bin" "$work/outside"
printf 'EPUBDATA' > "$work/root/Book One.epub"
printf 'AUDIODATA' > "$work/root/Book One.m4b"
printf 'OUTSIDE' > "$work/outside/Stray.epub"
export INGEST_DIR="$work/ingest" STAGE_DIR="$work/stage" EBOOK_ROOT="$work/root" LOG_FILE="$work/hook.log"

run() { bash ./hardlink-to-cwa.sh; }

# Staging must sit outside the watched ingest folder (CWA watches it recursively),
# both by default and in this test.
defaults=$(env -i PATH="$PATH" bash -c 'eval "$(grep -E "^[A-Z_]+=[$][{]" ./hardlink-to-cwa.sh)"; printf "%s\n%s\n" "$INGEST_DIR" "$STAGE_DIR"')
def_ingest=$(sed -n 1p <<< "$defaults")
def_stage=$(sed -n 2p <<< "$defaults")
case "$def_stage" in "$def_ingest"/*) echo "FAIL: default STAGE_DIR must not be inside INGEST_DIR"; exit 1 ;; esac
case "$STAGE_DIR" in "$INGEST_DIR"/*) echo "FAIL: test STAGE_DIR must not be inside INGEST_DIR"; exit 1 ;; esac

# Test event is a no-op that succeeds.
chaptarr_eventtype=Test run
[ -z "$(ls -A "$work/ingest")" ] || { echo "FAIL: Test event must not link anything"; exit 1; }

# Download event links the ebook (pipe-separated paths) and skips audio.
chaptarr_eventtype=Download chaptarr_addedbookpaths="$work/root/Book One.epub|$work/root/Book One.m4b" run
[ -d "$work/stage" ] || { echo "FAIL: hook must use STAGE_DIR"; exit 1; }
[ "$(stat -c %i "$work/ingest/Book One.epub")" = "$(stat -c %i "$work/root/Book One.epub")" ] || { echo "FAIL: ebook must be hardlinked into ingest (inode must survive the move)"; exit 1; }
[ ! -e "$work/ingest/Book One.m4b" ] || { echo "FAIL: audio files must not reach the ingest folder"; exit 1; }
[ -z "$(ls -A "$work/stage")" ] || { echo "FAIL: STAGE_DIR must be empty after a successful import"; exit 1; }
[ -z "$(find "$work/ingest" -mindepth 1 -name '.*')" ] || { echo "FAIL: no temp/hidden file may appear in ingest"; exit 1; }

# readarr_-prefixed variables are accepted too, and a rerun is a no-op.
rm "$work/ingest/Book One.epub"
readarr_eventtype=Download readarr_addedbookpaths="$work/root/Book One.epub" run
[ -e "$work/ingest/Book One.epub" ] || { echo "FAIL: readarr_ prefixed vars must work"; exit 1; }
readarr_eventtype=Download readarr_addedbookpaths="$work/root/Book One.epub" run

# Fallback to cp when ln fails.
rm "$work/ingest/Book One.epub"
printf '#!/bin/sh\nexit 1\n' > "$work/bin/ln"
chmod +x "$work/bin/ln"
PATH="$work/bin:$PATH" chaptarr_eventtype=Download chaptarr_addedbookpaths="$work/root/Book One.epub" run
[ "$(cat "$work/ingest/Book One.epub")" = "EPUBDATA" ] || { echo "FAIL: cp fallback must copy the file"; exit 1; }
[ "$(stat -c %h "$work/ingest/Book One.epub")" = "1" ] || { echo "FAIL: fallback copy must be a separate inode"; exit 1; }
[ -z "$(find "$work/ingest" -mindepth 1 -name '.*')" ] || { echo "FAIL: no temp file may be left behind in ingest"; exit 1; }
[ -z "$(ls -A "$work/stage")" ] || { echo "FAIL: STAGE_DIR must be empty after the cp fallback"; exit 1; }

# Only files under EBOOK_ROOT are eligible (keeps audiobook booklets out of CWA).
rm "$work/ingest/Book One.epub"
chaptarr_eventtype=Download chaptarr_addedbookpaths="$work/outside/Stray.epub" run
[ ! -e "$work/ingest/Stray.epub" ] || { echo "FAIL: an ebook outside EBOOK_ROOT must not be linked"; exit 1; }

# A failing copy leaves nothing staged, fails the run, and later files still import.
printf 'BROKEN' > "$work/root/Broken.epub"
cp_real=$(command -v cp)
printf '#!/bin/sh\ncase "$*" in *Broken*) exit 1 ;; esac\nexec %s "$@"\n' "$cp_real" > "$work/bin/cp"
chmod +x "$work/bin/cp"
rc=0
PATH="$work/bin:$PATH" chaptarr_eventtype=Download chaptarr_addedbookpaths="$work/root/Broken.epub|$work/root/Book One.epub" run || rc=$?
[ "$rc" -ne 0 ] || { echo "FAIL: a failed file must make the hook exit non-zero"; exit 1; }
[ ! -e "$work/ingest/Broken.epub" ] || { echo "FAIL: failed file must not reach ingest"; exit 1; }
[ -z "$(ls -A "$work/stage")" ] || { echo "FAIL: failed copy must leave nothing in STAGE_DIR"; exit 1; }
[ "$(cat "$work/ingest/Book One.epub")" = "EPUBDATA" ] || { echo "FAIL: files after a failure must still be imported"; exit 1; }

# The env of every call is logged so the real variable names can be checked.
grep -q 'event=Download' "$work/hook.log" || { echo "FAIL: hook must log the event"; exit 1; }

# --- manifests -------------------------------------------------------------
built=$(kustomize build .)

echo "$built" | kubeconform -strict -ignore-missing-schemas -summary

dep=$(echo "$built" | yq e 'select(.kind == "Deployment" and .metadata.name == "chaptarr")' -)
[ -n "$dep" ] || { echo "FAIL: no Deployment chaptarr"; exit 1; }
[ "$(echo "$dep" | yq e '.metadata.namespace' -)" = "arr" ] || { echo "FAIL: must live in arr"; exit 1; }
echo "$dep" | yq e '.spec.template.spec.containers[0].image' - | grep -Eq '^chaptarr/chaptarr:0\.9\.965@sha256:bb00d67cbe1485d1cd61ef178362a29b42aa08f86b290841aab4b115ad2647a6$' || { echo "FAIL: image must be pinned to 0.9.965 with its digest"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.strategy.type' -)" = "Recreate" ] || { echo "FAIL: RWO volume needs Recreate"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.template.spec.enableServiceLinks' -)" = "false" ] || { echo "FAIL: service-link env vars must be off"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.replicas' -)" = "1" ] || { echo "FAIL: replicas must be 1"; exit 1; }
for kv in PUID=1000 PGID=1000 UMASK=002 TZ=America/Sao_Paulo; do
  k=${kv%%=*}
  v=${kv#*=}
  [ "$(echo "$dep" | yq e ".spec.template.spec.containers[0].env[] | select(.name == \"$k\") | .value" -)" = "$v" ] || { echo "FAIL: $k must be $v"; exit 1; }
done
[ "$(echo "$dep" | yq e '.spec.template.spec.containers[0].volumeMounts[] | select(.name == "config") | .mountPath' -)" = "/config" ] || { echo "FAIL: config must mount at /config"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.template.spec.containers[0].volumeMounts[] | select(.name == "data") | .mountPath' -)" = "/data" ] || { echo "FAIL: data must mount at /data"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.template.spec.volumes[] | select(.name == "data") | .hostPath.path' -)" = "/mnt/pool-data" ] || { echo "FAIL: data hostPath must be the whole /mnt/pool-data (hardlinks)"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.template.spec.containers[0].volumeMounts[] | select(.name == "hooks") | .mountPath' -)" = "/scripts" ] || { echo "FAIL: hooks must mount at /scripts"; exit 1; }
echo "$dep" | yq e '.spec.template.spec.volumes[] | select(.name == "hooks") | .configMap.name' - | grep -q '^chaptarr-hooks' || { echo "FAIL: hooks volume must come from the chaptarr-hooks ConfigMap"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.template.spec.volumes[] | select(.name == "hooks") | .configMap.defaultMode' -)" = "493" ] || { echo "FAIL: hook script must be mode 0755 (493)"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.template.spec.containers[0].resources.limits.memory' -)" != "null" ] || { echo "FAIL: memory limit required"; exit 1; }

cm=$(echo "$built" | yq e 'select(.kind == "ConfigMap")' -)
echo "$cm" | grep -q 'hardlink-to-cwa.sh' || { echo "FAIL: ConfigMap must carry hardlink-to-cwa.sh"; exit 1; }

pvc=$(echo "$built" | yq e 'select(.kind == "PersistentVolumeClaim" and .metadata.name == "chaptarr-config")' -)
[ "$(echo "$pvc" | yq e '.spec.storageClassName' -)" = "local-path" ] || { echo "FAIL: config must be on local-path"; exit 1; }

svc=$(echo "$built" | yq e 'select(.kind == "Service" and .metadata.name == "chaptarr")' -)
[ "$(echo "$svc" | yq e '.spec.ports[0].port' -)" = "8789" ] || { echo "FAIL: Service port must be 8789"; exit 1; }

route=$(echo "$built" | yq e 'select(.kind == "IngressRoute" and .metadata.name == "chaptarr")' -)
echo "$route" | grep -qF 'Host(`chaptarr.local.fabriciooml.dev`)' || { echo "FAIL: LAN host chaptarr.local.fabriciooml.dev missing"; exit 1; }
[ "$(echo "$route" | yq e '.spec.routes[0].services[0].port' -)" = "8789" ] || { echo "FAIL: route must target port 8789"; exit 1; }
[ "$(echo "$route" | yq e '.spec.tls | has("secretName")' -)" = "false" ] || { echo "FAIL: route must use the default TLSStore"; exit 1; }

echo "PASS"
