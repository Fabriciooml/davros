#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

built=$(kustomize build .)

echo "$built" | kubeconform -strict -ignore-missing-schemas -skip Secret -summary

helmrelease=$(echo "$built" | yq e 'select(.kind == "HelmRelease")' -)
[ -n "$helmrelease" ] || { echo "FAIL: no HelmRelease found"; exit 1; }
[ "$(echo "$helmrelease" | yq e '.spec.chart.spec.chart' -)" = "cert-manager" ] || { echo "FAIL: helmrelease must install the cert-manager chart"; exit 1; }
[ "$(echo "$helmrelease" | yq e '.spec.values.crds.enabled' -)" = "true" ] || { echo "FAIL: chart must install its own CRDs"; exit 1; }

echo "PASS"
