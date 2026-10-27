#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

built=$(kustomize build .)

echo "$built" | kubeconform -strict -ignore-missing-schemas -summary

cm=$(echo "$built" | yq e 'select(.kind == "ConfigMap" and .metadata.name == "coredns-custom")' -)
[ -n "$cm" ] || { echo "FAIL: no ConfigMap coredns-custom"; exit 1; }
[ "$(echo "$cm" | yq e '.metadata.namespace' -)" = "kube-system" ] || { echo "FAIL: coredns-custom must live in kube-system, where k3s mounts it"; exit 1; }
[ "$(echo "$cm" | yq e '.data | keys | .[]' -)" = "cluster-local-search.server" ] || { echo "FAIL: the only key must be cluster-local-search.server (k3s imports *.server as extra server blocks)"; exit 1; }
block=$(echo "$cm" | yq e '.data["cluster-local-search.server"]' -)
echo "$block" | grep -q '^cluster\.local\.fabriciooml\.dev:53 {$' || { echo "FAIL: server block must be for the zone cluster.local.fabriciooml.dev:53"; exit 1; }
echo "$block" | grep -q 'rcode NXDOMAIN' || { echo "FAIL: the zone must answer NXDOMAIN"; exit 1; }

echo "PASS"
