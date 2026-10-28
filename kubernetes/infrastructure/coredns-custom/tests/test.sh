#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

built=$(kustomize build .)

echo "$built" | kubeconform -strict -ignore-missing-schemas -summary

cm=$(echo "$built" | yq e 'select(.kind == "ConfigMap" and .metadata.name == "coredns-custom")' -)
[ -n "$cm" ] || { echo "FAIL: no ConfigMap coredns-custom"; exit 1; }
[ "$(echo "$cm" | yq e '.metadata.namespace' -)" = "kube-system" ] || { echo "FAIL: coredns-custom must live in kube-system, where k3s mounts it"; exit 1; }
[ "$(echo "$cm" | yq e '.data | keys | join(",")' -)" = "cluster-local-search.server,fabriciooml-search.server" ] || { echo "FAIL: keys must be cluster-local-search.server and fabriciooml-search.server (k3s imports *.server as extra server blocks)"; exit 1; }
block=$(echo "$cm" | yq e '.data["cluster-local-search.server"]' -)
echo "$block" | grep -q '^cluster\.local\.fabriciooml\.dev:53 {$' || { echo "FAIL: server block must be for the zone cluster.local.fabriciooml.dev:53"; exit 1; }
echo "$block" | grep -q 'rcode NXDOMAIN' || { echo "FAIL: the zone must answer NXDOMAIN"; exit 1; }

search=$(echo "$cm" | yq e '.data["fabriciooml-search.server"]' -)
echo "$search" | grep -q '^local\.fabriciooml\.dev:53 {$' || { echo "FAIL: *.local.fabriciooml.dev must keep resolving through the upstream (pihole wildcard)"; exit 1; }
echo "$search" | grep -q '^fabriciooml\.dev:53 {$' || { echo "FAIL: server block for fabriciooml.dev:53 missing"; exit 1; }
echo "$search" | grep -qF 'match "^[^.]+[.].+[.]fabriciooml[.]dev[.]$"' || { echo "FAIL: names with two or more labels under fabriciooml.dev (search-list expansions of external names) must be matched"; exit 1; }
echo "$search" | grep -q 'rcode NXDOMAIN' || { echo "FAIL: matched names must answer NXDOMAIN, not an empty NOERROR (musl resolvers stop at NODATA)"; exit 1; }
[ "$(echo "$search" | grep -c 'forward \. /etc/resolv.conf')" = "2" ] || { echo "FAIL: both blocks must forward to the node resolvers"; exit 1; }

echo "PASS"
