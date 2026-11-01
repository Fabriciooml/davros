#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

built=$(kustomize build .)

echo "$built" | kubeconform -strict -ignore-missing-schemas -summary

dep=$(echo "$built" | yq e 'select(.kind == "Deployment" and .metadata.name == "plex")' -)
[ -n "$dep" ] || { echo "FAIL: no Deployment plex"; exit 1; }
[ "$(echo "$dep" | yq e '.metadata.namespace' -)" = "plex" ] || { echo "FAIL: must live in plex"; exit 1; }
echo "$dep" | yq e '.spec.template.spec.containers[0].image' - | grep -Eq '^plexinc/pms-docker:1\.43\.0\.10492-121068a07@sha256:[0-9a-f]{64}$' || { echo "FAIL: image must be pinned to 1.43.0.10492-121068a07 with a digest"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.strategy.type' -)" = "Recreate" ] || { echo "FAIL: RWO volume needs Recreate"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.template.spec.enableServiceLinks' -)" = "false" ] || { echo "FAIL: service-link env vars must be off"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.replicas' -)" = "0" ] || { echo "FAIL: replicas must be 0 until cutover"; exit 1; }
for kv in PLEX_UID=1000 PLEX_GID=1000 TZ=America/Sao_Paulo ADVERTISE_IP=http://192.168.31.240:32400/; do
  k=${kv%%=*}
  v=${kv#*=}
  [ "$(echo "$dep" | yq e ".spec.template.spec.containers[0].env[] | select(.name == \"$k\") | .value" -)" = "$v" ] || { echo "FAIL: $k must be $v"; exit 1; }
done
[ -z "$(echo "$dep" | yq e '.spec.template.spec.containers[0].env[] | select(.name == "PLEX_CLAIM")' -)" ] || { echo "FAIL: PLEX_CLAIM must not be set"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.template.spec.volumes[] | select(.name == "config") | .persistentVolumeClaim.claimName' -)" = "plex-config" ] || { echo "FAIL: config must come from PVC plex-config"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.template.spec.containers[0].volumeMounts[] | select(.name == "config") | .mountPath' -)" = "/config" ] || { echo "FAIL: config must mount at /config"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.template.spec.containers[0].volumeMounts[] | select(.name == "transcode") | .mountPath' -)" = "/transcode" ] || { echo "FAIL: transcode must mount at /transcode"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.template.spec.volumes[] | select(.name == "transcode") | has("emptyDir")' -)" = "true" ] || { echo "FAIL: transcode must be an emptyDir"; exit 1; }
for m in tv movies; do
  [ "$(echo "$dep" | yq e ".spec.template.spec.containers[0].volumeMounts[] | select(.name == \"$m\") | .mountPath" -)" = "/mnt/$m" ] || { echo "FAIL: $m must mount at /mnt/$m"; exit 1; }
  [ "$(echo "$dep" | yq e ".spec.template.spec.containers[0].volumeMounts[] | select(.name == \"$m\") | .readOnly" -)" = "true" ] || { echo "FAIL: $m must be read-only"; exit 1; }
  [ "$(echo "$dep" | yq e ".spec.template.spec.volumes[] | select(.name == \"$m\") | .hostPath.path" -)" = "/mnt/pool-data/media/$m" ] || { echo "FAIL: $m hostPath must be /mnt/pool-data/media/$m"; exit 1; }
done
[ "$(echo "$dep" | yq e '.spec.template.spec.containers[0].resources.limits.memory' -)" != "null" ] || { echo "FAIL: memory limit required"; exit 1; }

pvc=$(echo "$built" | yq e 'select(.kind == "PersistentVolumeClaim" and .metadata.name == "plex-config")' -)
[ "$(echo "$pvc" | yq e '.spec.storageClassName' -)" = "local-path" ] || { echo "FAIL: config must be on local-path"; exit 1; }

lan=$(echo "$built" | yq e 'select(.kind == "Service" and .metadata.name == "plex-lan")' -)
[ "$(echo "$lan" | yq e '.spec.type' -)" = "LoadBalancer" ] || { echo "FAIL: plex-lan must be a LoadBalancer"; exit 1; }
[ "$(echo "$lan" | yq e '.spec.ports[0].port' -)" = "32400" ] || { echo "FAIL: plex-lan port must be 32400"; exit 1; }

svc=$(echo "$built" | yq e 'select(.kind == "Service" and .metadata.name == "plex")' -)
[ "$(echo "$svc" | yq e '.spec.ports[0].port' -)" = "32400" ] || { echo "FAIL: Service port must be 32400"; exit 1; }

route=$(yq e '.' ingressroute.yaml)
echo "$route" | grep -qF 'Host(`plex.local.fabriciooml.dev`)' || { echo "FAIL: LAN host plex.local.fabriciooml.dev missing"; exit 1; }
[ "$(echo "$route" | yq e '.spec.routes[0].services[0].port' -)" = "32400" ] || { echo "FAIL: route must target port 32400"; exit 1; }
[ "$(echo "$route" | yq e '.spec.tls | has("secretName")' -)" = "false" ] || { echo "FAIL: route must use the default TLSStore"; exit 1; }

echo "PASS"
