#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

built=$(kustomize build .)

echo "$built" | kubeconform -strict -ignore-missing-schemas -summary

infra=$(echo "$built" | yq e 'select(.kind == "Kustomization" and .metadata.name == "infrastructure")' -)
[ -n "$infra" ] || { echo "FAIL: no flux Kustomization named infrastructure"; exit 1; }
[ "$(echo "$infra" | yq e '.spec.path' -)" = "./kubernetes/infrastructure" ] || { echo "FAIL: infrastructure kustomization must point at kubernetes/infrastructure"; exit 1; }
[ "$(echo "$infra" | yq e '.spec.decryption.provider' -)" = "sops" ] || { echo "FAIL: infrastructure kustomization must decrypt with sops"; exit 1; }
[ "$(echo "$infra" | yq e '.spec.decryption.secretRef.name' -)" = "sops-age" ] || { echo "FAIL: infrastructure kustomization must reference the sops-age secret"; exit 1; }

apps=$(echo "$built" | yq e 'select(.kind == "Kustomization" and .metadata.name == "apps")' -)
[ -n "$apps" ] || { echo "FAIL: no flux Kustomization named apps"; exit 1; }
[ "$(echo "$apps" | yq e '.spec.path' -)" = "./kubernetes/apps" ] || { echo "FAIL: apps kustomization must point at kubernetes/apps"; exit 1; }
[ "$(echo "$apps" | yq e '.spec.dependsOn[0].name' -)" = "infrastructure" ] || { echo "FAIL: apps must depend on infrastructure, so apps never reconcile before cilium/cert-manager/csi are up"; exit 1; }
[ "$(echo "$apps" | yq e '.spec.decryption.provider' -)" = "sops" ] || { echo "FAIL: apps kustomization must decrypt with sops too"; exit 1; }

echo "PASS"
