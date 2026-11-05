#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

built=$(kustomize build .)

echo "$built" | kubeconform -strict -ignore-missing-schemas -skip Secret -summary

dep=$(echo "$built" | yq e 'select(.kind == "Deployment" and .metadata.name == "homepage")' -)
[ -n "$dep" ] || { echo "FAIL: no Deployment homepage"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.template.spec.enableServiceLinks' -)" = "false" ] || { echo "FAIL: service-link env vars must be off"; exit 1; }
echo "$dep" | yq e '.spec.template.spec.containers[0].image' - | grep -Eq '^ghcr\.io/gethomepage/homepage:v[0-9.]+@sha256:[0-9a-f]{64}$' || { echo "FAIL: image must be pinned by tag and digest"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.template.spec.containers[0].env[] | select(.name == "HOMEPAGE_ALLOWED_HOSTS") | .value' -)" = "home.local.fabriciooml.dev" ] || { echo "FAIL: HOMEPAGE_ALLOWED_HOSTS must be home.local.fabriciooml.dev"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.template.spec.containers[0].resources.limits.memory' -)" != "null" ] || { echo "FAIL: memory limit missing"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.template.spec.containers[0].resources.requests.cpu' -)" != "null" ] || { echo "FAIL: cpu request missing"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.template.spec.containers[0].volumeMounts[] | select(.mountPath == "/app/config/logs") | .name' -)" = "logs" ] || { echo "FAIL: logs emptyDir must be mounted at /app/config/logs"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.template.spec.containers[0].envFrom[] | select(.secretRef.name == "homepage-secrets") | .secretRef.optional' -)" = "true" ] || { echo "FAIL: homepage-secrets must be an optional envFrom"; exit 1; }

[ ! -e configmap.yaml ] || { echo "FAIL: config must be real files under config/ fed to configMapGenerator, not an inline ConfigMap"; exit 1; }
for file in settings.yaml services.yaml widgets.yaml bookmarks.yaml docker.yaml kubernetes.yaml proxmox.yaml custom.css custom.js; do
  [ -f "config/$file" ] || { echo "FAIL: config/$file missing"; exit 1; }
done
cm=$(echo "$built" | yq e 'select(.kind == "ConfigMap" and (.metadata.name | test("^homepage-[a-z0-9]+$")))' -)
[ -n "$cm" ] || { echo "FAIL: generated ConfigMap homepage-<hash> missing"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.template.spec.volumes[] | select(.name == "config") | .configMap.name' -)" = "$(echo "$cm" | yq e '.metadata.name' -)" ] || { echo "FAIL: Deployment must mount the generated ConfigMap"; exit 1; }
for key in settings.yaml services.yaml widgets.yaml bookmarks.yaml docker.yaml kubernetes.yaml proxmox.yaml custom.css custom.js; do
  [ "$(echo "$cm" | yq e ".data | has(\"$key\")" -)" = "true" ] || { echo "FAIL: ConfigMap key $key missing"; exit 1; }
done

svc=$(echo "$built" | yq e 'select(.kind == "Service" and .metadata.name == "homepage")' -)
[ "$(echo "$svc" | yq e '.spec.ports[0].targetPort' -)" = "3000" ] || { echo "FAIL: service must target 3000"; exit 1; }

route=$(echo "$built" | yq e 'select(.kind == "IngressRoute" and .metadata.name == "homepage")' -)
echo "$route" | grep -qF 'Host(`home.local.fabriciooml.dev`)' || { echo "FAIL: LAN host home.local.fabriciooml.dev missing"; exit 1; }
[ "$(echo "$built" | yq e 'select(.kind == "IngressRoute")' - | grep -o 'Host(' | wc -l)" = "1" ] || { echo "FAIL: homepage must serve exactly one LAN host, no public host"; exit 1; }
[ "$(echo "$route" | yq e '.spec.tls | has("secretName")' -)" = "false" ] || { echo "FAIL: route must use the default TLSStore"; exit 1; }

echo "$built" | yq e 'select(.kind == "ServiceAccount" or .kind == "ClusterRole" or .kind == "ClusterRoleBinding")' - | grep -q . && { echo "FAIL: no RBAC in the POC"; exit 1; }

services=$(echo "$cm" | yq e '.data["services.yaml"]' -)
[ "$(echo "$services" | yq e '[.[] | to_entries | .[].value[]] | length' -)" = "26" ] || { echo "FAIL: expected exactly 26 service tiles"; exit 1; }
[ "$(echo "$services" | yq e '[.[] | to_entries | .[].value[] | to_entries | .[].value | select(has("href") | not)] | length' -)" = "0" ] || { echo "FAIL: every tile needs an href"; exit 1; }

# Every LAN href must point at a host some IngressRoute in the repo serves.
repo_root=$(cd ../../.. && pwd)
known=$(grep -rhoE 'Host\(`[^`]+`\)' "$repo_root/kubernetes" --include='*.yaml' | sed -E 's/Host\(`([^`]+)`\)/\1/' | sort -u)
hrefs=$(echo "$services" | yq e '.[] | to_entries | .[].value[] | to_entries | .[].value.href' - | sed -E 's#https://([^/]+).*#\1#' | sort -u)
for h in $hrefs; do
  echo "$known" | grep -qx "$h" || { echo "FAIL: href host $h is not served by any IngressRoute in the repo"; exit 1; }
done

# Widget secrets must be referenced, never inlined; every referenced var must exist in the SOPS file.
refs=$(cat config/*.yaml | grep -oE 'HOMEPAGE_VAR_[A-Z0-9_]+' | sort -u || true)
bad_cred=$(grep -hE '^[[:space:]]*(- )?(key|apikey|password|token|secret|username):' config/*.yaml | grep -vE '^[[:space:]]*(- )?(key|apikey|password|token|secret|username): +"\{\{HOMEPAGE_VAR_[A-Z0-9_]+\}\}"$' || true)
[ -z "$bad_cred" ] || { echo "FAIL: config/ has a credential field that is not a {{HOMEPAGE_VAR_*}} placeholder"; exit 1; }
if [ -n "$refs" ]; then
  [ -f homepage-secrets.sops.yaml ] || { echo "FAIL: config references HOMEPAGE_VAR_* but homepage-secrets.sops.yaml is missing"; exit 1; }
  have=$(yq e '.stringData | keys | .[]' homepage-secrets.sops.yaml | sort -u)
  for r in $refs; do
    echo "$have" | grep -qx "$r" || { echo "FAIL: $r referenced in config but absent from homepage-secrets.sops.yaml"; exit 1; }
  done
  [ "$(echo "$built" | yq e 'select(.kind == "Secret" and .metadata.name == "homepage-secrets") | .stringData | to_entries | .[].value' - | grep -cv '^ENC\[')" = "0" ] || { echo "FAIL: homepage-secrets must be fully SOPS encrypted"; exit 1; }
  echo "$built" | yq e 'select(.kind == "Secret" and .metadata.name == "homepage-secrets") | .metadata.name' - | grep -qx homepage-secrets || { echo "FAIL: homepage-secrets Secret not in the kustomization"; exit 1; }
fi

echo "PASS"
