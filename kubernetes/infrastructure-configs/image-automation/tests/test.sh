#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

built=$(kustomize build .)

echo "$built" | kubeconform -strict -ignore-missing-schemas -summary

iua=$(echo "$built" | yq e 'select(.kind == "ImageUpdateAutomation" and .metadata.name == "apps")' -)
[ -n "$iua" ] || { echo "FAIL: no ImageUpdateAutomation named apps"; exit 1; }
[ "$(echo "$iua" | yq e '.metadata.namespace' -)" = "flux-system" ] || { echo "FAIL: automation must live in flux-system"; exit 1; }
[ "$(echo "$iua" | yq e '.spec.update.path' -)" = "./kubernetes/apps" ] || { echo "FAIL: automation must only touch ./kubernetes/apps"; exit 1; }
[ "$(echo "$iua" | yq e '.spec.update.strategy' -)" = "Setters" ] || { echo "FAIL: strategy must be Setters"; exit 1; }
[ "$(echo "$iua" | yq e '.spec.git.push.branch' -)" = "main" ] || { echo "FAIL: pushes to main"; exit 1; }
[ "$(echo "$iua" | yq e '.spec.sourceRef.name' -)" = "flux-system" ] || { echo "FAIL: source must be the flux-system GitRepository"; exit 1; }

echo "PASS"
