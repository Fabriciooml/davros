#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

built=$(kustomize build .)

echo "$built" | kubeconform -strict -ignore-missing-schemas -skip Secret -summary

secret=$(echo "$built" | yq e 'select(.kind == "Secret" and .metadata.name == "grafana-admin-credentials")' -)
[ -n "$secret" ] || { echo "FAIL: no grafana-admin-credentials secret found"; exit 1; }
[ "$(echo "$secret" | yq e '.metadata.namespace' -)" = "monitoring" ] || { echo "FAIL: grafana-admin-credentials secret must live in the monitoring namespace"; exit 1; }
[ "$(echo "$secret" | yq e 'has("sops")' -)" = "true" ] || { echo "FAIL: grafana-admin-credentials secret must be sops-encrypted before being committed"; exit 1; }

grafana_route=$(echo "$built" | yq e 'select(.kind == "IngressRoute" and .metadata.name == "grafana")' -)
[ -n "$grafana_route" ] || { echo "FAIL: no grafana IngressRoute found"; exit 1; }
[ "$(echo "$grafana_route" | yq e '.metadata.namespace' -)" = "monitoring" ] || { echo "FAIL: grafana IngressRoute must live in the monitoring namespace"; exit 1; }
grafana_entrypoints=$(echo "$grafana_route" | yq e '.spec.entryPoints | join(",")' -)
case ",$grafana_entrypoints," in
  *,"websecure",*) ;;
  *) echo "FAIL: grafana route must use the websecure entrypoint, so it picks up the default tls cert"; exit 1 ;;
esac
grafana_match=$(echo "$grafana_route" | yq e '.spec.routes[0].match' -)
case "$grafana_match" in
  *grafana.local.fabriciooml.dev*) ;;
  *) echo "FAIL: grafana route must match the lan-only grafana hostname"; exit 1 ;;
esac
[ "$(echo "$grafana_route" | yq e '.spec.routes[0].services[0].name' -)" = "kube-prometheus-stack-grafana" ] || { echo "FAIL: grafana route must point at the kube-prometheus-stack-grafana service"; exit 1; }
[ "$(echo "$grafana_route" | yq e '.spec.routes[0].services[0].port' -)" = "80" ] || { echo "FAIL: grafana route must target port 80"; exit 1; }

prometheus_route=$(echo "$built" | yq e 'select(.kind == "IngressRoute" and .metadata.name == "prometheus")' -)
[ -n "$prometheus_route" ] || { echo "FAIL: no prometheus IngressRoute found"; exit 1; }
[ "$(echo "$prometheus_route" | yq e '.metadata.namespace' -)" = "monitoring" ] || { echo "FAIL: prometheus IngressRoute must live in the monitoring namespace"; exit 1; }
prometheus_entrypoints=$(echo "$prometheus_route" | yq e '.spec.entryPoints | join(",")' -)
case ",$prometheus_entrypoints," in
  *,"websecure",*) ;;
  *) echo "FAIL: prometheus route must use the websecure entrypoint, so it picks up the default tls cert"; exit 1 ;;
esac
prometheus_match=$(echo "$prometheus_route" | yq e '.spec.routes[0].match' -)
case "$prometheus_match" in
  *prometheus.local.fabriciooml.dev*) ;;
  *) echo "FAIL: prometheus route must match the lan-only prometheus hostname"; exit 1 ;;
esac
[ "$(echo "$prometheus_route" | yq e '.spec.routes[0].services[0].name' -)" = "kube-prometheus-stack-prometheus" ] || { echo "FAIL: prometheus route must point at the kube-prometheus-stack-prometheus service"; exit 1; }
[ "$(echo "$prometheus_route" | yq e '.spec.routes[0].services[0].port' -)" = "9090" ] || { echo "FAIL: prometheus route must target port 9090"; exit 1; }

scrape=$(echo "$built" | yq e 'select(.kind == "ScrapeConfig" and .metadata.name == "proxmox-host")' -)
[ -n "$scrape" ] || { echo "FAIL: no proxmox-host ScrapeConfig found"; exit 1; }
[ "$(echo "$scrape" | yq e '.metadata.namespace' -)" = "monitoring" ] || { echo "FAIL: scrapeconfig must live in the monitoring namespace"; exit 1; }
[ "$(echo "$scrape" | yq e '.metadata.labels.release' -)" = "kube-prometheus-stack" ] || { echo "FAIL: scrapeconfig needs release: kube-prometheus-stack or prometheus ignores it"; exit 1; }
[ "$(echo "$scrape" | yq e '.spec.jobName' -)" = "proxmox-host" ] || { echo "FAIL: scrape job must be named proxmox-host"; exit 1; }
[ "$(echo "$scrape" | yq e '.spec.staticConfigs[0].targets[0]' -)" = "192.168.31.42:9100" ] || { echo "FAIL: scrape target must be the host exporter on the lan address"; exit 1; }
[ "$(echo "$scrape" | yq e '.spec.scrapeInterval' -)" = "60s" ] || { echo "FAIL: scrape interval must be 60s to keep prometheus memory small"; exit 1; }

rules=$(echo "$built" | yq e 'select(.kind == "PrometheusRule" and .metadata.name == "host-alerts")' -)
[ -n "$rules" ] || { echo "FAIL: no host-alerts PrometheusRule found"; exit 1; }
[ "$(echo "$rules" | yq e '.metadata.labels.release' -)" = "kube-prometheus-stack" ] || { echo "FAIL: rules need release: kube-prometheus-stack or prometheus ignores them"; exit 1; }
alert_names=$(echo "$rules" | yq e '.spec.groups[].rules[].alert' -)
for name in ZpoolUsageHigh ZpoolNotOnline DiskSmartUnhealthy DiskSmartUnreadable DiskTemperatureHigh HostIoPressureHigh HostExporterDown HostMetricsStale; do
  grep -qx "$name" <<<"$alert_names" || { echo "FAIL: missing alert $name"; exit 1; }
done
[ "$(echo "$rules" | yq e '[.spec.groups[].rules[] | select(.alert == "ZpoolUsageHigh")] | length' -)" = "2" ] || { echo "FAIL: ZpoolUsageHigh needs a warning and a critical rule"; exit 1; }
[ "$(echo "$rules" | yq e '[.spec.groups[].rules[] | select(.alert == "ZpoolUsageHigh") | .labels.severity] | sort | join(",")' -)" = "critical,warning" ] || { echo "FAIL: ZpoolUsageHigh needs one warning and one critical rule"; exit 1; }
[ "$(echo "$rules" | yq e '.spec.groups[].rules[] | select(.alert == "ZpoolUsageHigh" and .labels.severity == "warning") | .expr' -)" = "homelab_zpool_allocated_bytes / homelab_zpool_size_bytes > 0.85" ] || { echo "FAIL: warning rule must not have an upper bound (inhibit rule mutes it)"; exit 1; }
missing_severity=$(echo "$rules" | yq e '[.spec.groups[].rules[] | select(.labels.severity == null)] | length' -)
[ "$missing_severity" = "0" ] || { echo "FAIL: every rule needs a severity label for alert routing"; exit 1; }

am_secret=$(echo "$built" | yq e 'select(.kind == "Secret" and .metadata.name == "alertmanager-config")' -)
[ -n "$am_secret" ] || { echo "FAIL: no alertmanager-config secret found"; exit 1; }
[ "$(echo "$am_secret" | yq e '.metadata.namespace' -)" = "monitoring" ] || { echo "FAIL: alertmanager-config must live in the monitoring namespace"; exit 1; }
[ "$(echo "$am_secret" | yq e 'has("sops")' -)" = "true" ] || { echo "FAIL: alertmanager-config must be sops-encrypted, it holds the telegram token"; exit 1; }
[ "$(echo "$am_secret" | yq e '.data | has("alertmanager.yaml")' -)" = "true" ] || { echo "FAIL: alertmanager-config must carry an alertmanager.yaml key"; exit 1; }

flux_pm=$(echo "$built" | yq e 'select(.kind == "PodMonitor" and .metadata.name == "flux-controllers")' -)
[ -n "$flux_pm" ] || { echo "FAIL: no flux-controllers PodMonitor found"; exit 1; }
[ "$(echo "$flux_pm" | yq e '.metadata.namespace' -)" = "monitoring" ] || { echo "FAIL: flux PodMonitor must live in the monitoring namespace"; exit 1; }
[ "$(echo "$flux_pm" | yq e '.metadata.labels.release' -)" = "kube-prometheus-stack" ] || { echo "FAIL: flux PodMonitor needs release: kube-prometheus-stack or prometheus ignores it"; exit 1; }
[ "$(echo "$flux_pm" | yq e '.spec.namespaceSelector.matchNames[0]' -)" = "flux-system" ] || { echo "FAIL: flux PodMonitor must select the flux-system namespace"; exit 1; }
[ "$(echo "$flux_pm" | yq e '.spec.selector.matchLabels["app.kubernetes.io/part-of"]' -)" = "flux" ] || { echo "FAIL: flux PodMonitor must select pods labelled app.kubernetes.io/part-of=flux"; exit 1; }
[ "$(echo "$flux_pm" | yq e '.spec.podMetricsEndpoints[0].port' -)" = "http-prom" ] || { echo "FAIL: flux PodMonitor must scrape the http-prom port"; exit 1; }

echo "PASS"
