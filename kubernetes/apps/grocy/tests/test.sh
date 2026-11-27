#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

built=$(kustomize build .)

echo "$built" | kubeconform -strict -ignore-missing-schemas -summary

dep=$(echo "$built" | yq e 'select(.kind == "Deployment" and .metadata.name == "grocy")' -)
[ -n "$dep" ] || { echo "FAIL: no Deployment grocy"; exit 1; }
echo "$dep" | yq e '.spec.template.spec.containers[0].image' - | grep -Eq '^lscr\.io/linuxserver/grocy:v[0-9.]+-ls[0-9]+@sha256:[0-9a-f]{64}$' || { echo "FAIL: image must be pinned by tag and digest"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.strategy.type' -)" = "Recreate" ] || { echo "FAIL: RWO volume needs Recreate"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.template.spec.enableServiceLinks' -)" = "false" ] || { echo "FAIL: service-link env vars must be off"; exit 1; }
for kv in PUID=1000 PGID=1000 TZ=America/Sao_Paulo; do
  k=${kv%%=*}
  v=${kv#*=}
  [ "$(echo "$dep" | yq e ".spec.template.spec.containers[0].env[] | select(.name == \"$k\") | .value" -)" = "$v" ] || { echo "FAIL: $k must be $v"; exit 1; }
done
[ "$(echo "$dep" | yq e '.spec.template.spec.containers[0].volumeMounts[0].mountPath' -)" = "/config" ] || { echo "FAIL: data must mount at /config"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.template.spec.containers[0].resources.limits.memory' -)" != "null" ] || { echo "FAIL: memory limit missing"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.template.spec.containers[0].resources.requests.memory' -)" != "null" ] || { echo "FAIL: memory request missing"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.template.spec.containers[0].resources.requests.cpu' -)" != "null" ] || { echo "FAIL: cpu request missing"; exit 1; }

pvc=$(echo "$built" | yq e 'select(.kind == "PersistentVolumeClaim" and .metadata.name == "grocy-config")' -)
[ "$(echo "$pvc" | yq e '.spec.storageClassName' -)" = "local-path" ] || { echo "FAIL: config must be on local-path"; exit 1; }

svc=$(echo "$built" | yq e 'select(.kind == "Service" and .metadata.name == "grocy")' -)
[ "$(echo "$svc" | yq e '.spec.ports[0].port' -)" = "80" ] || { echo "FAIL: service must expose port 80"; exit 1; }
[ "$(echo "$svc" | yq e '.spec.ports[0].targetPort' -)" = "80" ] || { echo "FAIL: service must target 80"; exit 1; }

route=$(echo "$built" | yq e 'select(.kind == "IngressRoute" and .metadata.name == "grocy")' -)
echo "$route" | grep -qF 'Host(`grocy.local.fabriciooml.dev`)' || { echo "FAIL: LAN host grocy.local.fabriciooml.dev missing"; exit 1; }
[ "$(echo "$route" | grep -o 'Host(' | wc -l)" = "1" ] || { echo "FAIL: grocy must serve exactly one LAN host, no public host"; exit 1; }
[ "$(echo "$route" | yq e '.spec.tls | has("secretName")' -)" = "false" ] || { echo "FAIL: route must use the default TLSStore"; exit 1; }

echo "PASS"
