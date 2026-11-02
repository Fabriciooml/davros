#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

built=$(kustomize build .)

echo "$built" | kubeconform -strict -ignore-missing-schemas -summary

dep=$(echo "$built" | yq e 'select(.kind == "Deployment" and .metadata.name == "cwa")' -)
[ -n "$dep" ] || { echo "FAIL: no Deployment cwa"; exit 1; }
[ "$(echo "$dep" | yq e '.metadata.namespace' -)" = "cwa" ] || { echo "FAIL: must live in cwa"; exit 1; }
echo "$dep" | yq e '.spec.template.spec.containers[0].image' - | grep -Eq '^crocodilestick/calibre-web-automated:v4\.0\.8@sha256:5e00373854247750cc3e4479b492ae09293ff5e06ed10177f226634d97888679$' || { echo "FAIL: image must be pinned to v4.0.8 with its digest"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.strategy.type' -)" = "Recreate" ] || { echo "FAIL: RWO volume needs Recreate"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.template.spec.enableServiceLinks' -)" = "false" ] || { echo "FAIL: service-link env vars must be off"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.replicas' -)" = "1" ] || { echo "FAIL: replicas must be 1"; exit 1; }
for kv in PUID=1000 PGID=1000 TZ=America/Sao_Paulo NETWORK_SHARE_MODE=false; do
  k=${kv%%=*}
  v=${kv#*=}
  [ "$(echo "$dep" | yq e ".spec.template.spec.containers[0].env[] | select(.name == \"$k\") | .value" -)" = "$v" ] || { echo "FAIL: $k must be $v"; exit 1; }
done
for kv in config=/config library=/calibre-library ingest=/cwa-book-ingest; do
  k=${kv%%=*}
  v=${kv#*=}
  [ "$(echo "$dep" | yq e ".spec.template.spec.containers[0].volumeMounts[] | select(.name == \"$k\") | .mountPath" -)" = "$v" ] || { echo "FAIL: $k must mount at $v"; exit 1; }
done
[ "$(echo "$dep" | yq e '.spec.template.spec.volumes[] | select(.name == "library") | .hostPath.path' -)" = "/mnt/pool-data/media/books" ] || { echo "FAIL: library hostPath must be /mnt/pool-data/media/books"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.template.spec.volumes[] | select(.name == "ingest") | .hostPath.path' -)" = "/mnt/pool-data/media/books-ingest" ] || { echo "FAIL: ingest hostPath must be /mnt/pool-data/media/books-ingest"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.template.spec.volumes | length' -)" = "3" ] || { echo "FAIL: CWA must mount only config, library and ingest"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.template.spec.containers[0].resources.limits.memory' -)" != "null" ] || { echo "FAIL: memory limit required (SQLite config stays on local-path, not NFS)"; exit 1; }

pvc=$(echo "$built" | yq e 'select(.kind == "PersistentVolumeClaim" and .metadata.name == "cwa-config")' -)
[ "$(echo "$pvc" | yq e '.spec.storageClassName' -)" = "local-path" ] || { echo "FAIL: config must be on local-path"; exit 1; }

svc=$(echo "$built" | yq e 'select(.kind == "Service" and .metadata.name == "cwa")' -)
[ "$(echo "$svc" | yq e '.spec.ports[0].port' -)" = "8083" ] || { echo "FAIL: Service port must be 8083"; exit 1; }

route=$(echo "$built" | yq e 'select(.kind == "IngressRoute" and .metadata.name == "cwa")' -)
echo "$route" | grep -qF 'Host(`cwa.local.fabriciooml.dev`)' || { echo "FAIL: LAN host cwa.local.fabriciooml.dev missing"; exit 1; }
echo "$route" | grep -qF 'Host(`books.fabriciooml.dev`)' || { echo "FAIL: public host books.fabriciooml.dev missing"; exit 1; }
[ "$(echo "$route" | yq e '.spec.routes[0].services[0].port' -)" = "8083" ] || { echo "FAIL: route must target port 8083"; exit 1; }
[ "$(echo "$route" | yq e '.spec.tls | has("secretName")' -)" = "false" ] || { echo "FAIL: route must use the default TLSStore"; exit 1; }

echo "PASS"
