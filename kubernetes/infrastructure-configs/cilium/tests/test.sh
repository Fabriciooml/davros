#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

built=$(kustomize build .)

echo "$built" | kubeconform -strict -ignore-missing-schemas -summary

pool=$(echo "$built" | yq e 'select(.kind == "CiliumLoadBalancerIPPool")' -)
[ -n "$pool" ] || { echo "FAIL: no CiliumLoadBalancerIPPool found"; exit 1; }
[ "$(echo "$pool" | yq e '.spec.blocks[0].start' -)" = "192.168.31.244" ] || { echo "FAIL: lb pool must start right after the vip"; exit 1; }
[ "$(echo "$pool" | yq e '.spec.blocks[0].stop' -)" = "192.168.31.246" ] || { echo "FAIL: lb pool must stop at .246"; exit 1; }

policy=$(echo "$built" | yq e 'select(.kind == "CiliumL2AnnouncementPolicy")' -)
[ -n "$policy" ] || { echo "FAIL: no CiliumL2AnnouncementPolicy found"; exit 1; }

echo "PASS"
