#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

built=$(kustomize build .)

echo "$built" | kubeconform -strict -ignore-missing-schemas -summary

dep=$(echo "$built" | yq e 'select(.kind == "Deployment" and .metadata.name == "wiki")' -)
[ -n "$dep" ] || { echo "FAIL: no Deployment wiki"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.template.spec.enableServiceLinks' -)" = "false" ] || { echo "FAIL: service-link env vars must be off"; exit 1; }
echo "$dep" | yq e '.spec.template.spec.containers[] | select(.name == "nginx") | .image' - | grep -Eq '^nginxinc/nginx-unprivileged:[0-9.]+-alpine@sha256:[0-9a-f]{64}$' || { echo "FAIL: nginx image must be pinned by tag and digest"; exit 1; }
echo "$dep" | yq e '.spec.template.spec.containers[] | select(.name == "git-sync") | .image' - | grep -Eq '^registry\.k8s\.io/git-sync/git-sync:v[0-9.]+@sha256:[0-9a-f]{64}$' || { echo "FAIL: git-sync image must be pinned by tag and digest"; exit 1; }
args=$(echo "$dep" | yq e '.spec.template.spec.containers[] | select(.name == "git-sync") | .args[]' -)
echo "$args" | grep -qx -- '--repo=https://github.com/Fabriciooml/davros.git' || { echo "FAIL: git-sync must pull the public davros repo over https"; exit 1; }
echo "$args" | grep -qx -- '--link=current' || { echo "FAIL: git-sync must link the checkout as current (nginx root depends on it)"; exit 1; }

conf=$(echo "$built" | yq e 'select(.kind == "ConfigMap" and .metadata.name == "wiki-nginx") | .data["default.conf"]' -)
echo "$conf" | grep -qF 'root /git/current/docs/wiki;' || { echo "FAIL: nginx must serve /git/current/docs/wiki"; exit 1; }

svc=$(echo "$built" | yq e 'select(.kind == "Service" and .metadata.name == "wiki")' -)
[ "$(echo "$svc" | yq e '.spec.ports[0].targetPort' -)" = "8080" ] || { echo "FAIL: service must target nginx-unprivileged on 8080"; exit 1; }

route=$(echo "$built" | yq e 'select(.kind == "IngressRoute" and .metadata.name == "wiki")' -)
echo "$route" | grep -qF 'Host(`wiki.local.fabriciooml.dev`)' || { echo "FAIL: LAN host wiki.local.fabriciooml.dev missing"; exit 1; }
[ "$(echo "$route" | grep -c 'Host(')" = "1" ] || { echo "FAIL: wiki must stay LAN only, no public host"; exit 1; }
[ "$(echo "$route" | yq e '.spec.tls | has("secretName")' -)" = "false" ] || { echo "FAIL: route must use the default TLSStore"; exit 1; }

echo "PASS"
