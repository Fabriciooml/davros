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
[ "$(echo "$services" | yq e '[.[] | to_entries | .[].value[] | to_entries | .[].value | select(has("href"))] | length' -)" = "26" ] || { echo "FAIL: expected exactly 26 link tiles (tiles with an href)"; exit 1; }
nohref=$(echo "$services" | yq e '.[] | to_entries | .[].value[] | to_entries | .[].value | select(has("href") | not) | .widget.type' -)
[ -z "$nohref" ] || [ "$(echo "$nohref" | sort -u)" = "calendar" ] || { echo "FAIL: a tile without href must be a calendar widget"; exit 1; }

# Every LAN href must point at a host some IngressRoute in the repo serves.
repo_root=$(cd ../../.. && pwd)
known=$(grep -rhoE 'Host\(`[^`]+`\)' "$repo_root/kubernetes" --include='*.yaml' | sed -E 's/Host\(`([^`]+)`\)/\1/' | sort -u)
hrefs=$(echo "$services" | yq e '.[] | to_entries | .[].value[] | to_entries | .[].value | select(has("href")) | .href' - | sed -E 's#https://([^/]+).*#\1#' | sort -u)
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

# Bookmarks: three groups, seven https links.
bm=$(echo "$cm" | yq e '.data["bookmarks.yaml"]' -)
[ "$(echo "$bm" | yq e '[.[] | keys | .[]] | join(",")' -)" = "Dev,Cloud,Docs" ] || { echo "FAIL: bookmarks must have groups Dev, Cloud, Docs in that order"; exit 1; }
[ "$(echo "$bm" | yq e '[.[] | to_entries | .[].value[] | to_entries | .[].value[].href] | length' -)" = "7" ] || { echo "FAIL: expected exactly 7 bookmarks"; exit 1; }
bad_bm=$(echo "$bm" | yq e '.[] | to_entries | .[].value[] | to_entries | .[].value[].href' - | grep -vE '^https://' || true)
[ -z "$bad_bm" ] || { echo "FAIL: every bookmark href must be https://"; exit 1; }

# Weather: Open-Meteo for Belo Horizonte, metric.
widgets=$(echo "$cm" | yq e '.data["widgets.yaml"]' -)
wx='.[] | select(has("openmeteo")) | .openmeteo'
[ "$(echo "$widgets" | yq e "$wx | .latitude" -)" = "-19.92" ] || { echo "FAIL: openmeteo latitude must be -19.92"; exit 1; }
[ "$(echo "$widgets" | yq e "$wx | .longitude" -)" = "-43.94" ] || { echo "FAIL: openmeteo longitude must be -43.94"; exit 1; }
[ "$(echo "$widgets" | yq e "$wx | .timezone" -)" = "America/Sao_Paulo" ] || { echo "FAIL: openmeteo timezone must be America/Sao_Paulo"; exit 1; }
[ "$(echo "$widgets" | yq e "$wx | .units" -)" = "metric" ] || { echo "FAIL: openmeteo units must be metric"; exit 1; }

# Calendar: one calendar tile whose integrations point at tiles that exist.
cal=$(echo "$services" | yq e '.[] | to_entries | .[].value[] | to_entries | .[].value | select(.widget.type == "calendar")' -)
[ -n "$cal" ] || { echo "FAIL: calendar tile missing"; exit 1; }
[ "$(echo "$cal" | yq e '.widget.integrations | length' -)" -ge 1 ] || { echo "FAIL: calendar needs at least one integration"; exit 1; }
echo "$cal" | yq e -o=json -I=0 '.widget.integrations[]' - | while IFS= read -r integ; do
  g=$(echo "$integ" | yq e '.service_group' -)
  n=$(echo "$integ" | yq e '.service_name' -)
  [ "$(echo "$services" | G="$g" N="$n" yq e '[.[] | select(has(strenv(G))) | .[strenv(G)][] | has(strenv(N))] | any' -)" = "true" ] || { echo "FAIL: calendar integration $g / $n matches no tile"; exit 1; }
done

# Layout: every layout group has tiles, and every tile group is in the layout.
settings=$(echo "$cm" | yq e '.data["settings.yaml"]' -)
groups=$(echo "$services" | yq e '.[] | keys | .[]' - | sort -u)
echo "$settings" | yq e '.layout | keys | .[]' - | while IFS= read -r g; do
  echo "$groups" | grep -qxF "$g" || { echo "FAIL: settings layout group '$g' has no tiles"; exit 1; }
done
echo "$groups" | while IFS= read -r g; do
  [ "$(echo "$settings" | G="$g" yq e '.layout | has(strenv(G))' -)" = "true" ] || { echo "FAIL: group '$g' is missing from settings layout"; exit 1; }
done

echo "PASS"
