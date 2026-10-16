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

echo "PASS"
