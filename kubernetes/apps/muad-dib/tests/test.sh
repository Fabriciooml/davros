#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

built=$(kustomize build .)

echo "$built" | kubeconform -strict -ignore-missing-schemas -skip Secret -summary

dep=$(echo "$built" | yq e 'select(.kind == "Deployment" and .metadata.name == "muad-dib")' -)
[ -n "$dep" ] || { echo "FAIL: no Deployment muad-dib"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.template.spec.containers[0].image' -)" = "ghcr.io/fabriciooml/muad_dib:main" ] || { echo "FAIL: image must follow :main"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.template.spec.containers[0].imagePullPolicy' -)" = "Always" ] || { echo "FAIL: must pull Always"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.template.spec.enableServiceLinks' -)" = "false" ] || { echo "FAIL: muad-dib must disable service-link env vars"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.progressDeadlineSeconds' -)" = "1200" ] || { echo "FAIL: muad-dib progressDeadlineSeconds must be 1200"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.template.spec.containers[0].env[] | select(.name == "KAFKA_BOOTSTRAP_SERVERS") | .value' -)" = "kafka.kafka.svc.cluster.local:9092" ] || { echo "FAIL: kafka must be the in-cluster service"; exit 1; }
# kustomize build strips trailing comments, and Flux reads the marker from the source file in git
grep -Eq '^[[:space:]]+fabriciooml\.dev/image-digest: sha256:[0-9a-f]{64} # \{"\$imagepolicy": "flux-system:muad-dib:digest"\}$' deployment.yaml || { echo "FAIL: digest marker missing"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.template.spec.containers[0].livenessProbe.httpGet.path' -)" = "/health/live" ] || { echo "FAIL: liveness path"; exit 1; }
for k in DATABASE_URL ADMIN_API_KEY; do
  [ "$(echo "$dep" | yq e ".spec.template.spec.containers[0].env[] | select(.name == \"$k\") | .valueFrom.secretKeyRef.name" -)" = "muad-dib-secrets" ] || { echo "FAIL: $k must come from the secret"; exit 1; }
  [ "$(echo "$dep" | yq e ".spec.template.spec.containers[0].env[] | select(.name == \"$k\") | .valueFrom.secretKeyRef.key" -)" = "$k" ] || { echo "FAIL: $k must reference key $k"; exit 1; }
done
init=$(echo "$dep" | yq e '.spec.template.spec.initContainers[0]' -)
[ "$(echo "$init" | yq e '.name' -)" = "migrate" ] || { echo "FAIL: first initContainer must be migrate"; exit 1; }
[ "$(echo "$init" | yq e '.command | join(" ")' -)" = "alembic upgrade head" ] || { echo "FAIL: migrate must run alembic upgrade head"; exit 1; }
[ "$(echo "$init" | yq e '.image' -)" = "$(echo "$dep" | yq e '.spec.template.spec.containers[0].image' -)" ] || { echo "FAIL: migrate must use the app image"; exit 1; }
[ "$(echo "$init" | yq e '.imagePullPolicy' -)" = "Always" ] || { echo "FAIL: migrate must pull Always"; exit 1; }
[ "$(echo "$init" | yq e '.env[] | select(.name == "DATABASE_URL") | .valueFrom.secretKeyRef.name' -)" = "muad-dib-secrets" ] || { echo "FAIL: migrate DATABASE_URL must come from the secret"; exit 1; }
[ "$(echo "$init" | yq e '.env[] | select(.name == "DATABASE_URL") | .valueFrom.secretKeyRef.key' -)" = "DATABASE_URL" ] || { echo "FAIL: migrate DATABASE_URL must reference key DATABASE_URL"; exit 1; }

echo "$built" | yq e 'select(.kind == "IngressRoute") | .spec.routes[0].match' - | grep -qF 'Host(`muad-dib.local.fabriciooml.dev`)' || { echo "FAIL: host missing"; exit 1; }

pol=$(echo "$built" | yq e 'select(.kind == "ImagePolicy" and .metadata.name == "muad-dib")' -)
[ "$(echo "$pol" | yq e '.spec.digestReflectionPolicy' -)" = "Always" ] || { echo "FAIL: policy must reflect the digest"; exit 1; }
repo=$(echo "$built" | yq e 'select(.kind == "ImageRepository" and .metadata.name == "muad-dib")' -)
[ "$(echo "$dep" | yq e '.spec.template.spec.containers[0].image' -)" = "$(echo "$repo" | yq e '.spec.image' -):main" ] || { echo "FAIL: muad-dib image must be the muad-dib ImageRepository image:main"; exit 1; }
[ "$(echo "$pol" | yq e '.spec.imageRepositoryRef.name' -)" = "muad-dib" ] || { echo "FAIL: muad-dib policy must reference ImageRepository muad-dib"; exit 1; }
[ "$(echo "$pol" | yq e '.spec.filterTags.pattern' -)" = "^main\$" ] || { echo "FAIL: muad-dib must follow main"; exit 1; }

keys=$(echo "$built" | yq e 'select(.kind == "Secret" and .metadata.name == "muad-dib-secrets") | .stringData | keys | .[]' - | sort | paste -sd, -)
[ "$keys" = "ADMIN_API_KEY,DATABASE_URL" ] || { echo "FAIL: muad-dib-secrets must hold exactly ADMIN_API_KEY and DATABASE_URL"; exit 1; }
values=$(echo "$built" | yq e 'select(.kind == "Secret" and .metadata.name == "muad-dib-secrets") | .stringData | to_entries | .[].value' -)
[ -n "$values" ] || { echo "FAIL: muad-dib-secrets has no stringData entries"; exit 1; }
if echo "$values" | grep -qv '^ENC\['; then echo "FAIL: muad-dib-secrets must be fully SOPS encrypted"; exit 1; fi

echo "PASS"
