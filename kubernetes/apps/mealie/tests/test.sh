#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

built=$(kustomize build .)

echo "$built" | kubeconform -strict -ignore-missing-schemas -summary

dep=$(echo "$built" | yq e 'select(.kind == "Deployment" and .metadata.name == "mealie")' -)
[ -n "$dep" ] || { echo "FAIL: no Deployment mealie"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.template.spec.containers[0].image' -)" = "ghcr.io/mealie-recipes/mealie:v3.16.0@sha256:74496aed2c5055e3b7b6c4e1bb9b4f16b1f566601582b258a10bae851f19ac24" ] || { echo "FAIL: image must stay pinned to the v3.16.0 digest"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.strategy.type' -)" = "Recreate" ] || { echo "FAIL: RWO volume needs Recreate"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.template.spec.enableServiceLinks' -)" = "false" ] || { echo "FAIL: service-link env vars must be off"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.progressDeadlineSeconds' -)" = "1200" ] || { echo "FAIL: progressDeadlineSeconds must be 1200"; exit 1; }
for kv in BASE_URL=https://mealie.fabriciooml.dev ALLOW_SIGNUP=false PUID=1000 PGID=1000; do
  k=${kv%%=*}
  v=${kv#*=}
  [ "$(echo "$dep" | yq e ".spec.template.spec.containers[0].env[] | select(.name == \"$k\") | .value" -)" = "$v" ] || { echo "FAIL: $k must be $v"; exit 1; }
done
[ "$(echo "$dep" | yq e '.spec.template.spec.containers[0].volumeMounts[0].mountPath' -)" = "/app/data" ] || { echo "FAIL: data must mount at /app/data"; exit 1; }

pvc=$(echo "$built" | yq e 'select(.kind == "PersistentVolumeClaim" and .metadata.name == "mealie-data")' -)
[ "$(echo "$pvc" | yq e '.spec.storageClassName' -)" = "local-path" ] || { echo "FAIL: data must be on local-path"; exit 1; }

route=$(echo "$built" | yq e 'select(.kind == "IngressRoute" and .metadata.name == "mealie")' -)
echo "$route" | grep -qF 'Host(`mealie.local.fabriciooml.dev`)' || { echo "FAIL: LAN host mealie.local.fabriciooml.dev missing"; exit 1; }
echo "$route" | grep -qF 'Host(`mealie.fabriciooml.dev`)' || { echo "FAIL: public host mealie.fabriciooml.dev missing"; exit 1; }
[ "$(echo "$route" | yq e '.spec.tls | has("secretName")' -)" = "false" ] || { echo "FAIL: route must use the default TLSStore"; exit 1; }

echo "PASS"
