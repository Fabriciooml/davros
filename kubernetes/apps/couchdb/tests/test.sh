#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

built=$(kustomize build .)

echo "$built" | kubeconform -strict -ignore-missing-schemas -summary

dep=$(echo "$built" | yq e 'select(.kind == "Deployment" and .metadata.name == "couchdb")' -)
[ -n "$dep" ] || { echo "FAIL: no Deployment couchdb"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.template.spec.containers[0].image' -)" = "couchdb:3.5.1@sha256:297cd556c7ba358a408fd009e7b8e3b91318ccfc4d57c9b0264a2fb051ad9ef7" ] || { echo "FAIL: image must stay pinned to the 3.5.1 digest"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.strategy.type' -)" = "Recreate" ] || { echo "FAIL: RWO volume needs Recreate"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.template.spec.enableServiceLinks' -)" = "false" ] || { echo "FAIL: service-link env vars must be off"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.progressDeadlineSeconds' -)" = "1200" ] || { echo "FAIL: progressDeadlineSeconds must be 1200"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.template.spec.securityContext.runAsUser' -)" = "5984" ] || { echo "FAIL: must run as uid 5984"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.template.spec.containers[0].volumeMounts[] | select(.mountPath == "/opt/couchdb/data") | .name' -)" = "data" ] || { echo "FAIL: data must mount at /opt/couchdb/data"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.template.spec.containers[0].volumeMounts[] | select(.mountPath == "/opt/couchdb/etc/local.d") | .name' -)" = "etc" ] || { echo "FAIL: etc must mount at /opt/couchdb/etc/local.d"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.template.spec.volumes[] | select(.name == "data") | .persistentVolumeClaim.claimName' -)" = "couchdb-data" ] || { echo "FAIL: data volume must use PVC couchdb-data"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.template.spec.volumes[] | select(.name == "etc") | .persistentVolumeClaim.claimName' -)" = "couchdb-etc" ] || { echo "FAIL: etc volume must use PVC couchdb-etc"; exit 1; }
for p in readinessProbe livenessProbe; do
  [ "$(echo "$dep" | yq e ".spec.template.spec.containers[0].$p.tcpSocket.port" -)" = "5984" ] || { echo "FAIL: $p must be a tcpSocket on 5984 (every http path answers 401)"; exit 1; }
  [ "$(echo "$dep" | yq e ".spec.template.spec.containers[0].$p | has(\"httpGet\")" -)" = "false" ] || { echo "FAIL: $p must not use httpGet"; exit 1; }
done
[ -z "$(echo "$dep" | yq e '.spec.template.spec.containers[0].env[] | select(.name == "COUCHDB_USER" or .name == "COUCHDB_PASSWORD")' -)" ] || { echo "FAIL: credentials come from the imported local.d, not env"; exit 1; }

for n in couchdb-data couchdb-etc; do
  pvc=$(echo "$built" | yq e "select(.kind == \"PersistentVolumeClaim\" and .metadata.name == \"$n\")" -)
  [ "$(echo "$pvc" | yq e '.spec.storageClassName' -)" = "local-path" ] || { echo "FAIL: $n must be on local-path"; exit 1; }
done

svc=$(echo "$built" | yq e 'select(.kind == "Service" and .metadata.name == "couchdb")' -)
[ "$(echo "$svc" | yq e '.spec.ports[0].port' -)" = "5984" ] || { echo "FAIL: Service couchdb must expose 5984"; exit 1; }
lan=$(echo "$built" | yq e 'select(.kind == "Service" and .metadata.name == "couchdb-lan")' -)
[ "$(echo "$lan" | yq e '.spec.type' -)" = "LoadBalancer" ] || { echo "FAIL: couchdb-lan must be a LoadBalancer"; exit 1; }
[ "$(echo "$lan" | yq e '.spec.ports[0].port' -)" = "5984" ] || { echo "FAIL: couchdb-lan must expose 5984"; exit 1; }

route=$(echo "$built" | yq e 'select(.kind == "IngressRoute" and .metadata.name == "couchdb")' -)
echo "$route" | grep -qF 'Host(`obsidian.local.fabriciooml.dev`)' || { echo "FAIL: LAN host obsidian.local.fabriciooml.dev missing"; exit 1; }
[ "$(echo "$route" | yq e '.spec.tls | has("secretName")' -)" = "false" ] || { echo "FAIL: route must use the default TLSStore"; exit 1; }

echo "PASS"
