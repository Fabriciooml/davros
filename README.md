# davros

![Davros](docs/images/davros.jpg)

Named after Davros, the mad-scientist from Doctor Who (also known as the greatest show on earth). Davros created the Daleks, I create shitty systems that need constant attention and refuses to cooperate, so tomato tomato.

Homelab Kubernetes cluster: OpenTofu provisions the infrastructure, Flux
drives everything inside the cluster from this repo, SOPS/age keeps secrets
safe in a public repo.

## Stack

- **Proxmox VE** — the one physical host everything runs on.
- **k3s**, single node, running in a privileged LXC container on Proxmox.
- **Flux** — bootstrapped against this repo, reconciles
  everything under `kubernetes/` into the cluster.
- **SOPS + age** — encrypts secrets (`*.sops.yaml` files) before they're committed.
- **cert-manager** + Let's Encrypt — issues two wildcard certs:
  `*.local.mydomain` (LAN-only) and `*.mydomain` (public, via Cloudflare Tunnel).
- **Traefik** — ingress controller.
- **csi-driver-nfs** — dynamic PV provisioning against NFS exports.

## Repo layout

```
terraform/
  k3s-cluster/        # the LXC node itself + k3s install (see above)
  cloudflare/          # DNS records + tunnel ingress rules for public apps
  modules/
    public-app-ingress/ # reusable module: one app -> one DNS record + tunnel rule

kubernetes/
  flux-system/          # flux's own bootstrap manifests (gitops-managed after first bootstrap)
  infrastructure/        # HelmRepositories + HelmReleases (cert-manager, traefik, nfs-csi, monitoring)
  infrastructure-configs/ # chart-owned CRs that must come after the chart installs (ClusterIssuers, Certificates, StorageClasses, IngressRoutes, the sops-encrypted secrets)
  apps/                  # workload apps (empty so far)

scripts/
  proxmox-host/          # one-off setup scripts run directly on the Proxmox host
```

Every `kustomization.yaml` directory under `kubernetes/` has a matching
`tests/test.sh` (kubeconform + yq assertions) run by `make test`.

## Bootstrapping from scratch

```
make apply-cluster      # create the k3s LXC + install k3s (real, asks to confirm)
make kubeconfig          # merge the generated kubeconfig into ~/.kube/config
export GITHUB_TOKEN=...  # a github PAT with the `repo` scope, or put it in .env (see below)
make flux-bootstrap      # wire this repo to the cluster via flux (real, asks to confirm)
make sops-age-secret     # deliver the sops age key into flux-system so it can decrypt secrets
make apply-cloudflare    # DNS + tunnel ingress for public apps (real, asks to confirm)
```

Or just `make bootstrap`, which runs all of the above in order (still asks
to confirm at each real step).