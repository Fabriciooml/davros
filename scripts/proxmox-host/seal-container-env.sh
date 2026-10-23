#!/usr/bin/env bash
# Build a SOPS-encrypted Kubernetes Secret from selected env vars of a
# container running in LXC 104, without ever printing the values.
set -euo pipefail

if [ "$#" -lt 5 ]; then
  echo "usage: $0 <container> <namespace> <secret-name> <out-file> <ENV_KEY>..." >&2
  exit 2
fi
container=$1
namespace=$2
name=$3
out=$4
shift 4
proxmox_host="${PROXMOX_HOST:-root@192.168.31.42}"

name_re='^[A-Za-z0-9_.-]+$'
key_re='^[A-Za-z_][A-Za-z0-9_]*$'
for value in "$container" "$namespace" "$name"; do
  if ! [[ $value =~ $name_re ]]; then
    echo "invalid container/namespace/name (allowed: A-Z a-z 0-9 _ . -): $value" >&2
    exit 2
  fi
done
for key in "$@"; do
  if ! [[ $key =~ $key_re ]]; then
    echo "invalid env key: $key" >&2
    exit 2
  fi
done

tmp=$(mktemp)
out_tmp="$out.tmp.$$"
trap 'rm -f "$tmp" "$out_tmp"' EXIT
chmod 600 "$tmp"

env_json=$(ssh "$proxmox_host" "pct exec 104 -- docker inspect $container --format '{{json .Config.Env}}'")

ENV_JSON="$env_json" python3 -I - "$name" "$namespace" "$@" > "$tmp" <<'PY'
import json
import os
import sys

name, namespace, *keys = sys.argv[1:]
env = dict(entry.split("=", 1) for entry in (json.loads(os.environ["ENV_JSON"]) or []))
missing = [key for key in keys if key not in env]
if missing:
    sys.exit("missing env keys in container: " + ", ".join(missing))
print("apiVersion: v1")
print("kind: Secret")
print("metadata:")
print("  name: %s" % name)
print("  namespace: %s" % namespace)
print("type: Opaque")
print("stringData:")
for key in keys:
    print("  %s: %s" % (key, json.dumps(env[key])))
PY

sops --encrypt --encrypted-regex '^(data|stringData)$' --filename-override "$out" --input-type yaml --output-type yaml "$tmp" > "$out_tmp"
mv "$out_tmp" "$out"
echo "wrote $out (keys: $*)"
