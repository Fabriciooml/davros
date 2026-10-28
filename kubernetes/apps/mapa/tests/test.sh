#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

built=$(kustomize build .)

echo "$built" | kubeconform -strict -ignore-missing-schemas -skip Secret -summary

for d in backend frontend; do
  dep=$(echo "$built" | yq e "select(.kind == \"Deployment\" and .metadata.name == \"$d\")" -)
  [ -n "$dep" ] || { echo "FAIL: no Deployment $d"; exit 1; }
  [ "$(echo "$dep" | yq e '.spec.template.spec.containers[0].imagePullPolicy' -)" = "Always" ] || { echo "FAIL: $d must pull Always"; exit 1; }
  [ "$(echo "$dep" | yq e '.spec.template.spec.enableServiceLinks' -)" = "false" ] || { echo "FAIL: $d must disable service-link env vars"; exit 1; }
  [ "$(echo "$dep" | yq e '.spec.progressDeadlineSeconds' -)" = "1200" ] || { echo "FAIL: $d progressDeadlineSeconds must be 1200"; exit 1; }
  # kustomize build strips YAML comments, and Flux reads the marker from the source file in git
  grep -Eq "^[[:space:]]+fabriciooml\.dev/image-digest: sha256:[0-9a-f]{64} # \{\"\\\$imagepolicy\": \"flux-system:mapa-$d:digest\"\}\$" "$d.yaml" || { echo "FAIL: $d digest marker missing"; exit 1; }
  pol=$(echo "$built" | yq e "select(.kind == \"ImagePolicy\" and .metadata.name == \"mapa-$d\")" -)
  [ "$(echo "$pol" | yq e '.spec.digestReflectionPolicy' -)" = "Always" ] || { echo "FAIL: mapa-$d policy must reflect the digest"; exit 1; }
  repo=$(echo "$built" | yq e "select(.kind == \"ImageRepository\" and .metadata.name == \"mapa-$d\")" -)
  [ "$(echo "$dep" | yq e '.spec.template.spec.containers[0].image' -)" = "$(echo "$repo" | yq e '.spec.image' -):main" ] || { echo "FAIL: $d image must be the mapa-$d ImageRepository image:main"; exit 1; }
  [ "$(echo "$pol" | yq e '.spec.imageRepositoryRef.name' -)" = "mapa-$d" ] || { echo "FAIL: mapa-$d policy must reference ImageRepository mapa-$d"; exit 1; }
  [ "$(echo "$pol" | yq e '.spec.filterTags.pattern' -)" = "^main\$" ] || { echo "FAIL: mapa-$d must follow main"; exit 1; }
done

be=$(echo "$built" | yq e 'select(.kind == "Deployment" and .metadata.name == "backend")' -)
[ "$(echo "$be" | yq e '.spec.strategy.type' -)" = "Recreate" ] || { echo "FAIL: backend RWO volume needs Recreate"; exit 1; }
[ "$(echo "$be" | yq e '.spec.template.spec.containers[0].env[] | select(.name == "DB_PATH") | .value' -)" = "/app/data/nosso_mapa.db" ] || { echo "FAIL: DB_PATH must match the imported file"; exit 1; }
[ "$(echo "$be" | yq e '.spec.template.spec.containers[0].env[] | select(.name == "GOOGLE_PLACES_API_KEY") | .valueFrom.secretKeyRef.name' -)" = "mapa-secrets" ] || { echo "FAIL: places key must come from the secret"; exit 1; }
[ "$(echo "$be" | yq e '.spec.template.spec.containers[0].env[] | select(.name == "GOOGLE_PLACES_API_KEY") | .valueFrom.secretKeyRef.key' -)" = "GOOGLE_PLACES_API_KEY" ] || { echo "FAIL: places key must reference GOOGLE_PLACES_API_KEY in the secret"; exit 1; }

fe=$(echo "$built" | yq e 'select(.kind == "Deployment" and .metadata.name == "frontend")' -)
[ "$(echo "$fe" | yq e '.spec.template.spec.containers[0].env[] | select(.name == "VITE_GOOGLE_MAPS_API_KEY") | .valueFrom.secretKeyRef.key' -)" = "GOOGLE_PLACES_API_KEY" ] || { echo "FAIL: frontend maps key must come from the secret at runtime"; exit 1; }

svc=$(echo "$built" | yq e 'select(.kind == "Service" and .metadata.name == "backend")' -)
[ "$(echo "$svc" | yq e '.spec.ports[0].port' -)" = "8000" ] || { echo "FAIL: nginx proxies to backend:8000"; exit 1; }

pvc=$(echo "$built" | yq e 'select(.kind == "PersistentVolumeClaim" and .metadata.name == "mapa-data")' -)
[ "$(echo "$pvc" | yq e '.spec.storageClassName' -)" = "local-path" ] || { echo "FAIL: data must be on local-path"; exit 1; }

route=$(echo "$built" | yq e 'select(.kind == "IngressRoute" and .metadata.name == "mapa")' -)
echo "$route" | grep -qF 'Host(`mapa.local.fabriciooml.dev`)' || { echo "FAIL: LAN host missing"; exit 1; }
echo "$route" | grep -qF 'Host(`mapa.fabriciooml.dev`)' || { echo "FAIL: public host missing"; exit 1; }

keys=$(echo "$built" | yq e 'select(.kind == "Secret" and .metadata.name == "mapa-secrets") | .stringData | keys | .[]' - | sort | paste -sd, -)
[ "$keys" = "GOOGLE_PLACES_API_KEY" ] || { echo "FAIL: mapa-secrets must hold exactly GOOGLE_PLACES_API_KEY"; exit 1; }
values=$(echo "$built" | yq e 'select(.kind == "Secret" and .metadata.name == "mapa-secrets") | .stringData | to_entries | .[].value' -)
[ -n "$values" ] || { echo "FAIL: mapa-secrets has no stringData entries"; exit 1; }
if echo "$values" | grep -qv '^ENC\['; then echo "FAIL: mapa-secrets must be fully SOPS encrypted"; exit 1; fi

echo "PASS"
