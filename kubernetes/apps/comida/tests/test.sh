#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

built=$(kustomize build .)

echo "$built" | kubeconform -strict -ignore-missing-schemas -skip Secret -summary

dep=$(echo "$built" | yq e 'select(.kind == "Deployment" and .metadata.name == "comida")' -)
[ -n "$dep" ] || { echo "FAIL: no Deployment comida"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.strategy.type' -)" = "Recreate" ] || { echo "FAIL: RWO volume needs Recreate"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.template.spec.containers[0].image' -)" = "ghcr.io/fabriciooml/comida_di_buteco_tracker:main" ] || { echo "FAIL: image must follow :main"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.template.spec.containers[0].imagePullPolicy' -)" = "Always" ] || { echo "FAIL: must pull Always"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.template.spec.enableServiceLinks' -)" = "false" ] || { echo "FAIL: comida must disable service-link env vars"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.progressDeadlineSeconds' -)" = "1200" ] || { echo "FAIL: comida progressDeadlineSeconds must be 1200"; exit 1; }
# kustomize build strips trailing comments, and Flux reads the marker from the source file in git;
# it must sit on the same line as the digest value or the setter silently stops updating
grep -Eq '^[[:space:]]+fabriciooml\.dev/image-digest: sha256:[0-9a-f]{64} # \{"\$imagepolicy": "flux-system:comida:digest"\}$' deployment.yaml || { echo "FAIL: digest marker missing"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.template.spec.containers[0].env[] | select(.name == "DB_PATH") | .value' -)" = "/app/data/butecos.db" ] || { echo "FAIL: DB_PATH must match the imported file"; exit 1; }

pvc=$(echo "$built" | yq e 'select(.kind == "PersistentVolumeClaim" and .metadata.name == "comida-data")' -)
[ "$(echo "$pvc" | yq e '.spec.storageClassName' -)" = "local-path" ] || { echo "FAIL: data must be on local-path"; exit 1; }

route=$(echo "$built" | yq e 'select(.kind == "IngressRoute" and .metadata.name == "comida")' -)
echo "$route" | grep -qF 'Host(`comida.local.fabriciooml.dev`)' || { echo "FAIL: LAN host missing"; exit 1; }
echo "$route" | grep -qF 'Host(`butecos.fabriciooml.dev`)' || { echo "FAIL: public host missing"; exit 1; }

pol=$(echo "$built" | yq e 'select(.kind == "ImagePolicy" and .metadata.name == "comida")' -)
[ "$(echo "$pol" | yq e '.spec.digestReflectionPolicy' -)" = "Always" ] || { echo "FAIL: policy must reflect the digest of the moving tag"; exit 1; }

repo=$(echo "$built" | yq e 'select(.kind == "ImageRepository" and .metadata.name == "comida")' -)
[ "$(echo "$dep" | yq e '.spec.template.spec.containers[0].image' -)" = "$(echo "$repo" | yq e '.spec.image' -):main" ] || { echo "FAIL: comida image must be the comida ImageRepository image:main"; exit 1; }
[ "$(echo "$pol" | yq e '.spec.imageRepositoryRef.name' -)" = "comida" ] || { echo "FAIL: comida policy must reference ImageRepository comida"; exit 1; }
[ "$(echo "$pol" | yq e '.spec.filterTags.pattern' -)" = "^main\$" ] || { echo "FAIL: comida must follow main"; exit 1; }

echo "PASS"
