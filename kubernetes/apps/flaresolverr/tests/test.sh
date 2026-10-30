#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

built=$(kustomize build .)

echo "$built" | kubeconform -strict -ignore-missing-schemas -summary

dep=$(echo "$built" | yq e 'select(.kind == "Deployment" and .metadata.name == "flaresolverr")' -)
[ -n "$dep" ] || { echo "FAIL: no Deployment flaresolverr"; exit 1; }
[ "$(echo "$dep" | yq e '.metadata.namespace' -)" = "arr" ] || { echo "FAIL: must live in arr"; exit 1; }
echo "$dep" | yq e '.spec.template.spec.containers[0].image' - | grep -Eq '^ghcr\.io/flaresolverr/flaresolverr:v[0-9.]+@sha256:[0-9a-f]{64}$' || { echo "FAIL: image must be pinned by tag and digest"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.strategy.type' -)" = "Recreate" ] || { echo "FAIL: strategy must be Recreate"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.template.spec.enableServiceLinks' -)" = "false" ] || { echo "FAIL: service-link env vars must be off"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.progressDeadlineSeconds' -)" = "1200" ] || { echo "FAIL: progressDeadlineSeconds must be 1200"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.template.spec.containers[0].ports[0].containerPort' -)" = "8191" ] || { echo "FAIL: port must be 8191"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.template.spec.containers[0].resources.limits.memory' -)" != "null" ] || { echo "FAIL: memory limit required"; exit 1; }

svc=$(echo "$built" | yq e 'select(.kind == "Service" and .metadata.name == "flaresolverr")' -)
[ "$(echo "$svc" | yq e '.spec.ports[0].port' -)" = "8191" ] || { echo "FAIL: Service port must be 8191"; exit 1; }

echo "PASS"
