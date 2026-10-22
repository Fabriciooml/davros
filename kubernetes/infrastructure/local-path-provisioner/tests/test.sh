#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

built=$(kustomize build .)

echo "$built" | kubeconform -strict -ignore-missing-schemas -summary

class=$(echo "$built" | yq e 'select(.kind == "StorageClass" and .metadata.name == "local-path")' -)
[ -n "$class" ] || { echo "FAIL: local-path StorageClass not found"; exit 1; }
[ "$(echo "$class" | yq e '.provisioner' -)" = "rancher.io/local-path" ] || { echo "FAIL: provisioner must be rancher.io/local-path"; exit 1; }
[ "$(echo "$class" | yq e '.reclaimPolicy' -)" = "Retain" ] || { echo "FAIL: reclaimPolicy must be Retain so imported data is never deleted with its PVC"; exit 1; }
[ "$(echo "$class" | yq e '.volumeBindingMode' -)" = "WaitForFirstConsumer" ] || { echo "FAIL: volumeBindingMode must be WaitForFirstConsumer"; exit 1; }

config=$(echo "$built" | yq e 'select(.kind == "ConfigMap" and .metadata.name == "local-path-config") | .data."config.json"' -)
path=$(echo "$config" | yq e -p=json '.nodePathMap[0].paths[0]' -)
[ "$path" = "/var/lib/local-pv" ] || { echo "FAIL: volumes must live on /var/lib/local-pv (the bind-mounted LV), got $path"; exit 1; }

image=$(echo "$built" | yq e 'select(.kind == "Deployment") | .spec.template.spec.containers[0].image' -)
case "$image" in
  *:latest|*:) echo "FAIL: provisioner image must be pinned"; exit 1 ;;
  *:v*) ;;
  *) echo "FAIL: provisioner image must carry a version tag, got $image"; exit 1 ;;
esac

default=$(echo "$class" | yq e '.metadata.annotations."storageclass.kubernetes.io/is-default-class" // "false"' -)
[ "$default" = "false" ] || { echo "FAIL: local-path must not be the default class"; exit 1; }

echo "PASS"
