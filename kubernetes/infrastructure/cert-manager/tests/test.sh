#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

built=$(kustomize build .)

echo "$built" | kubeconform -strict -ignore-missing-schemas -skip Secret -summary

helmrelease=$(echo "$built" | yq e 'select(.kind == "HelmRelease")' -)
[ -n "$helmrelease" ] || { echo "FAIL: no HelmRelease found"; exit 1; }
[ "$(echo "$helmrelease" | yq e '.spec.chart.spec.chart' -)" = "cert-manager" ] || { echo "FAIL: helmrelease must install the cert-manager chart"; exit 1; }
[ "$(echo "$helmrelease" | yq e '.spec.values.crds.enabled' -)" = "true" ] || { echo "FAIL: chart must install its own CRDs"; exit 1; }

staging=$(echo "$built" | yq e 'select(.kind == "ClusterIssuer" and .metadata.name == "letsencrypt-staging")' -)
[ -n "$staging" ] || { echo "FAIL: no letsencrypt-staging ClusterIssuer found"; exit 1; }
[ "$(echo "$staging" | yq e '.spec.acme.server' -)" = "https://acme-staging-v02.api.letsencrypt.org/directory" ] || { echo "FAIL: staging issuer must point at the LE staging endpoint"; exit 1; }
[ "$(echo "$staging" | yq e '.spec.acme.solvers[0].dns01.cloudflare.apiTokenSecretRef.name' -)" = "cloudflare-api-token" ] || { echo "FAIL: staging issuer must use the cloudflare dns01 solver with our secret"; exit 1; }

production=$(echo "$built" | yq e 'select(.kind == "ClusterIssuer" and .metadata.name == "letsencrypt-production")' -)
[ -n "$production" ] || { echo "FAIL: no letsencrypt-production ClusterIssuer found"; exit 1; }
[ "$(echo "$production" | yq e '.spec.acme.server' -)" = "https://acme-v02.api.letsencrypt.org/directory" ] || { echo "FAIL: production issuer must point at the LE production endpoint"; exit 1; }

secret=$(echo "$built" | yq e 'select(.kind == "Secret" and .metadata.name == "cloudflare-api-token")' -)
[ -n "$secret" ] || { echo "FAIL: no cloudflare-api-token secret found"; exit 1; }
[ "$(echo "$secret" | yq e 'has("sops")' -)" = "true" ] || { echo "FAIL: cloudflare-api-token secret must be sops-encrypted before being committed"; exit 1; }

echo "PASS"
