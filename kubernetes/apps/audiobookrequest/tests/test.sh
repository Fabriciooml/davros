#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

built=$(kustomize build .)

echo "$built" | kubeconform -strict -ignore-missing-schemas -summary

dep=$(echo "$built" | yq e 'select(.kind == "Deployment" and .metadata.name == "audiobookrequest")' -)
[ -n "$dep" ] || { echo "FAIL: no Deployment audiobookrequest"; exit 1; }
[ "$(echo "$dep" | yq e '.metadata.namespace' -)" = "arr" ] || { echo "FAIL: must live in arr"; exit 1; }
echo "$dep" | yq e '.spec.template.spec.containers[0].image' - | grep -Eq '^markbeep/audiobookrequest:1\.11\.0@sha256:628080b8bc71d057927ec26109eb3135f5ce6678a541077cb5b8d13fbe9fca43$' || { echo "FAIL: image must be pinned to 1.11.0 with its digest"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.strategy.type' -)" = "Recreate" ] || { echo "FAIL: RWO volume needs Recreate"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.template.spec.enableServiceLinks' -)" = "false" ] || { echo "FAIL: service-link env vars must be off"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.replicas' -)" = "1" ] || { echo "FAIL: replicas must be 1"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.template.spec.containers[0].env[] | select(.name == "TZ") | .value' -)" = "America/Sao_Paulo" ] || { echo "FAIL: TZ must be America/Sao_Paulo"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.template.spec.containers[0].volumeMounts[] | select(.name == "config") | .mountPath' -)" = "/config" ] || { echo "FAIL: config must mount at /config"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.template.spec.volumes | length' -)" = "1" ] || { echo "FAIL: ABR must mount only its config volume (no media access)"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.template.spec.containers[0].resources.limits.memory' -)" != "null" ] || { echo "FAIL: memory limit required"; exit 1; }

pvc=$(echo "$built" | yq e 'select(.kind == "PersistentVolumeClaim" and .metadata.name == "audiobookrequest-config")' -)
[ "$(echo "$pvc" | yq e '.spec.storageClassName' -)" = "local-path" ] || { echo "FAIL: config must be on local-path"; exit 1; }

svc=$(echo "$built" | yq e 'select(.kind == "Service" and .metadata.name == "audiobookrequest")' -)
[ "$(echo "$svc" | yq e '.spec.ports[0].port' -)" = "8000" ] || { echo "FAIL: Service port must be 8000"; exit 1; }

route=$(echo "$built" | yq e 'select(.kind == "IngressRoute" and .metadata.name == "audiobookrequest")' -)
echo "$route" | grep -qF 'Host(`audiobookrequest.local.fabriciooml.dev`)' || { echo "FAIL: LAN host audiobookrequest.local.fabriciooml.dev missing"; exit 1; }
[ "$(echo "$route" | yq e '.spec.routes[0].services[0].port' -)" = "8000" ] || { echo "FAIL: route must target port 8000"; exit 1; }
[ "$(echo "$route" | yq e '.spec.tls | has("secretName")' -)" = "false" ] || { echo "FAIL: route must use the default TLSStore"; exit 1; }

echo "PASS"
