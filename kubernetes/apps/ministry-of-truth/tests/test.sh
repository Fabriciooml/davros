#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

built=$(kustomize build .)

echo "$built" | kubeconform -strict -ignore-missing-schemas -skip Secret -summary

dep=$(echo "$built" | yq e 'select(.kind == "Deployment" and .metadata.name == "ministry-of-truth")' -)
[ -n "$dep" ] || { echo "FAIL: no Deployment ministry-of-truth"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.strategy.type' -)" = "Recreate" ] || { echo "FAIL: RWO volume needs Recreate"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.replicas' -)" = "1" ] || { echo "FAIL: single replica (SQLite + RWO PVC)"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.template.spec.containers[0].image' -)" = "ghcr.io/fabriciooml/ministry_of_truth:main" ] || { echo "FAIL: image must follow :main"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.template.spec.containers[0].imagePullPolicy' -)" = "Always" ] || { echo "FAIL: must pull Always"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.template.spec.enableServiceLinks' -)" = "false" ] || { echo "FAIL: must disable service-link env vars"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.progressDeadlineSeconds' -)" = "1200" ] || { echo "FAIL: progressDeadlineSeconds must be 1200"; exit 1; }
# kustomize build strips trailing comments, and Flux reads the marker from the source file in git;
# it must sit on the same line as the digest value or the setter silently stops updating
grep -Eq '^[[:space:]]+fabriciooml\.dev/image-digest: sha256:[0-9a-f]{64} # \{"\$imagepolicy": "flux-system:ministry-of-truth:digest"\}$' deployment.yaml || { echo "FAIL: digest marker missing"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.template.spec.containers[0].env[] | select(.name == "TZ") | .value' -)" = "America/Sao_Paulo" ] || { echo "FAIL: TZ"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.template.spec.containers[0].env[] | select(.name == "DATA_DIR") | .value' -)" = "/data" ] || { echo "FAIL: DATA_DIR"; exit 1; }
for k in FERNET_KEY SESSION_SECRET SONARR_KEY RADARR_KEY; do
  [ "$(echo "$dep" | yq e ".spec.template.spec.containers[0].env[] | select(.name == \"$k\") | .valueFrom.secretKeyRef.name" -)" = "ministry-of-truth-secrets" ] || { echo "FAIL: $k must come from the secret"; exit 1; }
  [ "$(echo "$dep" | yq e ".spec.template.spec.containers[0].env[] | select(.name == \"$k\") | .valueFrom.secretKeyRef.key" -)" = "$k" ] || { echo "FAIL: $k must reference key $k"; exit 1; }
done
[ "$(echo "$dep" | yq e '.spec.template.spec.containers[0].readinessProbe.httpGet.path' -)" = "/healthz" ] || { echo "FAIL: readiness path"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.template.spec.containers[0].livenessProbe.httpGet.path' -)" = "/healthz" ] || { echo "FAIL: liveness path"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.template.spec.containers[0].volumeMounts[] | select(.name == "data") | .mountPath' -)" = "/data" ] || { echo "FAIL: data must mount at /data"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.template.spec.securityContext.fsGroup' -)" = "10001" ] || { echo "FAIL: fsGroup must match the image uid"; exit 1; }
for f in requests.cpu requests.memory limits.memory; do
  [ "$(echo "$dep" | yq e ".spec.template.spec.containers[0].resources.$f" -)" != "null" ] || { echo "FAIL: resources.$f missing"; exit 1; }
done

for p in readinessProbe livenessProbe; do
  t=$(echo "$dep" | yq e ".spec.template.spec.containers[0].$p.timeoutSeconds" -)
  [ "$t" != "null" ] && [ "$t" -ge 3 ] || { echo "FAIL: $p.timeoutSeconds must be >= 3 (feed parsing can stall the event loop)"; exit 1; }
done
[ "$(echo "$dep" | yq e '.spec.template.spec.containers[0].resources.requests.cpu' -)" = "25m" ] || { echo "FAIL: requests.cpu 25m"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.template.spec.containers[0].resources.requests.memory' -)" = "128Mi" ] || { echo "FAIL: requests.memory 128Mi"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.template.spec.containers[0].resources.limits.memory' -)" = "384Mi" ] || { echo "FAIL: limits.memory 384Mi"; exit 1; }

pvc=$(echo "$built" | yq e 'select(.kind == "PersistentVolumeClaim" and .metadata.name == "ministry-of-truth-data")' -)
[ "$(echo "$pvc" | yq e '.spec.storageClassName' -)" = "local-path" ] || { echo "FAIL: data must be on local-path"; exit 1; }
[ "$(echo "$dep" | yq e '.spec.template.spec.volumes[] | select(.name == "data") | .persistentVolumeClaim.claimName' -)" = "ministry-of-truth-data" ] || { echo "FAIL: deployment must mount the PVC"; exit 1; }

route=$(echo "$built" | yq e 'select(.kind == "IngressRoute" and .metadata.name == "ministry-of-truth")' -)
echo "$route" | grep -qF 'Host(`news.local.fabriciooml.dev`)' || { echo "FAIL: LAN host missing"; exit 1; }
[ "$(echo "$route" | grep -o 'Host(' | wc -l)" = "1" ] || { echo "FAIL: exactly one host, LAN-only"; exit 1; }
[ "$(echo "$route" | yq e '.spec.tls' -)" = "{}" ] || { echo "FAIL: tls must be {} (default TLSStore)"; exit 1; }

svc=$(echo "$built" | yq e 'select(.kind == "Service" and .metadata.name == "ministry-of-truth")' -)
[ "$(echo "$svc" | yq e '.spec.ports[0].targetPort' -)" = "8000" ] || { echo "FAIL: service must target 8000"; exit 1; }

pol=$(echo "$built" | yq e 'select(.kind == "ImagePolicy" and .metadata.name == "ministry-of-truth")' -)
[ "$(echo "$pol" | yq e '.spec.digestReflectionPolicy' -)" = "Always" ] || { echo "FAIL: policy must reflect the digest of the moving tag"; exit 1; }
[ "$(echo "$pol" | yq e '.spec.filterTags.pattern' -)" = "^main\$" ] || { echo "FAIL: must follow main"; exit 1; }
[ "$(echo "$pol" | yq e '.spec.imageRepositoryRef.name' -)" = "ministry-of-truth" ] || { echo "FAIL: policy must reference its ImageRepository"; exit 1; }
repo=$(echo "$built" | yq e 'select(.kind == "ImageRepository" and .metadata.name == "ministry-of-truth")' -)
[ "$(echo "$dep" | yq e '.spec.template.spec.containers[0].image' -)" = "$(echo "$repo" | yq e '.spec.image' -):main" ] || { echo "FAIL: deployment image must be the ImageRepository image:main"; exit 1; }

echo "$built" | yq e 'select(.kind == "Secret") | .metadata.name' - | grep -qx 'ministry-of-truth-secrets' || { echo "FAIL: secret missing"; exit 1; }
grep -q 'ENC\[AES256_GCM' secret.sops.yaml || { echo "FAIL: secret must be sops-encrypted"; exit 1; }

echo "PASS"
