#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

built=$(kustomize build .)

echo "$built" | kubeconform -strict -ignore-missing-schemas -summary

dep=$(echo "$built" | yq e 'select(.kind == "Deployment" and .metadata.name == "bazarr")' -)
[ -n "$dep" ] || { echo "FAIL: no Deployment bazarr"; exit 1; }
[ "$(echo "$dep" | yq e '.metadata.namespace' -)" = "arr" ] || { echo "FAIL: must live in arr"; exit 1; }
echo "$dep" | yq e '.spec.template.spec.containers[0].image' - | grep -Eq '^ghcr\.io/hotio/bazarr:release-1\.6\.0@sha256:[0-9a-f]{64}$' || { echo "FAIL: image must be pinned to 1.6.0 with a digest"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.strategy.type' -)" = "Recreate" ] || { echo "FAIL: RWO volume needs Recreate"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.template.spec.enableServiceLinks' -)" = "false" ] || { echo "FAIL: service-link env vars must be off"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.progressDeadlineSeconds' -)" = "1200" ] || { echo "FAIL: progressDeadlineSeconds must be 1200"; exit 1; }
for kv in PUID=1000 PGID=1000 UMASK=002 TZ=America/Sao_Paulo; do
  k=${kv%%=*}
  v=${kv#*=}
  [ "$(echo "$dep" | yq e ".spec.template.spec.containers[0].env[] | select(.name == \"$k\") | .value" -)" = "$v" ] || { echo "FAIL: $k must be $v"; exit 1; }
done
[ "$(echo "$dep" | yq e '.spec.template.spec.containers[0].volumeMounts[] | select(.name == "config") | .mountPath' -)" = "/config" ] || { echo "FAIL: config must mount at /config"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.template.spec.containers[0].volumeMounts[] | select(.name == "media") | .mountPath' -)" = "/data/media" ] || { echo "FAIL: media must mount at /data/media"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.template.spec.volumes[] | select(.name == "media") | .hostPath.path' -)" = "/mnt/pool-data/media" ] || { echo "FAIL: media hostPath must be /mnt/pool-data/media"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.template.spec.containers[0].resources.limits.memory' -)" != "null" ] || { echo "FAIL: memory limit required"; exit 1; }

pvc=$(echo "$built" | yq e 'select(.kind == "PersistentVolumeClaim" and .metadata.name == "bazarr-config")' -)
[ "$(echo "$pvc" | yq e '.spec.storageClassName' -)" = "local-path" ] || { echo "FAIL: config must be on local-path"; exit 1; }

svc=$(echo "$built" | yq e 'select(.kind == "Service" and .metadata.name == "bazarr")' -)
[ "$(echo "$svc" | yq e '.spec.ports[0].port' -)" = "6767" ] || { echo "FAIL: Service port must be 6767"; exit 1; }

echo "PASS"
