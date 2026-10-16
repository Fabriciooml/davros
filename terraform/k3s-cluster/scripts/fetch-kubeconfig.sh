#!/usr/bin/env bash
set -euo pipefail

query=$(cat)
proxmox_host=$(echo "$query" | python3 -c 'import json,sys; print(json.load(sys.stdin)["proxmox_host"])')
vm_id=$(echo "$query" | python3 -c 'import json,sys; print(json.load(sys.stdin)["vm_id"])')
node_ip=$(echo "$query" | python3 -c 'import json,sys; print(json.load(sys.stdin)["node_ip"])')

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

kubeconfig=$(ssh "root@${proxmox_host}" "pct exec ${vm_id} -- cat /etc/rancher/k3s/k3s.yaml" \
  | "${script_dir}/rewrite-kubeconfig-server.sh" "${node_ip}")

kubeconfig_b64=$(echo "$kubeconfig" | base64 -w0)

python3 -c "import json; print(json.dumps({'kubeconfig_b64': '${kubeconfig_b64}'}))"
