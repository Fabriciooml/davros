#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

built=$(kustomize build .)

echo "$built" | kubeconform -strict -ignore-missing-schemas -skip Secret -summary

fail() { echo "FAIL: $1"; exit 1; }
dep() { echo "$built" | yq e "select(.kind == \"Deployment\" and .metadata.name == \"$1\")" -; }

PG='pgvector/pgvector:pg16@sha256:484e838076e04939d27d3e176e91c86eea96236126023be8d3059761122e579f'
REDIS='redis:8-alpine@sha256:5af80107c1eeecb484a2269b80a26d12bfa6521787da4663bd9f19f60a163483'

# every Deployment: Recreate, 1 replica, no service links, digest-pinned images
for d in db redis backend celery-worker celery-beat frontend; do
  x=$(dep "$d"); [ -n "$x" ] || fail "no Deployment $d"
  [ "$(echo "$x" | yq e '.metadata.namespace' -)" = "securo" ] || fail "$d must be in namespace securo"
  [ "$(echo "$x" | yq e '.spec.strategy.type' -)" = "Recreate" ] || fail "$d needs Recreate"
  [ "$(echo "$x" | yq e '.spec.replicas' -)" = "1" ] || fail "$d must have 1 replica"
  [ "$(echo "$x" | yq e '.spec.template.spec.enableServiceLinks' -)" = "false" ] || fail "$d must disable service links"
  imgs=$(echo "$x" | yq e '(.spec.template.spec.containers[].image, .spec.template.spec.initContainers[].image) | select(. != null)' -)
  [ -n "$imgs" ] || fail "$d has no images found"
  for img in $imgs; do
    case "$img" in *@sha256:*) ;; *) fail "$d image $img not digest-pinned" ;; esac
    case "$img" in *:latest*) fail "$d image $img uses :latest" ;; esac
  done
done

# db
db=$(dep db)
[ "$(echo "$db" | yq e '.spec.template.spec.containers[0].image' -)" = "$PG" ] || fail "db image must be the pinned pgvector"
[ "$(echo "$db" | yq e '.spec.template.spec.containers[0].env[] | select(.name == "POSTGRES_DB") | .value' -)" = "securo" ] || fail "POSTGRES_DB must be securo"
[ "$(echo "$db" | yq e '.spec.template.spec.containers[0].env[] | select(.name == "POSTGRES_PASSWORD") | .valueFrom.secretKeyRef.name' -)" = "securo-secrets" ] || fail "db password from securo-secrets"
[ "$(echo "$db" | yq e '.spec.template.spec.volumes[] | select(.name == "data") | .persistentVolumeClaim.claimName' -)" = "securo-db" ] || fail "db data PVC securo-db"
[ "$(echo "$db" | yq e '.spec.template.spec.containers[0].readinessProbe.exec.command | join(" ")' -)" = "pg_isready -h 127.0.0.1 -U postgres -d securo" ] || fail "db readiness must be pg_isready over TCP"

# redis
[ "$(dep redis | yq e '.spec.template.spec.containers[0].image' -)" = "$REDIS" ] || fail "redis image must be the pinned one"

# services
for s in "db 5432" "redis 6379"; do
  set -- $s
  svc=$(echo "$built" | yq e "select(.kind == \"Service\" and .metadata.name == \"$1\")" -)
  [ "$(echo "$svc" | yq e '.spec.ports[0].port' -)" = "$2" ] || fail "Service $1 must expose $2"
  [ "$(echo "$svc" | yq e '.spec.type // "ClusterIP"' -)" = "ClusterIP" ] || fail "Service $1 must be ClusterIP"
done

# pvcs
for n in securo-db securo-attachments securo-backups; do
  pvc=$(echo "$built" | yq e "select(.kind == \"PersistentVolumeClaim\" and .metadata.name == \"$n\")" -)
  [ "$(echo "$pvc" | yq e '.spec.storageClassName' -)" = "local-path" ] || fail "$n must be on local-path"
done

# secrets: encrypted, right keys
f=securo-secrets.sops.yaml
grep -q '^sops:' "$f" || fail "$f must be sops-encrypted"
grep -qF 'encrypted_regex: ^(data|stringData)$' "$f" || fail "$f must encrypt only data/stringData (Flux needs plaintext kind/metadata)"
[ "$(echo "$built" | yq e 'select(.kind == "Secret" and .metadata.name == "securo-secrets") | .metadata.namespace' -)" = "securo" ] || fail "securo-secrets must be a plaintext-metadata Secret in namespace securo"
for k in POSTGRES_PASSWORD SECRET_KEY PLUGGY_CLIENT_ID PLUGGY_CLIENT_SECRET; do
  grep -qE "^[[:space:]]+$k: ENC\[" "$f" || fail "$f missing encrypted key $k"
done

# config
cm=$(echo "$built" | yq e 'select(.kind == "ConfigMap" and .metadata.name == "securo-config")' -)
for kv in DEBUG=false AGENTS_ENABLED=false PLUGINS_ENABLED=false OIDC_ENABLED=false SIMPLEFIN_ENABLED=false FRONTEND_URL=https://securo.local.fabriciooml.dev TRUSTED_PROXY_HOPS=2; do
  [ "$(echo "$cm" | yq e ".data.${kv%%=*}" -)" = "${kv#*=}" ] || fail "securo-config ${kv%%=*} must be ${kv#*=}"
done

BACKEND='ghcr.io/securo-finance/securo-backend:0.22.0@sha256:b993682d9d99079695e1009ee3c95dc5190f46ef7416d2bf0968baa4d619610e'

be=$(dep backend)
[ "$(echo "$be" | yq e '.spec.template.spec.containers[0].image' -)" = "$BACKEND" ] || fail "backend image pin"
[ "$(echo "$be" | yq e '.spec.template.spec.initContainers[0].image' -)" = "$BACKEND" ] || fail "migrate init image pin"
[ "$(echo "$be" | yq e '.spec.template.spec.initContainers[0].command | join(" ")' -)" = "alembic upgrade head" ] || fail "init container must run alembic upgrade head"
[ "$(echo "$be" | yq e '.spec.template.spec.containers[0].readinessProbe.httpGet.path' -)" = "/api/health" ] || fail "backend probe /api/health"
[ "$(echo "$be" | yq e '.spec.template.spec.containers[0].command | join(" ")' -)" = "uvicorn app.main:app --host 0.0.0.0 --port 8000" ] || fail "backend command"

for d in backend celery-worker celery-beat; do
  x=$(dep "$d")
  c='.spec.template.spec.containers[0]'
  echo "$x" | yq e "$c.envFrom[].configMapRef.name" - | grep -qx securo-config || fail "$d must envFrom securo-config"
  for k in POSTGRES_PASSWORD SECRET_KEY PLUGGY_CLIENT_ID PLUGGY_CLIENT_SECRET; do
    [ "$(echo "$x" | yq e "$c.env[] | select(.name == \"$k\") | .valueFrom.secretKeyRef.name" -)" = "securo-secrets" ] || fail "$d env $k from securo-secrets"
  done
  [ "$(echo "$x" | yq e "$c.env[] | select(.name == \"DATABASE_URL\") | .value" -)" = 'postgresql+asyncpg://postgres:$(POSTGRES_PASSWORD)@db:5432/securo' ] || fail "$d DATABASE_URL"
  [ "$(echo "$x" | yq e "$c.image" -)" = "$BACKEND" ] || fail "$d image pin"
  [ "$(echo "$x" | yq e '.spec.template.spec.securityContext | has("runAsUser")' -)" = "false" ] || fail "$d must not set runAsUser (image runs as root)"
  [ "$(echo "$x" | yq e '.spec.template.spec.volumes[] | select(.name == "attachments") | .persistentVolumeClaim.claimName' -)" = "securo-attachments" ] || fail "$d attachments PVC"
  [ "$(echo "$x" | yq e '.spec.template.spec.volumes[] | select(.name == "backups") | .persistentVolumeClaim.claimName' -)" = "securo-backups" ] || fail "$d backups PVC"
done
for d in celery-worker celery-beat; do
  x=$(dep "$d")
  [ "$(echo "$x" | yq e '.spec.template.spec.initContainers[0].command | join(" ")' -)" != "" ] || fail "$d needs a schema-wait init container"
  echo "$x" | yq e '.spec.template.spec.initContainers[0].command | join(" ")' - | grep -q 'alembic current --check-heads' || fail "$d init must wait on alembic current --check-heads"
done
[ "$(dep celery-worker | yq e '.spec.template.spec.containers[0].command | join(" ")' -)" = "celery -A app.worker worker --loglevel=info --concurrency=2" ] || fail "worker command"
[ "$(dep celery-beat | yq e '.spec.template.spec.containers[0].command | join(" ")' -)" = "celery -A app.worker beat --loglevel=info" ] || fail "beat command"
[ "$(echo "$built" | yq e 'select(.kind == "Service" and .metadata.name == "backend") | .spec.ports[0].port' -)" = "8000" ] || fail "Service backend 8000"

FRONTEND='ghcr.io/securo-finance/securo-frontend:0.22.0@sha256:5ecbe79a212c5f1a92c83e80aff5419a2b8942e9cda42f5278142a618caf5316'
fe=$(dep frontend)
[ "$(echo "$fe" | yq e '.spec.template.spec.containers[0].image' -)" = "$FRONTEND" ] || fail "frontend image pin"
[ "$(echo "$fe" | yq e '.spec.template.spec.containers[0].env[] | select(.name == "BACKEND_URL") | .value' -)" = "http://backend.securo.svc.cluster.local:8000" ] || fail "frontend BACKEND_URL must be the FQDN (nginx resolver ignores search domains)"
[ "$(echo "$fe" | yq e '.spec.template.spec.containers[0].readinessProbe.httpGet.port' -)" = "8080" ] || fail "frontend probe 8080"
[ "$(echo "$built" | yq e 'select(.kind == "Service" and .metadata.name == "frontend") | .spec.ports[0].port' -)" = "8080" ] || fail "Service frontend 8080"
[ -z "$(echo "$built" | yq e 'select(.kind == "Service" and .spec.type == "LoadBalancer")' -)" ] || fail "no LoadBalancer Services (LAN-only via Traefik)"

route=$(echo "$built" | yq e 'select(.kind == "IngressRoute" and .metadata.name == "securo")' -)
[ "$(echo "$route" | yq e '.metadata.namespace' -)" = "securo" ] || fail "route namespace"
[ "$(echo "$route" | yq e '.spec.routes | length' -)" = "1" ] || fail "route must have exactly one rule"
[ "$(echo "$route" | yq e '.spec.routes[].match' -)" = 'Host(`securo.local.fabriciooml.dev`)' ] || fail "route must match only the LAN host"
echo "$route" | grep -qF 'securo.fabriciooml.dev' && fail "no public host"
[ "$(echo "$route" | yq e '.spec.routes[0].services[0].name' -)" = "frontend" ] || fail "route -> frontend"
[ "$(echo "$route" | yq e '.spec.routes[0].services[0].port' -)" = "8080" ] || fail "route port 8080"
[ "$(echo "$route" | yq e '.spec.tls | has("secretName")' -)" = "false" ] || fail "route must use the default TLSStore"

echo "PASS"
