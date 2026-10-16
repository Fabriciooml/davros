#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

fixture='apiVersion: v1
clusters:
- cluster:
    server: https://127.0.0.1:6443
  name: default
kind: Config
'

output=$(echo "$fixture" | ./scripts/rewrite-kubeconfig-server.sh "192.168.31.240")

echo "$output" | grep -q "https://192.168.31.240:6443" || { echo "FAIL: server address was not rewritten to the new ip"; exit 1; }
echo "$output" | grep -q "127.0.0.1" && { echo "FAIL: old 127.0.0.1 address must not remain"; exit 1; }

echo "PASS"
