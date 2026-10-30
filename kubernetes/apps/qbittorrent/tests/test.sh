#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

built=$(kustomize build .)

echo "$built" | kubeconform -strict -ignore-missing-schemas -summary

dep=$(echo "$built" | yq e 'select(.kind == "Deployment" and .metadata.name == "qbittorrent")' -)
[ -n "$dep" ] || { echo "FAIL: no Deployment qbittorrent"; exit 1; }
[ "$(echo "$dep" | yq e '.metadata.namespace' -)" = "arr" ] || { echo "FAIL: must live in arr"; exit 1; }
echo "$dep" | yq e '.spec.template.spec.containers[0].image' - | grep -Eq '^ghcr\.io/hotio/qbittorrent:release-5\.2\.3@sha256:[0-9a-f]{64}$' || { echo "FAIL: image must be pinned to 5.2.3 with a digest"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.strategy.type' -)" = "Recreate" ] || { echo "FAIL: RWO volume needs Recreate"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.template.spec.enableServiceLinks' -)" = "false" ] || { echo "FAIL: service-link env vars must be off"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.progressDeadlineSeconds' -)" = "1200" ] || { echo "FAIL: progressDeadlineSeconds must be 1200"; exit 1; }
for kv in PUID=1000 PGID=1000 UMASK=002 TZ=America/Sao_Paulo; do
  k=${kv%%=*}
  v=${kv#*=}
  [ "$(echo "$dep" | yq e ".spec.template.spec.containers[0].env[] | select(.name == \"$k\") | .value" -)" = "$v" ] || { echo "FAIL: $k must be $v"; exit 1; }
done
[ "$(echo "$dep" | yq e '.spec.template.spec.containers[0].volumeMounts[] | select(.name == "config") | .mountPath' -)" = "/config" ] || { echo "FAIL: config must mount at /config"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.template.spec.containers[0].volumeMounts[] | select(.name == "torrents") | .mountPath' -)" = "/data/torrents" ] || { echo "FAIL: torrents must mount at /data/torrents"; exit 1; }
hp=$(echo "$dep" | yq e '.spec.template.spec.volumes[] | select(.name == "torrents") | .hostPath.path' -)
[ "$hp" = "/mnt/pool-data/torrents" ] || { echo "FAIL: torrents hostPath must be /mnt/pool-data/torrents"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.template.spec.containers[0].resources.limits.memory' -)" != "null" ] || { echo "FAIL: memory limit required"; exit 1; }

pvc=$(echo "$built" | yq e 'select(.kind == "PersistentVolumeClaim" and .metadata.name == "qbittorrent-config")' -)
[ "$(echo "$pvc" | yq e '.spec.storageClassName' -)" = "local-path" ] || { echo "FAIL: config must be on local-path"; exit 1; }

svc=$(echo "$built" | yq e 'select(.kind == "Service" and .metadata.name == "qbittorrent")' -)
[ "$(echo "$svc" | yq e '.spec.ports[0].port' -)" = "4242" ] || { echo "FAIL: Service port must be 4242"; exit 1; }
peer=$(echo "$built" | yq e 'select(.kind == "Service" and .metadata.name == "qbittorrent-peer")' -)
[ "$(echo "$peer" | yq e '.spec.type' -)" = "LoadBalancer" ] || { echo "FAIL: peer Service must be a LoadBalancer"; exit 1; }
[ "$(echo "$peer" | yq e '[.spec.ports[] | select(.port == 6881) | .protocol] | sort | join(",")' -)" = "TCP,UDP" ] || { echo "FAIL: peer Service must expose 6881 tcp and udp"; exit 1; }

[ "$(echo "$dep" | yq e '.spec.replicas' -)" = "1" ] || { echo "FAIL: replicas must be 1 after cutover"; exit 1; }

route=$(echo "$built" | yq e 'select(.kind == "IngressRoute" and .metadata.name == "qbittorrent")' -)
echo "$route" | grep -qF 'Host(`torrent.local.fabriciooml.dev`)' || { echo "FAIL: LAN host torrent.local.fabriciooml.dev missing"; exit 1; }
[ "$(echo "$route" | yq e '.spec.routes[0].services[0].port' -)" = "4242" ] || { echo "FAIL: route must target port 4242"; exit 1; }
[ "$(echo "$route" | yq e '.spec.tls | has("secretName")' -)" = "false" ] || { echo "FAIL: route must use the default TLSStore"; exit 1; }

echo "PASS"
