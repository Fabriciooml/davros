#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

built=$(kustomize build .)

echo "$built" | kubeconform -strict -ignore-missing-schemas -skip Secret -summary

for chart in cert-manager csi-driver-nfs; do
  found=$(echo "$built" | yq e "select(.kind == \"HelmRelease\" and .spec.chart.spec.chart == \"$chart\")" -)
  [ -n "$found" ] || { echo "FAIL: $chart HelmRelease missing from the aggregated infrastructure build"; exit 1; }
done

class=$(echo "$built" | yq e 'select(.kind == "StorageClass" and .metadata.name == "local-path")' -)
[ -n "$class" ] || { echo "FAIL: local-path StorageClass missing from the aggregated infrastructure build"; exit 1; }

echo "PASS"
