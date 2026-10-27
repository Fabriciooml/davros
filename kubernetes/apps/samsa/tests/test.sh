#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

built=$(kustomize build .)

echo "$built" | kubeconform -strict -ignore-missing-schemas -skip Secret -summary

dep=$(echo "$built" | yq e 'select(.kind == "Deployment" and .metadata.name == "samsa")' -)
[ -n "$dep" ] || { echo "FAIL: no Deployment samsa"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.template.spec.containers[0].image' -)" = "ghcr.io/fabriciooml/samsa:latest" ] || { echo "FAIL: image must follow :latest"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.template.spec.containers[0].imagePullPolicy' -)" = "Always" ] || { echo "FAIL: must pull Always"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.template.spec.enableServiceLinks' -)" = "false" ] || { echo "FAIL: samsa must disable service-link env vars"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.progressDeadlineSeconds' -)" = "1200" ] || { echo "FAIL: samsa progressDeadlineSeconds must be 1200"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.template.spec.containers[0].env[] | select(.name == "KAFKA_BOOTSTRAP") | .value' -)" = "kafka.kafka.svc.cluster.local:9092" ] || { echo "FAIL: kafka must be the in-cluster service"; exit 1; }
# kustomize build strips trailing comments, and Flux reads the marker from the source file in git
grep -Eq '^[[:space:]]+fabriciooml\.dev/image-digest: sha256:[0-9a-f]{64} # \{"\$imagepolicy": "flux-system:samsa:digest"\}$' deployment.yaml || { echo "FAIL: digest marker missing"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.template.spec.containers[0].readinessProbe.httpGet.path' -)" = "/health/ready" ] || { echo "FAIL: readiness path"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.template.spec.containers[0].livenessProbe.httpGet.path' -)" = "/health/live" ] || { echo "FAIL: liveness must not depend on kafka/postgres"; exit 1; }
for k in DATABASE_URL ADMIN_BOOTSTRAP_PASSWORD; do
  [ "$(echo "$dep" | yq e ".spec.template.spec.containers[0].env[] | select(.name == \"$k\") | .valueFrom.secretKeyRef.name" -)" = "samsa-secrets" ] || { echo "FAIL: $k must come from the secret"; exit 1; }
  [ "$(echo "$dep" | yq e ".spec.template.spec.containers[0].env[] | select(.name == \"$k\") | .valueFrom.secretKeyRef.key" -)" = "$k" ] || { echo "FAIL: $k must reference key $k"; exit 1; }
done

pvc=$(echo "$built" | yq e 'select(.kind == "PersistentVolumeClaim" and .metadata.name == "samsa-keys")' -)
[ "$(echo "$pvc" | yq e '.spec.storageClassName' -)" = "local-path" ] || { echo "FAIL: keys on local-path"; exit 1; }

echo "$built" | yq e 'select(.kind == "IngressRoute") | .spec.routes[0].match' - | grep -qF 'Host(`samsa.local.fabriciooml.dev`)' || { echo "FAIL: host missing"; exit 1; }

pol=$(echo "$built" | yq e 'select(.kind == "ImagePolicy" and .metadata.name == "samsa")' -)
[ "$(echo "$pol" | yq e '.spec.digestReflectionPolicy' -)" = "Always" ] || { echo "FAIL: policy must reflect the digest"; exit 1; }

repo=$(echo "$built" | yq e 'select(.kind == "ImageRepository" and .metadata.name == "samsa")' -)
[ "$(echo "$dep" | yq e '.spec.template.spec.containers[0].image' -)" = "$(echo "$repo" | yq e '.spec.image' -):latest" ] || { echo "FAIL: samsa image must be the samsa ImageRepository image:latest"; exit 1; }
[ "$(echo "$pol" | yq e '.spec.imageRepositoryRef.name' -)" = "samsa" ] || { echo "FAIL: samsa policy must reference ImageRepository samsa"; exit 1; }
[ "$(echo "$pol" | yq e '.spec.filterTags.pattern' -)" = "^latest\$" ] || { echo "FAIL: samsa must follow latest"; exit 1; }

keys=$(echo "$built" | yq e 'select(.kind == "Secret" and .metadata.name == "samsa-secrets") | .stringData | keys | .[]' - | sort | paste -sd, -)
[ "$keys" = "ADMIN_BOOTSTRAP_PASSWORD,DATABASE_URL" ] || { echo "FAIL: samsa-secrets must hold exactly ADMIN_BOOTSTRAP_PASSWORD and DATABASE_URL"; exit 1; }
values=$(echo "$built" | yq e 'select(.kind == "Secret" and .metadata.name == "samsa-secrets") | .stringData | to_entries | .[].value' -)
[ -n "$values" ] || { echo "FAIL: samsa-secrets has no stringData entries"; exit 1; }
if echo "$values" | grep -qv '^ENC\['; then echo "FAIL: samsa-secrets must be fully SOPS encrypted"; exit 1; fi

echo "PASS"
