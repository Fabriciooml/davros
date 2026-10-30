#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

built=$(kustomize build .)

echo "$built" | kubeconform -strict -ignore-missing-schemas -skip Secret -summary

cj=$(echo "$built" | yq e 'select(.kind == "CronJob" and .metadata.name == "configarr")' -)
[ -n "$cj" ] || { echo "FAIL: no CronJob configarr"; exit 1; }
[ "$(echo "$cj" | yq e '.metadata.namespace' -)" = "arr" ] || { echo "FAIL: must live in arr"; exit 1; }
[ "$(echo "$cj" | yq e '.spec.suspend' -)" = "true" ] || { echo "FAIL: must stay suspended until the stack is verified"; exit 1; }
[ "$(echo "$cj" | yq e '.spec.schedule' -)" = "0 4 * * 0" ] || { echo "FAIL: schedule must be weekly (0 4 * * 0)"; exit 1; }
[ "$(echo "$cj" | yq e '.spec.timeZone' -)" = "America/Sao_Paulo" ] || { echo "FAIL: timeZone must be America/Sao_Paulo"; exit 1; }
[ "$(echo "$cj" | yq e '.spec.concurrencyPolicy' -)" = "Forbid" ] || { echo "FAIL: concurrencyPolicy must be Forbid"; exit 1; }
[ "$(echo "$cj" | yq e '.spec.startingDeadlineSeconds' -)" = "600" ] || { echo "FAIL: startingDeadlineSeconds must be 600"; exit 1; }
[ "$(echo "$cj" | yq e '.spec.jobTemplate.spec.backoffLimit' -)" = "1" ] || { echo "FAIL: backoffLimit must be 1"; exit 1; }
echo "$cj" | yq e '.spec.jobTemplate.spec.template.spec.containers[0].image' - | grep -Eq '^ghcr\.io/raydak-labs/configarr:1\.30\.1@sha256:[0-9a-f]{64}$' || { echo "FAIL: image must be pinned to 1.30.1 with a digest"; exit 1; }
[ "$(echo "$cj" | yq e '.spec.jobTemplate.spec.template.spec.restartPolicy' -)" = "Never" ] || { echo "FAIL: restartPolicy must be Never"; exit 1; }
[ "$(echo "$cj" | yq e '.spec.jobTemplate.spec.template.spec.containers[0].volumeMounts[] | select(.mountPath == "/app/repos") | .name' -)" = "repos" ] || { echo "FAIL: /app/repos cache missing"; exit 1; }
[ "$(echo "$cj" | yq e '.spec.jobTemplate.spec.template.spec.containers[0].volumeMounts[] | select(.mountPath == "/app/config/config.yml") | .subPath' -)" = "config.yml" ] || { echo "FAIL: config.yml must be mounted by subPath"; exit 1; }
[ "$(echo "$cj" | yq e '.spec.jobTemplate.spec.template.spec.containers[0].volumeMounts[] | select(.mountPath == "/app/config/secrets.yml") | .subPath' -)" = "secrets.yml" ] || { echo "FAIL: secrets.yml must be mounted by subPath"; exit 1; }
[ "$(echo "$cj" | yq e '.spec.jobTemplate.spec.template.spec.containers[0].resources.limits.memory' -)" = "1Gi" ] || { echo "FAIL: memory limit must be 1Gi"; exit 1; }

echo "$built" | yq e 'select(.kind == "Secret" and .metadata.name == "configarr-secrets") | .sops | has("age")' - | grep -q true || { echo "FAIL: secret must be SOPS-encrypted"; exit 1; }

pvc=$(echo "$built" | yq e 'select(.kind == "PersistentVolumeClaim" and .metadata.name == "configarr-repos")' -)
[ "$(echo "$pvc" | yq e '.spec.storageClassName' -)" = "local-path" ] || { echo "FAIL: repos cache must be on local-path"; exit 1; }

cm=$(echo "$built" | yq e 'select(.kind == "ConfigMap" and (.metadata.name | test("^configarr-config")))' -)
[ -n "$cm" ] || { echo "FAIL: config ConfigMap missing"; exit 1; }
if echo "$cm" | grep -q '192\.168\.31\.226' ; then
  echo "$cm" | yq e '.data."config.yml"' - | grep -v '^[[:space:]]*#' | grep -q '192\.168\.31\.226' && { echo "FAIL: config.yml still points at LXC 104"; exit 1; }
fi
echo "$cm" | yq e '.data."config.yml"' - | grep -E '^[[:space:]]*api_key:' | grep -qv '!secret' && { echo "FAIL: api_key must use !secret"; exit 1; }

echo "PASS"
