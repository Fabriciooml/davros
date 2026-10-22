#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

built=$(kustomize build .)

echo "$built" | kubeconform -strict -ignore-missing-schemas -skip Secret -summary

for kind in ClusterIssuer Certificate IngressRoute EndpointSlice; do
  found=$(echo "$built" | yq e "select(.kind == \"$kind\")" -)
  [ -n "$found" ] || { echo "FAIL: $kind missing from the aggregated infrastructure-configs build"; exit 1; }
done

echo "PASS"
