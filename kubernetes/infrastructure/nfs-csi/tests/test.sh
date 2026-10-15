#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

built=$(kustomize build .)

echo "$built" | kubeconform -strict -ignore-missing-schemas -summary

storage_class=$(echo "$built" | yq e 'select(.kind == "StorageClass")' -)
[ -n "$storage_class" ] || { echo "FAIL: no StorageClass found"; exit 1; }
[ "$(echo "$storage_class" | yq e '.provisioner' -)" = "nfs.csi.k8s.io" ] || { echo "FAIL: provisioner must be nfs.csi.k8s.io"; exit 1; }
[ "$(echo "$storage_class" | yq e '.parameters.server' -)" = "192.168.31.42" ] || { echo "FAIL: nfs server must be the proxmox host"; exit 1; }
[ "$(echo "$storage_class" | yq e '.parameters.share' -)" = "/pool/data" ] || { echo "FAIL: nfs share must be /pool/data"; exit 1; }

helmrelease=$(echo "$built" | yq e 'select(.kind == "HelmRelease")' -)
[ -n "$helmrelease" ] || { echo "FAIL: no HelmRelease found"; exit 1; }
[ "$(echo "$helmrelease" | yq e '.spec.chart.spec.chart' -)" = "csi-driver-nfs" ] || { echo "FAIL: helmrelease must install the csi-driver-nfs chart"; exit 1; }

echo "PASS"
