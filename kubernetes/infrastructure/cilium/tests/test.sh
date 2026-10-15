#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

built=$(kustomize build .)

echo "$built" | kubeconform -strict -ignore-missing-schemas -summary

helmrelease=$(echo "$built" | yq e 'select(.kind == "HelmRelease")' -)
[ -n "$helmrelease" ] || { echo "FAIL: no HelmRelease found"; exit 1; }
[ "$(echo "$helmrelease" | yq e '.spec.chart.spec.chart' -)" = "cilium" ] || { echo "FAIL: helmrelease must install the cilium chart"; exit 1; }
[ "$(echo "$helmrelease" | yq e '.spec.values.kubeProxyReplacement' -)" = "true" ] || { echo "FAIL: kubeProxyReplacement must be true, talos' kube-proxy is disabled"; exit 1; }
[ "$(echo "$helmrelease" | yq e '.spec.values.k8sServiceHost' -)" = "192.168.31.243" ] || { echo "FAIL: k8sServiceHost must be the kube-vip VIP"; exit 1; }
[ "$(echo "$helmrelease" | yq e '.spec.values.k8sServicePort' -)" = "6443" ] || { echo "FAIL: k8sServicePort must be 6443"; exit 1; }
[ "$(echo "$helmrelease" | yq e '.spec.values.l2announcements.enabled' -)" = "true" ] || { echo "FAIL: l2announcements must be enabled for the loadbalancer pool to work"; exit 1; }

agent_caps=$(echo "$helmrelease" | yq e '.spec.values.securityContext.capabilities.ciliumAgent | join(",")' -)
case ",$agent_caps," in
  *,"SYS_MODULE",*) echo "FAIL: ciliumAgent capabilities must not request SYS_MODULE, talos has no loadable kernel module support at all and refuses to grant it"; exit 1 ;;
esac
clean_caps=$(echo "$helmrelease" | yq e '.spec.values.securityContext.capabilities.cleanCiliumState | join(",")' -)
case ",$clean_caps," in
  *,"SYS_MODULE",*) echo "FAIL: cleanCiliumState capabilities must not request SYS_MODULE, talos has no loadable kernel module support at all and refuses to grant it"; exit 1 ;;
esac

pool=$(echo "$built" | yq e 'select(.kind == "CiliumLoadBalancerIPPool")' -)
[ -n "$pool" ] || { echo "FAIL: no CiliumLoadBalancerIPPool found"; exit 1; }
[ "$(echo "$pool" | yq e '.spec.blocks[0].start' -)" = "192.168.31.244" ] || { echo "FAIL: lb pool must start right after the vip"; exit 1; }
[ "$(echo "$pool" | yq e '.spec.blocks[0].stop' -)" = "192.168.31.246" ] || { echo "FAIL: lb pool must stop at .246"; exit 1; }

policy=$(echo "$built" | yq e 'select(.kind == "CiliumL2AnnouncementPolicy")' -)
[ -n "$policy" ] || { echo "FAIL: no CiliumL2AnnouncementPolicy found"; exit 1; }

echo "PASS"
