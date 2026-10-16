#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

built=$(kustomize build .)

echo "$built" | kubeconform -strict -ignore-missing-schemas -summary

media_class=$(echo "$built" | yq e 'select(.kind == "StorageClass" and .metadata.name == "nfs-media")' -)
[ -n "$media_class" ] || { echo "FAIL: nfs-media StorageClass not found"; exit 1; }
[ "$(echo "$media_class" | yq e '.provisioner' -)" = "nfs.csi.k8s.io" ] || { echo "FAIL: nfs-media provisioner must be nfs.csi.k8s.io"; exit 1; }
[ "$(echo "$media_class" | yq e '.parameters.server' -)" = "192.168.31.42" ] || { echo "FAIL: nfs-media server must be the proxmox host"; exit 1; }
[ "$(echo "$media_class" | yq e '.parameters.share' -)" = "/pool/data" ] || { echo "FAIL: nfs-media share must be /pool/data"; exit 1; }

appdata_class=$(echo "$built" | yq e 'select(.kind == "StorageClass" and .metadata.name == "nfs-appdata")' -)
[ -n "$appdata_class" ] || { echo "FAIL: nfs-appdata StorageClass not found"; exit 1; }
[ "$(echo "$appdata_class" | yq e '.provisioner' -)" = "nfs.csi.k8s.io" ] || { echo "FAIL: nfs-appdata provisioner must be nfs.csi.k8s.io"; exit 1; }
[ "$(echo "$appdata_class" | yq e '.parameters.server' -)" = "192.168.31.42" ] || { echo "FAIL: nfs-appdata server must be the proxmox host"; exit 1; }
[ "$(echo "$appdata_class" | yq e '.parameters.share' -)" = "/mnt/hd2tb-k8s-appdata" ] || { echo "FAIL: nfs-appdata share must be /mnt/hd2tb-k8s-appdata"; exit 1; }

helmrelease=$(echo "$built" | yq e 'select(.kind == "HelmRelease")' -)
[ -n "$helmrelease" ] || { echo "FAIL: no HelmRelease found"; exit 1; }
[ "$(echo "$helmrelease" | yq e '.spec.chart.spec.chart' -)" = "csi-driver-nfs" ] || { echo "FAIL: helmrelease must install the csi-driver-nfs chart"; exit 1; }

echo "PASS"
