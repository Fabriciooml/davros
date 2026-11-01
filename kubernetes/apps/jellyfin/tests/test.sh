#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

built=$(kustomize build .)

echo "$built" | kubeconform -strict -ignore-missing-schemas -summary

dep=$(echo "$built" | yq e 'select(.kind == "Deployment" and .metadata.name == "jellyfin")' -)
[ -n "$dep" ] || { echo "FAIL: no Deployment jellyfin"; exit 1; }
[ "$(echo "$dep" | yq e '.metadata.namespace' -)" = "jellyfin" ] || { echo "FAIL: must live in jellyfin"; exit 1; }
echo "$dep" | yq e '.spec.template.spec.containers[0].image' - | grep -Eq '^jellyfin/jellyfin:10\.11\.8@sha256:[0-9a-f]{64}$' || { echo "FAIL: image must be pinned to 10.11.8 with a digest"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.strategy.type' -)" = "Recreate" ] || { echo "FAIL: RWO volume needs Recreate"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.template.spec.enableServiceLinks' -)" = "false" ] || { echo "FAIL: service-link env vars must be off"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.replicas' -)" = "0" ] || { echo "FAIL: replicas must be 0 until cutover"; exit 1; }
for kv in JELLYFIN_DATA_DIR=/var/lib/jellyfin JELLYFIN_CONFIG_DIR=/etc/jellyfin JELLYFIN_CACHE_DIR=/var/cache/jellyfin JELLYFIN_LOG_DIR=/var/log/jellyfin; do
  k=${kv%%=*}
  v=${kv#*=}
  [ "$(echo "$dep" | yq e ".spec.template.spec.containers[0].env[] | select(.name == \"$k\") | .value" -)" = "$v" ] || { echo "FAIL: $k must be $v"; exit 1; }
done
[ "$(echo "$dep" | yq e '.spec.template.spec.containers[0].volumeMounts[] | select(.name == "tv") | .mountPath' -)" = "/mnt/tv" ] || { echo "FAIL: tv must mount at /mnt/tv"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.template.spec.containers[0].volumeMounts[] | select(.name == "movies") | .mountPath' -)" = "/mnt/movies" ] || { echo "FAIL: movies must mount at /mnt/movies"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.template.spec.volumes[] | select(.name == "tv") | .hostPath.path' -)" = "/mnt/pool-data/media/tv" ] || { echo "FAIL: tv hostPath must be /mnt/pool-data/media/tv"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.template.spec.volumes[] | select(.name == "movies") | .hostPath.path' -)" = "/mnt/pool-data/media/movies" ] || { echo "FAIL: movies hostPath must be /mnt/pool-data/media/movies"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.template.spec.containers[0].resources.limits.memory' -)" != "null" ] || { echo "FAIL: memory limit required"; exit 1; }

pvc=$(echo "$built" | yq e 'select(.kind == "PersistentVolumeClaim" and .metadata.name == "jellyfin-config")' -)
[ "$(echo "$pvc" | yq e '.spec.storageClassName' -)" = "local-path" ] || { echo "FAIL: config must be on local-path"; exit 1; }

lan=$(echo "$built" | yq e 'select(.kind == "Service" and .metadata.name == "jellyfin-lan")' -)
[ "$(echo "$lan" | yq e '.spec.type' -)" = "LoadBalancer" ] || { echo "FAIL: jellyfin-lan must be a LoadBalancer"; exit 1; }
[ "$(echo "$lan" | yq e '.spec.ports[0].port' -)" = "8096" ] || { echo "FAIL: jellyfin-lan port must be 8096"; exit 1; }

svc=$(echo "$built" | yq e 'select(.kind == "Service" and .metadata.name == "jellyfin")' -)
[ "$(echo "$svc" | yq e '.spec.ports[0].port' -)" = "8096" ] || { echo "FAIL: Service port must be 8096"; exit 1; }

route=$(yq e '.' ingressroute.yaml)
echo "$route" | grep -qF 'Host(`jellyfin.local.fabriciooml.dev`)' || { echo "FAIL: LAN host jellyfin.local.fabriciooml.dev missing"; exit 1; }
[ "$(echo "$route" | yq e '.spec.routes[0].services[0].port' -)" = "8096" ] || { echo "FAIL: route must target port 8096"; exit 1; }
[ "$(echo "$route" | yq e '.spec.tls | has("secretName")' -)" = "false" ] || { echo "FAIL: route must use the default TLSStore"; exit 1; }

echo "PASS"
