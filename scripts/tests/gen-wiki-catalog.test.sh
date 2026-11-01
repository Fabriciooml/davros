#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
gen="$root/scripts/gen-wiki-catalog.py"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

# ---- fixture ----
apps="$tmp/apps"
mkdir -p "$apps/alpha" "$apps/beta" "$apps/nowork"

cat > "$apps/alpha/deployment.yaml" <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: alpha
  namespace: demo
spec:
  template:
    spec:
      containers:
        - name: alpha
          image: example/alpha:1.2@sha256:abc123
YAML
cat > "$apps/alpha/pvc.yaml" <<'YAML'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: alpha-config
  namespace: demo
spec:
  resources:
    requests:
      storage: 2Gi
YAML
cat > "$apps/alpha/ingressroute.yaml" <<'YAML'
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: alpha
  namespace: demo
spec:
  routes:
    - match: Host(`alpha.local.fabriciooml.dev`) || Host(`alpha.fabriciooml.dev`)
      kind: Rule
YAML
# a sops file that looks like a workload: if the generator opens it, the canary leaks
cat > "$apps/alpha/leak.sops.yaml" <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: leak
  namespace: demo
spec:
  template:
    spec:
      containers:
        - name: leak
          image: canary/leak:1
YAML
cat > "$apps/alpha/kustomization.yaml" <<'YAML'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - deployment.yaml
YAML

cat > "$apps/beta/workload.yaml" <<'YAML'
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: beta
  namespace: other
spec:
  template:
    spec:
      containers:
        - name: beta
          image: example/beta@sha256:def456
        - name: beta-sidecar
          image: example/beta:2.0
---
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: beta
  namespace: other
spec:
  routes:
    - match: Host(`beta.local.fabriciooml.dev`)
      kind: Rule
YAML

cat > "$apps/nowork/namespace.yaml" <<'YAML'
apiVersion: v1
kind: Namespace
metadata:
  name: nowork
YAML

cat > "$tmp/notes.json" <<'JSON'
{"alpha": {"description": "Alpha thing.", "category": "tools"}}
JSON

out="$tmp/out/apps.json"
python3 "$gen" --apps-dir "$apps" --notes "$tmp/notes.json" --out "$out" >/dev/null 2>"$tmp/stderr" \
  || fail "generator exited non-zero"

[ -f "$out" ] || fail "apps.json not written"
[ -f "$tmp/out/apps.js" ] || fail "apps.js not written"
head -c 18 "$tmp/out/apps.js" | grep -qF 'window.WIKI_APPS =' || fail "apps.js must start with window.WIKI_APPS ="

grep -q 'beta' "$tmp/stderr" || fail "missing-notes warning for beta not printed"

python3 - "$out" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
apps = {a["name"]: a for a in data["apps"]}
assert list(apps) == ["alpha", "beta"], list(apps)

a = apps["alpha"]
assert a["namespace"] == "demo", a
assert a["category"] == "tools" and a["description"] == "Alpha thing.", a
assert a["images"] == [{"repo": "example/alpha", "tag": "1.2", "pinned": True}], a["images"]
assert a["hosts"] == [
    {"host": "alpha.<domain>", "visibility": "public"},
    {"host": "alpha.local.<domain>", "visibility": "lan"},
], a["hosts"]
assert a["storage"] == [{"name": "alpha-config", "size": "2Gi"}], a["storage"]
assert a["public"] is True and a["lan"] is True and a["stateful"] is True, a

b = apps["beta"]
assert b["namespace"] == "other", b
assert b["images"] == [
    {"repo": "example/beta", "tag": "2.0", "pinned": False},
    {"repo": "example/beta", "tag": "digest", "pinned": True},
], b["images"]
assert b["hosts"] == [{"host": "beta.local.<domain>", "visibility": "lan"}], b["hosts"]
assert b["public"] is False and b["lan"] is True and b["stateful"] is False, b
assert b["category"] == "uncategorised", b
assert b["description"] == "No description yet.", b
PY

if grep -rq 'canary' "$tmp/out"; then fail "a *.sops.yaml file was read"; fi
if grep -rq 'fabriciooml.dev' "$tmp/out"; then fail "real domain leaked into output"; fi

python3 "$gen" --apps-dir "$apps" --notes "$tmp/notes.json" --out "$tmp/out2/apps.json" >/dev/null 2>&1
cmp -s "$out" "$tmp/out2/apps.json" || fail "output not stable across runs"

# leak guard: real domain in notes must abort the run and write nothing
cat > "$tmp/leaknotes.json" <<'JSON'
{"alpha": {"description": "see alpha.fabriciooml.dev", "category": "tools"}}
JSON
if python3 "$gen" --apps-dir "$apps" --notes "$tmp/leaknotes.json" --out "$tmp/leakout/apps.json" >/dev/null 2>"$tmp/leak-stderr"; then
  fail "generator should exit non-zero when the real domain is in the output"
fi
[ ! -e "$tmp/leakout/apps.json" ] || fail "output written despite domain leak"
grep -q 'domain' "$tmp/leak-stderr" || fail "leak error message must mention the domain"

# same repo with several tags must not depend on hash ordering
for seed in 1 2 3 4 5 6 7 8; do
  PYTHONHASHSEED=$seed python3 "$gen" --apps-dir "$apps" --notes "$tmp/notes.json" \
    --out "$tmp/seed$seed/apps.json" >/dev/null 2>&1
  cmp -s "$out" "$tmp/seed$seed/apps.json" || fail "output depends on PYTHONHASHSEED=$seed"
done

# ---- real repo ----
real_out="$tmp/real/apps.json"
python3 "$gen" --out "$real_out" >/dev/null 2>"$tmp/real-stderr" || fail "generator failed on real repo"
if [ -s "$tmp/real-stderr" ]; then
  cat "$tmp/real-stderr" >&2
  fail "real apps missing from docs/wiki/data/app-notes.json (warnings above)"
fi
if grep -rq 'fabriciooml.dev' "$tmp/real"; then fail "real domain leaked into real-repo output"; fi

expected=""
for d in "$root"/kubernetes/apps/*/; do
  n="$(basename "$d")"
  if grep -lEs '^kind: (Deployment|StatefulSet|DaemonSet|CronJob)' "$d"*.yaml 2>/dev/null | grep -v '\.sops\.yaml$' | grep -q .; then
    expected="$expected $n"
  fi
done
actual="$(python3 -c "import json,sys;print(' '.join(a['name'] for a in json.load(open(sys.argv[1]))['apps']))" "$real_out")"
[ "$(echo $expected)" = "$actual" ] || fail "app set mismatch: expected [$(echo $expected)] got [$actual]"

echo "PASS"
