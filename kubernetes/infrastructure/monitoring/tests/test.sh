#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

built=$(kustomize build .)

echo "$built" | kubeconform -strict -ignore-missing-schemas -summary

ns=$(echo "$built" | yq e 'select(.kind == "Namespace" and .metadata.name == "monitoring")' -)
[ -n "$ns" ] || { echo "FAIL: monitoring Namespace not found"; exit 1; }

helmrelease=$(echo "$built" | yq e 'select(.kind == "HelmRelease")' -)
[ -n "$helmrelease" ] || { echo "FAIL: no HelmRelease found"; exit 1; }
[ "$(echo "$helmrelease" | yq e '.metadata.namespace' -)" = "monitoring" ] || { echo "FAIL: helmrelease must live in the monitoring namespace"; exit 1; }
[ "$(echo "$helmrelease" | yq e '.spec.chart.spec.chart' -)" = "kube-prometheus-stack" ] || { echo "FAIL: helmrelease must install the kube-prometheus-stack chart"; exit 1; }

[ "$(echo "$helmrelease" | yq e '.spec.values.alertmanager.enabled' -)" = "false" ] || { echo "FAIL: alertmanager must be disabled -- no notification channels configured yet"; exit 1; }

[ "$(echo "$helmrelease" | yq e '.spec.values.grafana.admin.existingSecret' -)" = "grafana-admin-credentials" ] || { echo "FAIL: grafana must read its admin password from the grafana-admin-credentials secret, not a plaintext value"; exit 1; }
[ "$(echo "$helmrelease" | yq e '.spec.values.grafana.persistence.storageClassName' -)" = "nfs-appdata" ] || { echo "FAIL: grafana persistence must use the nfs-appdata storage class"; exit 1; }

[ "$(echo "$helmrelease" | yq e '.spec.values.prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.storageClassName' -)" = "nfs-appdata" ] || { echo "FAIL: prometheus storage must use the nfs-appdata storage class"; exit 1; }
[ "$(echo "$helmrelease" | yq e '.spec.values.prometheus.prometheusSpec.retention' -)" = "15d" ] || { echo "FAIL: prometheus retention must be 15d"; exit 1; }

echo "PASS"
