#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

built=$(kustomize build .)

echo "$built" | kubeconform -strict -ignore-missing-schemas -summary

dep=$(echo "$built" | yq e 'select(.kind == "Deployment" and .metadata.name == "audiobookshelf")' -)
[ -n "$dep" ] || { echo "FAIL: no Deployment audiobookshelf"; exit 1; }
[ "$(echo "$dep" | yq e '.metadata.namespace' -)" = "audiobookshelf" ] || { echo "FAIL: must live in audiobookshelf"; exit 1; }
echo "$dep" | yq e '.spec.template.spec.containers[0].image' - | grep -Eq '^ghcr\.io/advplyr/audiobookshelf:2\.37\.2@sha256:b897c33f05972fb1bf484f7487bc878fa91ec8691335c1db6e2929c3a7658efa$' || { echo "FAIL: image must be pinned to 2.37.2 with its digest"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.strategy.type' -)" = "Recreate" ] || { echo "FAIL: RWO volume needs Recreate"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.template.spec.enableServiceLinks' -)" = "false" ] || { echo "FAIL: service-link env vars must be off"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.replicas' -)" = "1" ] || { echo "FAIL: replicas must be 1"; exit 1; }
for kv in TZ=America/Sao_Paulo AUDIOBOOKSHELF_UID=1000 AUDIOBOOKSHELF_GID=1000; do
  k=${kv%%=*}
  v=${kv#*=}
  [ "$(echo "$dep" | yq e ".spec.template.spec.containers[0].env[] | select(.name == \"$k\") | .value" -)" = "$v" ] || { echo "FAIL: $k must be $v"; exit 1; }
done
for kv in config=/config metadata=/metadata audiobooks=/audiobooks; do
  k=${kv%%=*}
  v=${kv#*=}
  [ "$(echo "$dep" | yq e ".spec.template.spec.containers[0].volumeMounts[] | select(.name == \"$k\") | .mountPath" -)" = "$v" ] || { echo "FAIL: $k must mount at $v"; exit 1; }
done
[ "$(echo "$dep" | yq e '.spec.template.spec.volumes[] | select(.name == "audiobooks") | .hostPath.path' -)" = "/mnt/pool-data/media/audiobooks" ] || { echo "FAIL: audiobooks hostPath must be /mnt/pool-data/media/audiobooks"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.template.spec.volumes | length' -)" = "3" ] || { echo "FAIL: ABS must mount only config, metadata and audiobooks"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.template.spec.containers[0].resources.limits.memory' -)" != "null" ] || { echo "FAIL: memory limit required"; exit 1; }

for pv in audiobookshelf-config audiobookshelf-metadata; do
  pvc=$(echo "$built" | yq e "select(.kind == \"PersistentVolumeClaim\" and .metadata.name == \"$pv\")" -)
  [ "$(echo "$pvc" | yq e '.spec.storageClassName' -)" = "local-path" ] || { echo "FAIL: $pv must be on local-path"; exit 1; }
done

svc=$(echo "$built" | yq e 'select(.kind == "Service" and .metadata.name == "audiobookshelf")' -)
[ "$(echo "$svc" | yq e '.spec.ports[0].port' -)" = "80" ] || { echo "FAIL: Service port must be 80"; exit 1; }

route=$(echo "$built" | yq e 'select(.kind == "IngressRoute" and .metadata.name == "audiobookshelf")' -)
echo "$route" | grep -qF 'Host(`audiobookshelf.local.fabriciooml.dev`)' || { echo "FAIL: LAN host audiobookshelf.local.fabriciooml.dev missing"; exit 1; }
echo "$route" | grep -qF 'Host(`audiobooks.fabriciooml.dev`)' || { echo "FAIL: public host audiobooks.fabriciooml.dev missing"; exit 1; }
[ "$(echo "$route" | yq e '.spec.routes[0].services[0].port' -)" = "80" ] || { echo "FAIL: route must target port 80"; exit 1; }
[ "$(echo "$route" | yq e '.spec.tls | has("secretName")' -)" = "false" ] || { echo "FAIL: route must use the default TLSStore"; exit 1; }

echo "PASS"
