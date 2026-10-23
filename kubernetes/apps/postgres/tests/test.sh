#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

built=$(kustomize build .)

echo "$built" | kubeconform -strict -ignore-missing-schemas -skip Secret -summary

pg=$(echo "$built" | yq e 'select(.kind == "Deployment" and .metadata.name == "postgres")' -)
[ -n "$pg" ] || { echo "FAIL: no Deployment postgres"; exit 1; }
[ "$(echo "$pg" | yq e '.spec.strategy.type' -)" = "Recreate" ] || { echo "FAIL: RWO volume needs Recreate"; exit 1; }
[ "$(echo "$pg" | yq e '.spec.progressDeadlineSeconds' -)" = "1200" ] || { echo "FAIL: postgres progressDeadlineSeconds must be 1200"; exit 1; }
for probe in readinessProbe livenessProbe; do
  [ "$(echo "$pg" | yq e ".spec.template.spec.containers[0].$probe.exec.command | join(\" \")" -)" = "pg_isready -h 127.0.0.1 -U root -d postgres" ] || { echo "FAIL: postgres $probe must use pg_isready over TCP (-h 127.0.0.1)"; exit 1; }
done
[ "$(echo "$pg" | yq e '.spec.replicas' -)" = "0" ] || { echo "FAIL: postgres must be committed at replicas 0"; exit 1; }
[ "$(echo "$pg" | yq e '.spec.template.spec.enableServiceLinks' -)" = "false" ] || { echo "FAIL: postgres must disable service-link env vars"; exit 1; }
case "$(echo "$pg" | yq e '.spec.template.spec.containers[0].image' -)" in
  postgres:16-alpine@sha256:721873c34ceb9f8d8fc265984940dc982404c105f19ad51be9fdc5970a6080ea) ;;
  *) echo "FAIL: postgres must stay on the running 16-alpine digest"; exit 1 ;;
esac
[ "$(echo "$pg" | yq e '.spec.template.spec.containers[0].env[] | select(.name == "POSTGRES_INITDB_ARGS") | .value' -)" = "--encoding=UTF-8 --locale=C" ] || { echo "FAIL: initdb args must match the old cluster"; exit 1; }
[ "$(echo "$pg" | yq e '.spec.template.spec.containers[0].env[] | select(.name == "POSTGRES_PASSWORD") | .valueFrom.secretKeyRef.name' -)" = "postgres-secrets" ] || { echo "FAIL: password from the secret"; exit 1; }

admin=$(echo "$built" | yq e 'select(.kind == "Deployment" and .metadata.name == "pgadmin")' -)
[ -n "$admin" ] || { echo "FAIL: no Deployment pgadmin"; exit 1; }
[ "$(echo "$admin" | yq e '.spec.template.spec.securityContext.runAsUser' -)" = "5050" ] || { echo "FAIL: pgadmin runs as 5050"; exit 1; }
[ "$(echo "$admin" | yq e '.spec.progressDeadlineSeconds' -)" = "1200" ] || { echo "FAIL: pgadmin progressDeadlineSeconds must be 1200"; exit 1; }
[ "$(echo "$admin" | yq e '.spec.replicas' -)" = "0" ] || { echo "FAIL: pgadmin must be committed at replicas 0"; exit 1; }
[ "$(echo "$admin" | yq e '.spec.template.spec.enableServiceLinks' -)" = "false" ] || { echo "FAIL: pgadmin must disable service-link env vars"; exit 1; }
[ "$(echo "$admin" | yq e '.spec.strategy.type' -)" = "Recreate" ] || { echo "FAIL: pgadmin RWO volume needs Recreate"; exit 1; }
case "$(echo "$admin" | yq e '.spec.template.spec.containers[0].image' -)" in
  dpage/pgadmin4@sha256:c332c5f6dfba995d9ebc4af261d93506d6876085d712eaaa3defc8dd1a3f26de) ;;
  *) echo "FAIL: pgadmin must be pinned by digest"; exit 1 ;;
esac

for pvc in postgres-data pgadmin-data; do
  [ "$(echo "$built" | yq e "select(.kind == \"PersistentVolumeClaim\" and .metadata.name == \"$pvc\") | .spec.storageClassName" -)" = "local-path" ] || { echo "FAIL: $pvc must be on local-path"; exit 1; }
done

[ "$(echo "$built" | yq e 'select(.kind == "Service" and .metadata.name == "postgres-lan") | .spec.type' -)" = "LoadBalancer" ] || { echo "FAIL: postgres-lan must be a LoadBalancer"; exit 1; }
echo "$built" | yq e 'select(.kind == "IngressRoute") | .spec.routes[0].match' - | grep -q 'pgadmin.local.fabriciooml.dev' || { echo "FAIL: pgadmin host missing"; exit 1; }

keys_of() {
  echo "$built" | yq e "select(.kind == \"Secret\" and .metadata.name == \"$1\") | .stringData | keys | .[]" - | sort | paste -sd, -
}
[ "$(keys_of postgres-secrets)" = "POSTGRES_PASSWORD" ] || { echo "FAIL: postgres-secrets must hold exactly POSTGRES_PASSWORD"; exit 1; }
[ "$(keys_of pgadmin-secrets)" = "PGADMIN_DEFAULT_EMAIL,PGADMIN_DEFAULT_PASSWORD" ] || { echo "FAIL: pgadmin-secrets must hold exactly PGADMIN_DEFAULT_EMAIL and PGADMIN_DEFAULT_PASSWORD"; exit 1; }

for s in postgres-secrets pgadmin-secrets; do
  values=$(echo "$built" | yq e "select(.kind == \"Secret\" and .metadata.name == \"$s\") | .stringData | to_entries | .[].value" -)
  [ -n "$values" ] || { echo "FAIL: $s has no stringData entries"; exit 1; }
  if echo "$values" | grep -qv '^ENC\['; then echo "FAIL: $s must be fully SOPS encrypted"; exit 1; fi
done

echo "PASS"
