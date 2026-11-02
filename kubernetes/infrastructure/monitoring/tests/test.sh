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

[ "$(echo "$helmrelease" | yq e '.spec.values.alertmanager.enabled' -)" = "true" ] || { echo "FAIL: alertmanager must be enabled so alerts can be delivered"; exit 1; }
[ "$(echo "$helmrelease" | yq e '.spec.values.alertmanager.alertmanagerSpec.configSecret' -)" = "alertmanager-config" ] || { echo "FAIL: alertmanager must read its whole config from the alertmanager-config sops secret, so the telegram token never appears in git"; exit 1; }
[ "$(echo "$helmrelease" | yq e '.spec.values.alertmanager.alertmanagerSpec.resources.limits.memory' -)" != "null" ] || { echo "FAIL: alertmanager needs a memory limit on this memory-tight node"; exit 1; }
for flag in kubeScheduler kubeControllerManager kubeProxy; do
  [ "$(echo "$helmrelease" | yq e ".spec.values.${flag}.enabled" -)" = "false" ] || { echo "FAIL: ${flag} is embedded in k3s and must not be scraped"; exit 1; }
done
for alert in KubeSchedulerDown KubeControllerManagerDown KubeProxyDown; do
  [ "$(echo "$helmrelease" | yq e ".spec.values.defaultRules.disabled.${alert}" -)" = "true" ] || { echo "FAIL: ${alert} is a k3s false positive and must be disabled"; exit 1; }
done

[ "$(echo "$helmrelease" | yq e '.spec.values.grafana.admin.existingSecret' -)" = "grafana-admin-credentials" ] || { echo "FAIL: grafana must read its admin password from the grafana-admin-credentials secret, not a plaintext value"; exit 1; }
[ "$(echo "$helmrelease" | yq e '.spec.values.grafana.persistence.storageClassName' -)" = "local-path" ] || { echo "FAIL: grafana persistence must use the local-path storage class"; exit 1; }

[ "$(echo "$helmrelease" | yq e '.spec.values.prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.storageClassName' -)" = "local-path" ] || { echo "FAIL: prometheus storage must use the local-path storage class"; exit 1; }
[ "$(echo "$helmrelease" | yq e '.spec.values.prometheus.prometheusSpec.retention' -)" = "15d" ] || { echo "FAIL: prometheus retention must be 15d"; exit 1; }

echo "PASS"
