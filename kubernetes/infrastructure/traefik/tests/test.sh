#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

built=$(kustomize build .)

echo "$built" | kubeconform -strict -ignore-missing-schemas -summary

helmrelease=$(echo "$built" | yq e 'select(.kind == "HelmRelease")' -)
[ -n "$helmrelease" ] || { echo "FAIL: no HelmRelease found"; exit 1; }
[ "$(echo "$helmrelease" | yq e '.spec.chart.spec.chart' -)" = "traefik" ] || { echo "FAIL: helmrelease must install the traefik chart"; exit 1; }
[ "$(echo "$helmrelease" | yq e '.spec.values.service.type' -)" = "LoadBalancer" ] || { echo "FAIL: traefik service must be a LoadBalancer, so cilium l2announcement gives it a lan ip"; exit 1; }

namespace=$(echo "$built" | yq e 'select(.kind == "Namespace" and .metadata.name == "traefik")' -)
[ -n "$namespace" ] || { echo "FAIL: no traefik namespace found"; exit 1; }

[ "$(echo "$helmrelease" | yq e '.spec.values.api.dashboard' -)" = "true" ] || { echo "FAIL: traefik dashboard/api must be enabled"; exit 1; }

echo "PASS"
