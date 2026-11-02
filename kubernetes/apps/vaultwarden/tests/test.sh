#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

built=$(kustomize build .)

echo "$built" | kubeconform -strict -ignore-missing-schemas -summary

dep=$(echo "$built" | yq e 'select(.kind == "Deployment" and .metadata.name == "vaultwarden")' -)
[ -n "$dep" ] || { echo "FAIL: no Deployment vaultwarden"; exit 1; }
[ "$(echo "$dep" | yq e '.metadata.namespace' -)" = "vaultwarden" ] || { echo "FAIL: must live in vaultwarden"; exit 1; }
echo "$dep" | yq e '.spec.template.spec.containers[0].image' - | grep -Eq '^vaultwarden/server:1\.37\.4@sha256:[0-9a-f]{64}$' || { echo "FAIL: image must be pinned to 1.37.4 with a digest"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.strategy.type' -)" = "Recreate" ] || { echo "FAIL: RWO volume needs Recreate"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.template.spec.enableServiceLinks' -)" = "false" ] || { echo "FAIL: service-link env vars must be off"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.replicas' -)" = "1" ] || { echo "FAIL: replicas must be 1 after cutover"; exit 1; }
for kv in DOMAIN=https://vault.fabriciooml.dev ROCKET_PORT=8080 WEB_VAULT_ENABLED=true DATA_FOLDER=/data; do
  k=${kv%%=*}
  v=${kv#*=}
  [ "$(echo "$dep" | yq e ".spec.template.spec.containers[0].env[] | select(.name == \"$k\") | .value" -)" = "$v" ] || { echo "FAIL: $k must be $v"; exit 1; }
done
[ -z "$(echo "$dep" | yq e '.spec.template.spec.containers[0].env[] | select(.name == "ADMIN_TOKEN")' -)" ] || { echo "FAIL: ADMIN_TOKEN must not be set (admin page disabled)"; exit 1; }
echo "$dep" | grep -q ROCKET_TLS && { echo "FAIL: TLS terminates at Traefik, ROCKET_TLS must not be set"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.template.spec.containers[0].volumeMounts[0].mountPath' -)" = "/data" ] || { echo "FAIL: data must mount at /data"; exit 1; }

[ -z "$(echo "$built" | yq e 'select(.kind == "Secret")' -)" ] || { echo "FAIL: no Secret expected"; exit 1; }

pvc=$(echo "$built" | yq e 'select(.kind == "PersistentVolumeClaim" and .metadata.name == "vaultwarden-data")' -)
[ "$(echo "$pvc" | yq e '.spec.storageClassName' -)" = "local-path" ] || { echo "FAIL: data must be on local-path"; exit 1; }

svc=$(echo "$built" | yq e 'select(.kind == "Service" and .metadata.name == "vaultwarden")' -)
[ "$(echo "$svc" | yq e '.spec.ports[0].port' -)" = "8080" ] || { echo "FAIL: Service port must be 8080"; exit 1; }

route=$(echo "$built" | yq e 'select(.kind == "IngressRoute" and .metadata.name == "vaultwarden")' -)
echo "$route" | grep -qF 'Host(`vault.local.fabriciooml.dev`)' || { echo "FAIL: LAN host missing"; exit 1; }
echo "$route" | grep -qF 'Host(`vault.fabriciooml.dev`)' || { echo "FAIL: public host missing"; exit 1; }
[ "$(echo "$route" | yq e '.spec.routes[0].services[0].port' -)" = "8080" ] || { echo "FAIL: route must target port 8080"; exit 1; }
[ "$(echo "$route" | yq e '.spec.tls | has("secretName")' -)" = "false" ] || { echo "FAIL: route must use the default TLSStore"; exit 1; }

echo "PASS"
