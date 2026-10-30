#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

built=$(kustomize build .)

echo "$built" | kubeconform -strict -ignore-missing-schemas -summary

ns=$(echo "$built" | yq e 'select(.kind == "Namespace" and .metadata.name == "arr")' -)
[ -n "$ns" ] || { echo "FAIL: Namespace arr missing"; exit 1; }

echo "PASS"
