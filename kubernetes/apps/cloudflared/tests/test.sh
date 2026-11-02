#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

built=$(kustomize build .)

echo "$built" | kubeconform -strict -ignore-missing-schemas -skip Secret -summary

dep=$(echo "$built" | yq e 'select(.kind == "Deployment" and .metadata.name == "cloudflared")' -)
[ -n "$dep" ] || { echo "FAIL: no Deployment cloudflared"; exit 1; }
[ "$(echo "$dep" | yq e '.metadata.namespace' -)" = "cloudflared" ] || { echo "FAIL: must live in cloudflared"; exit 1; }
echo "$dep" | yq e '.spec.template.spec.containers[0].image' - | grep -Eq '^cloudflare/cloudflared:2026\.2\.0@sha256:[0-9a-f]{64}$' || { echo "FAIL: image must be pinned to 2026.2.0 with a digest"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.template.spec.enableServiceLinks' -)" = "false" ] || { echo "FAIL: service-link env vars must be off"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.replicas' -)" = "1" ] || { echo "FAIL: replicas must be 1"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.template.spec.containers[0].env[] | select(.name == "TUNNEL_TOKEN") | .valueFrom.secretKeyRef.name' -)" = "cloudflared-token" ] || { echo "FAIL: TUNNEL_TOKEN must come from the cloudflared-token secret"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.template.spec.containers[0].env[] | select(.name == "TUNNEL_TOKEN") | .value' -)" = "null" ] || { echo "FAIL: TUNNEL_TOKEN must not be a plaintext value"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.template.spec.containers[0].readinessProbe.httpGet.path' -)" = "/ready" ] || { echo "FAIL: readiness must use /ready"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.template.spec.containers[0].resources.limits.memory' -)" != "null" ] || { echo "FAIL: memory limit required"; exit 1; }

secret=$(echo "$built" | yq e 'select(.kind == "Secret" and .metadata.name == "cloudflared-token")' -)
[ -n "$secret" ] || { echo "FAIL: no Secret cloudflared-token"; exit 1; }
echo "$secret" | yq e '.sops | has("age")' - | grep -q true || { echo "FAIL: secret must be SOPS-encrypted"; exit 1; }
echo "$secret" | yq e '.data.TUNNEL_TOKEN // .stringData.TUNNEL_TOKEN' - | grep -q '^ENC\[' || { echo "FAIL: TUNNEL_TOKEN must be encrypted"; exit 1; }

echo "PASS"
