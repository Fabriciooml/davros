# Rebuild cluster as k3s-in-LXC (replacing Talos-in-KVM)

## Problem

The homelab's single Proxmox host (23GB RAM, 16 vCPU) is overcommitted.
Three Talos control-plane VMs alone commit ~9-10GB RSS (each a full VM
with its own duplicated OS/kernel), on top of ~7-8GB already running
in existing LXCs (docker stack, jellyfin, plex, pihole, npmplus,
cloudflared, vaultwarden) and a ~2.6GB Home Assistant VM. At idle this
leaves only ~3-4GB headroom.

Every host reboot (or any event that restarts the Talos VMs
simultaneously with everything else) throws the Kubernetes control
plane into a self-sustaining failure spiral: host memory pressure →
host kernel swaps pages belonging to the running Talos VMs themselves
(invisible to the guest) → etcd disk/memory operations stall →
leader-election timeouts and lease renewal failures across
etcd/apiserver/scheduler/controller-manager/HelmRelease controllers →
crashloops → more restarts → more pressure. This consumed most of a
session's real time with no config bug to fix — it's a structural
capacity problem, and it will only get worse as more apps are added to
the cluster.

Running a full HA (3-node) Talos control plane on a *single physical
host* also provides no real protection against hardware failure — it
only protects against a single VM crashing, a narrower benefit than
its resource cost justifies here.

## Decision

Replace the Talos-on-KVM cluster with a single-node k3s cluster
running inside one privileged LXC container. This eliminates the
etcd-clustering/leader-election failure mode entirely (no cluster to
elect a leader of) and removes the ×3 duplicated-OS-kernel overhead
that VMs impose, since an LXC container shares the host kernel
directly.

## Topology

- **One privileged LXC container** (Debian 12 base), running k3s
  server with the control plane and schedulable workloads combined —
  same "no separate worker tier" philosophy as the original Talos
  design, just on one node instead of three.
- **Static IP** assigned directly via the LXC's network config
  (`ip=<addr>/24,gw=<gateway>`) — no DHCP, no deterministic-MAC +
  Pi-hole-reservation dance that Talos needed, since Proxmox LXC
  containers take a static IP natively at creation time.
- **No kube-vip, no VIP.** Cluster endpoint is the container's static
  IP directly. `cluster_endpoint`/`k8sServiceHost` references update
  accordingly.
- **No etcd clustering, no multi-node leader election.** k3s on a
  single server node uses its embedded datastore without any
  clustering overhead.

## What stays the same

- `terraform/cloudflare/` — fully separate root module, zero changes.
  External apps (vault, butecos, ha, mealie, mapa) are routed by the
  Cloudflare tunnel directly to their own standalone LXC/VM IPs, not
  through the k8s cluster at all, so this rebuild has zero impact on
  anything currently serving real traffic.
- `kubernetes/flux-system/`, `kubernetes/infrastructure/`,
  `kubernetes/infrastructure-configs/`, `kubernetes/apps/` — all
  manifests are reused as-is. Cilium's `SYS_MODULE`-capability removal
  (from `helmrelease.yaml`) stays relevant: LXC containers cannot
  grant `CAP_SYS_MODULE` even when privileged, same restriction Talos
  had, just for a different underlying reason.
- SOPS/age setup, `.sops.yaml`, the sops-age secret delivery mechanism.
- Makefile's `confirm`-gated safety pattern for destructive targets.
- Cilium as the CNI (kept over k3s's built-in Flannel+ServiceLB) to
  reuse the already-built LB IP pool / L2 announcement policy work in
  `kubernetes/infrastructure-configs/cilium/`.

## What gets deleted

- `terraform/talos-cluster/` and `terraform/modules/talos-node/`
  (and their tests) — the entire Talos-provider-specific stack:
  `talos_machine_secrets`, `talos_machine_configuration_apply`,
  `talos_client_configuration`, the Image Factory schematic/ISO
  download logic, kube-vip/VIP CIDR math.

## What's new

- `terraform/k3s-cluster/` — single root module (no submodule needed
  at this scale):
  - `proxmox_virtual_environment_container` resource (bpg/proxmox
    provider, already in use for the VM side) — privileged, static IP,
    `features { mount = ["nfs"] }` enabled (Proxmox LXCs block NFS
    mounts by default — csi-driver-nfs needs this explicitly).
  - `proxmox_virtual_environment_download_file` to fetch the Debian 12
    LXC template automatically (same pattern as the existing Talos ISO
    download) — no manual template pre-download step.
  - A `null_resource` (SSH to the Proxmox host + `pct exec`) that runs
    the k3s install script (`curl -sfL https://get.k3s.io | sh -`) —
    idempotent, safe to rerun.
  - Kubeconfig extraction: read `/etc/rancher/k3s/k3s.yaml` from the
    container via `pct exec ... cat`, rewrite the server address from
    `127.0.0.1` to the container's static IP, write to a known local
    path.

## One-command bootstrap requirement

`make bootstrap` must take the homelab from zero to a fully running
cluster with no manual steps, and must be safe to rerun (idempotent at
every step) since a fresh rebuild is the expected recovery path rather
than node-level HA:

1. `tofu apply` in `terraform/k3s-cluster/` — provisions the LXC,
   downloads the template if missing, installs k3s.
2. Extract kubeconfig, rewrite server IP, write to the known path.
3. Check for `~/.config/sops/age/keys.txt` — create **only if
   missing** (never regenerate; regenerating breaks decryption of
   already-committed SOPS secrets).
4. Create the `sops-age` k8s secret in `flux-system`.
5. `flux bootstrap github ...` — already idempotent, safe to rerun
   against the same GitHub repo even on a from-scratch rebuild.

All of this chains into one Makefile target, replacing today's
multi-step manual bootstrap sequence (which is what made this
session's recovery so painful).

Note: Claude's own tool permissions block it from running `tofu
apply` or certain Proxmox permission-grant commands directly — that
constrains what Claude can execute in a session, not the Makefile
itself. The Makefile stays fully automated for the user; the user runs
`make bootstrap` themselves.

## Known risks / LXC-specific gotchas (validate during build, not blocking)

- **NFS mounts**: needs `features: mount=nfs` on the container
  resource or csi-driver-nfs mount attempts fail inside the LXC.
- **Cilium eBPF in LXC**: privileged LXC generally supports eBPF on a
  modern kernel (host is `6.17.13-1-pve`), but validate immediately
  after provisioning rather than assuming.
- **Apparmor**: Proxmox's privileged LXC still runs under an apparmor
  profile by default; may need `lxc.apparmor.profile: unconfined` set
  via the container's raw config if Cilium/k3s hit permission issues.
- **No rolling node replacement**: single node means no HA failover
  story if the LXC needs rebuilding — recovery goes through the same
  one-command bootstrap instead of node replacement. This is a
  different recovery model than 3-node HA would have given, accepted
  as part of this design given the "plug and play, rerun make
  bootstrap" goal.

## Migration / cutover sequence

No real workloads exist on the cluster today (`kubernetes/apps/` is
still an empty placeholder), so this is a clean swap, not a live
migration:

1. `tofu destroy` in `terraform/talos-cluster/` — removes the 3 Talos
   VMs, frees ~9-10GB immediately. Real, destructive — run by the user
   themselves, same as every other mutation this session.
2. Delete `terraform/talos-cluster/` and `terraform/modules/talos-node/`
   from the repo.
3. Build `terraform/k3s-cluster/` (TDD, same discipline as the rest of
   the repo: `tofu test` + mocked provider assertions before any real
   apply).
4. `tofu apply` → provision LXC, install k3s, validate the eBPF/NFS/
   apparmor gotchas.
5. Update Makefile's bootstrap chain for the new one-command flow.
6. Re-run `flux bootstrap` against the same GitHub repo —
   `kubernetes/infrastructure`, `infrastructure-configs`, `apps`
   Kustomizations reconcile against the new cluster unchanged.
