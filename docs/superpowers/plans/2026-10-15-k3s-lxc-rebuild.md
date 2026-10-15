# k3s-in-LXC Cluster Rebuild Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the 3-node Talos-on-KVM cluster with a single-node k3s cluster running in one privileged Proxmox LXC container, eliminating the host memory overcommit and etcd-leader-election failure mode this session hit repeatedly, while keeping every Flux/Cilium/cert-manager manifest already built reusable unchanged.

**Architecture:** One `proxmox_virtual_environment_container` (Debian 12, privileged, static IP, `features.mount = ["nfs"]`) replaces three `proxmox_virtual_environment_vm` Talos nodes. k3s is installed via SSH + `pct exec` from a `null_resource` provisioner (runs only on real `apply`, never during `tofu test`'s `command = plan` runs). Kubeconfig is fetched the same way via a `data "external"` source, server address rewritten from `127.0.0.1` to the container's real IP, and written to a local file Terraform tracks as an output. No kube-vip, no VIP, no etcd clustering.

**Tech Stack:** OpenTofu, bpg/proxmox provider (`~> 0.66`, already in use), hashicorp/null (`~> 3.2`), hashicorp/external (`~> 2.3`), hashicorp/local (`~> 2.5`), k3s, bash.

**Spec:** `docs/superpowers/specs/2026-10-15-k3s-lxc-rebuild-design.md`

## Global Constraints

- `required_version >= 1.7.0` (matches every other root/module in this repo).
- Every new provider version is pinned with `~>` (minor-floor), matching existing convention — never unpinned.
- Every `tofu test` run in this module uses `command = plan`, never `command = apply`, for any run that touches the container resource, the `null_resource` k3s-install, or the `data "external"` kubeconfig fetch — real SSH commands must never execute during `make test`. (`command = apply` is only acceptable for a pure in-memory test fixture with no provisioners, as the existing `tests/setup` pattern already does for `talos_machine_secrets`.)
- Every Makefile target this plan touches keeps the existing `confirm`-gated pattern for destructive/real-infra actions — never add `-auto-approve` anywhere.
- Every step must be idempotent: rerunning `make bootstrap` from a partially-completed or fully-fresh state must not error or duplicate anything.
- `terraform/cloudflare/` is never touched by any task in this plan.
- `kubernetes/flux-system/`, `kubernetes/infrastructure/`, `kubernetes/infrastructure-configs/`, `kubernetes/apps/` manifests are reused as-is except the one `k8sServiceHost` value change called out explicitly in Task 8 — no other manifest content changes.

---

## Task 1: Tear down the existing Talos cluster and delete its Terraform code

**Files:**
- Delete: `terraform/talos-cluster/` (entire directory, including `terraform.tfstate`, `terraform.tfstate.backup`, `terraform.tfvars`)
- Delete: `terraform/modules/talos-node/` (entire directory)

This is an operational/destructive task, not a code-test cycle — there is nothing to unit test about destroying VMs. The verification step below is the test.

- [ ] **Step 1: Destroy the real Talos VMs**

Run (you, the user, run this yourself — it is destructive and irreversible):

```bash
cd terraform/talos-cluster
tofu destroy
```

Confirm the prompt, then verify all 3 VMs are gone:

```bash
ssh root@192.168.31.42 'qm list | grep talos'
```

Expected: no output (no VMs named `talos-*` remain).

- [ ] **Step 2: Delete the Talos-specific Terraform code**

```bash
git rm -r terraform/talos-cluster terraform/modules/talos-node
```

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "chore: remove talos-on-kvm cluster, destroyed in favor of k3s-in-lxc"
```

---

## Task 2: Scaffold the k3s-cluster root module (provider wiring only)

**Files:**
- Create: `terraform/k3s-cluster/versions.tf`
- Create: `terraform/k3s-cluster/providers.tf`
- Create: `terraform/k3s-cluster/variables.tf`
- Create: `terraform/k3s-cluster/terraform.tfvars.example`
- Test: `terraform/k3s-cluster/tests/k3s_cluster.tftest.hcl`

**Interfaces:**
- Produces: variables `proxmox_api_endpoint` (string), `proxmox_api_token` (string, sensitive), `proxmox_host` (string — plain SSH-reachable IP, distinct from the HTTPS API endpoint), `proxmox_node` (string), `datastore_id` (string), `vm_id` (number), `node_ip` (string, bare IPv4 e.g. `"192.168.31.240"`), `gateway` (string), `cpu_cores` (number, default `2`), `memory_mb` (number, default `4096`), `disk_gb` (number, default `32`).

- [ ] **Step 1: Write `versions.tf`**

```hcl
terraform {
  required_version = ">= 1.7.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.66"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
    external = {
      source  = "hashicorp/external"
      version = "~> 2.3"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}
```

- [ ] **Step 2: Write `providers.tf`**

```hcl
provider "proxmox" {
  endpoint  = var.proxmox_api_endpoint
  api_token = var.proxmox_api_token
  insecure  = true
}
```

- [ ] **Step 3: Write `variables.tf`**

```hcl
variable "proxmox_api_endpoint" {
  type = string
}

variable "proxmox_api_token" {
  type      = string
  sensitive = true
}

variable "proxmox_host" {
  type        = string
  description = "Plain SSH-reachable address of the proxmox host (e.g. 192.168.31.42), used to run pct exec commands. Distinct from proxmox_api_endpoint, which is the HTTPS API URL."
}

variable "proxmox_node" {
  type = string
}

variable "datastore_id" {
  type = string
}

variable "vm_id" {
  type = number
}

variable "node_ip" {
  type        = string
  description = "Bare static IPv4 address for the k3s node, e.g. 192.168.31.240 (no CIDR suffix)."
}

variable "gateway" {
  type = string
}

variable "cpu_cores" {
  type    = number
  default = 2
}

variable "memory_mb" {
  type    = number
  default = 4096
}

variable "disk_gb" {
  type    = number
  default = 32
}
```

- [ ] **Step 4: Write `terraform.tfvars.example`**

```hcl
proxmox_api_endpoint = "https://192.168.31.42:8006/"
proxmox_api_token    = "terraform@pve!davros=00000000-0000-0000-0000-000000000000"
proxmox_host         = "192.168.31.42"
proxmox_node         = "local"
datastore_id         = "HD_2TB"
vm_id                = 240
node_ip              = "192.168.31.240"
gateway              = "192.168.31.1"
```

- [ ] **Step 5: Write the failing test file**

```hcl
mock_provider "proxmox" {}

run "variables_have_expected_defaults" {
  command = plan

  variables {
    proxmox_api_endpoint = "https://192.168.31.42:8006/"
    proxmox_api_token    = "test-token"
    proxmox_host         = "192.168.31.42"
    proxmox_node         = "local"
    datastore_id         = "HD_2TB"
    vm_id                = 240
    node_ip              = "192.168.31.240"
    gateway              = "192.168.31.1"
  }

  assert {
    condition     = var.cpu_cores == 2
    error_message = "cpu_cores must default to 2"
  }

  assert {
    condition     = var.memory_mb == 4096
    error_message = "memory_mb must default to 4096"
  }

  assert {
    condition     = var.disk_gb == 32
    error_message = "disk_gb must default to 32"
  }
}
```

- [ ] **Step 6: Run the test to verify it fails for the right reason**

```bash
cd terraform/k3s-cluster && tofu init -input=false && tofu test
```

Expected: FAIL — there is no resource in this module yet, so `tofu plan` has nothing to plan against the variables, but the plan itself should still succeed since no resources exist to error on. Actually expect this to PASS immediately since the assertions only check variable defaults and there are no resources yet. This step exists to confirm `tofu init`/`tofu test` wiring works before any resource logic is added. Treat an `init`/`test`-harness error as the failure to fix; a clean PASS on pure variable defaults is the expected (not a red herring) outcome here.

- [ ] **Step 7: Commit**

```bash
git add terraform/k3s-cluster/versions.tf terraform/k3s-cluster/providers.tf \
  terraform/k3s-cluster/variables.tf terraform/k3s-cluster/terraform.tfvars.example \
  terraform/k3s-cluster/tests/k3s_cluster.tftest.hcl
git commit -m "feat: scaffold k3s-cluster terraform root module"
```

---

## Task 3: Container resource — static IP, privileged, NFS mount feature

**Files:**
- Modify: `terraform/k3s-cluster/main.tf` (create)
- Modify: `terraform/k3s-cluster/outputs.tf` (create)
- Test: `terraform/k3s-cluster/tests/k3s_cluster.tftest.hcl`

**Interfaces:**
- Consumes: all variables from Task 2.
- Produces: `proxmox_virtual_environment_download_file.debian_template` (template download resource), `proxmox_virtual_environment_container.node` (the container resource), outputs `ip_address` (string), `hostname` (string).

- [ ] **Step 1: Add the failing test**

Append to `terraform/k3s-cluster/tests/k3s_cluster.tftest.hcl`:

```hcl
run "container_is_privileged_with_static_ip_and_nfs_mount" {
  command = plan

  variables {
    proxmox_api_endpoint = "https://192.168.31.42:8006/"
    proxmox_api_token    = "test-token"
    proxmox_host         = "192.168.31.42"
    proxmox_node         = "local"
    datastore_id         = "HD_2TB"
    vm_id                = 240
    node_ip              = "192.168.31.240"
    gateway              = "192.168.31.1"
  }

  assert {
    condition     = proxmox_virtual_environment_container.node.unprivileged == false
    error_message = "container must be privileged, k3s and cilium need capabilities unprivileged lxc won't grant"
  }

  assert {
    condition     = proxmox_virtual_environment_container.node.initialization[0].ip_config[0].ipv4[0].address == "192.168.31.240/24"
    error_message = "container must get a static ip, not dhcp"
  }

  assert {
    condition     = proxmox_virtual_environment_container.node.initialization[0].ip_config[0].ipv4[0].gateway == "192.168.31.1"
    error_message = "container must use the configured gateway"
  }

  assert {
    condition     = contains(proxmox_virtual_environment_container.node.features[0].mount, "nfs")
    error_message = "container must allow nfs mounts, proxmox lxc blocks them by default and csi-driver-nfs needs them"
  }

  assert {
    condition     = proxmox_virtual_environment_container.node.cpu[0].cores == 2
    error_message = "container cpu cores must match cpu_cores variable default"
  }

  assert {
    condition     = proxmox_virtual_environment_container.node.memory[0].dedicated == 4096
    error_message = "container memory must match memory_mb variable default"
  }

  assert {
    condition     = output.ip_address == "192.168.31.240"
    error_message = "ip_address output must be the bare node ip"
  }

  assert {
    condition     = output.hostname == "k3s-node"
    error_message = "hostname output must be k3s-node"
  }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd terraform/k3s-cluster && tofu test
```

Expected: FAIL with "Reference to undeclared resource" (`proxmox_virtual_environment_container.node` does not exist yet).

- [ ] **Step 3: Write `main.tf`**

```hcl
locals {
  hostname = "k3s-node"
}

resource "proxmox_virtual_environment_download_file" "debian_template" {
  node_name    = var.proxmox_node
  datastore_id = "local"
  content_type = "vztmpl"
  file_name    = "debian-12-standard_12.7-1_amd64.tar.zst"
  url          = "http://download.proxmox.com/images/system/debian-12-standard_12.7-1_amd64.tar.zst"
}

resource "proxmox_virtual_environment_container" "node" {
  node_name    = var.proxmox_node
  vm_id        = var.vm_id
  unprivileged = false
  started      = true

  initialization {
    hostname = local.hostname

    ip_config {
      ipv4 {
        address = "${var.node_ip}/24"
        gateway = var.gateway
      }
    }
  }

  network_interface {
    name   = "eth0"
    bridge = "vmbr0"
  }

  operating_system {
    template_file_id = proxmox_virtual_environment_download_file.debian_template.id
    type             = "debian"
  }

  disk {
    datastore_id = var.datastore_id
    size         = var.disk_gb
  }

  cpu {
    cores = var.cpu_cores
  }

  memory {
    dedicated = var.memory_mb
  }

  features {
    nesting = true
    mount   = ["nfs"]
  }
}
```

- [ ] **Step 4: Write `outputs.tf`**

```hcl
output "ip_address" {
  value = var.node_ip
}

output "hostname" {
  value = local.hostname
}
```

- [ ] **Step 5: Run the test to verify it passes**

```bash
cd terraform/k3s-cluster && tofu test
```

Expected: PASS, both runs.

- [ ] **Step 6: Commit**

```bash
git add terraform/k3s-cluster/main.tf terraform/k3s-cluster/outputs.tf terraform/k3s-cluster/tests/k3s_cluster.tftest.hcl
git commit -m "feat: add k3s node lxc container resource"
```

---

## Task 4: Standalone, testable kubeconfig-server-rewrite script

This is the one piece of the k3s-install/kubeconfig-fetch logic that can be
unit tested without touching real infrastructure (the SSH call itself
cannot and must not run during `make test` — see Global Constraints).
Isolating the rewrite logic into its own script lets it carry a real test
cycle.

**Files:**
- Create: `terraform/k3s-cluster/scripts/rewrite-kubeconfig-server.sh`
- Test: `terraform/k3s-cluster/tests/rewrite_kubeconfig_server.test.sh`

**Interfaces:**
- Produces: a script invoked as `rewrite-kubeconfig-server.sh <new-ip>`, reading a kubeconfig YAML on stdin, writing the rewritten YAML on stdout. Later tasks (Task 5) call this script by exact path `terraform/k3s-cluster/scripts/rewrite-kubeconfig-server.sh`.

- [ ] **Step 1: Write the failing test**

```bash
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
```

Save as `terraform/k3s-cluster/tests/rewrite_kubeconfig_server.test.sh`.

- [ ] **Step 2: Run it to verify it fails**

```bash
chmod +x terraform/k3s-cluster/tests/rewrite_kubeconfig_server.test.sh
bash terraform/k3s-cluster/tests/rewrite_kubeconfig_server.test.sh
```

Expected: FAIL — `./scripts/rewrite-kubeconfig-server.sh: No such file or directory`.

- [ ] **Step 3: Write the script**

```bash
#!/usr/bin/env bash
set -euo pipefail

new_ip="$1"
sed "s/127\.0\.0\.1/${new_ip}/"
```

Save as `terraform/k3s-cluster/scripts/rewrite-kubeconfig-server.sh`, then:

```bash
chmod +x terraform/k3s-cluster/scripts/rewrite-kubeconfig-server.sh
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
bash terraform/k3s-cluster/tests/rewrite_kubeconfig_server.test.sh
```

Expected: `PASS`.

- [ ] **Step 5: Commit**

```bash
git add terraform/k3s-cluster/scripts/rewrite-kubeconfig-server.sh terraform/k3s-cluster/tests/rewrite_kubeconfig_server.test.sh
git commit -m "feat: add standalone, tested kubeconfig server-address rewrite script"
```

---

## Task 5: k3s install provisioner and kubeconfig fetch (real-infra only, no automated test)

**Files:**
- Create: `terraform/k3s-cluster/scripts/fetch-kubeconfig.sh`
- Modify: `terraform/k3s-cluster/main.tf:` (append `null_resource.k3s_install` and `data "external" "kubeconfig"`)
- Modify: `terraform/k3s-cluster/outputs.tf:` (append `kubeconfig_path` output)

**Interfaces:**
- Consumes: `proxmox_virtual_environment_container.node` (Task 3), `scripts/rewrite-kubeconfig-server.sh` (Task 4, exact path as written there).
- Produces: `local_file.kubeconfig` at `${path.module}/kubeconfig`, output `kubeconfig_path` (string) that Task 7's Makefile work consumes by exact name.

There is deliberately no `tofu test` run added in this task — per Global
Constraints, the `null_resource` provisioner and the `data "external"`
program must never execute during `make test`. Since both depend on
`proxmox_virtual_environment_container.node.id`, which is unknown during a
mocked `command = plan` run, OpenTofu defers them to apply-time and never
invokes them — this is inherent to how plan-only test runs behave, not
something the plan needs to special-case. Verification for this task
happens during the real first apply in Task 7.

- [ ] **Step 1: Write `scripts/fetch-kubeconfig.sh`**

```bash
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
```

```bash
chmod +x terraform/k3s-cluster/scripts/fetch-kubeconfig.sh
```

- [ ] **Step 2: Append the install/fetch resources to `main.tf`**

```hcl
resource "null_resource" "k3s_install" {
  depends_on = [proxmox_virtual_environment_container.node]

  triggers = {
    container_id = proxmox_virtual_environment_container.node.id
  }

  provisioner "local-exec" {
    command = "ssh root@${var.proxmox_host} 'pct exec ${var.vm_id} -- bash -c \"curl -sfL https://get.k3s.io | sh -\"'"
  }
}

data "external" "kubeconfig" {
  depends_on = [null_resource.k3s_install]

  program = ["${path.module}/scripts/fetch-kubeconfig.sh"]

  query = {
    proxmox_host = var.proxmox_host
    vm_id        = tostring(var.vm_id)
    node_ip      = var.node_ip
  }
}

resource "local_file" "kubeconfig" {
  content         = base64decode(data.external.kubeconfig.result.kubeconfig_b64)
  filename        = "${path.module}/kubeconfig"
  file_permission = "0600"
}
```

- [ ] **Step 3: Append the output to `outputs.tf`**

```hcl
output "kubeconfig_path" {
  value = local_file.kubeconfig.filename
}
```

- [ ] **Step 4: Validate the module still inits and plans cleanly against the mocked provider**

```bash
cd terraform/k3s-cluster && tofu init -input=false && tofu test
```

Expected: PASS — the new resources are unresolved/deferred under the mocked plan (per the Interfaces note above) and do not break the existing assertions.

- [ ] **Step 5: Commit**

```bash
git add terraform/k3s-cluster/scripts/fetch-kubeconfig.sh terraform/k3s-cluster/main.tf terraform/k3s-cluster/outputs.tf
git commit -m "feat: install k3s via ssh provisioner and fetch rewritten kubeconfig"
```

---

## Task 6: `.gitignore` the generated kubeconfig and tfstate, same as the old module

**Files:**
- Modify: `.gitignore`

**Interfaces:** none (pure repo hygiene, no code interface).

- [ ] **Step 1: Check current `.gitignore` coverage**

```bash
cat .gitignore
```

- [ ] **Step 2: Add the new module's generated files if not already covered by existing glob patterns**

If `.gitignore` does not already glob-match `terraform/k3s-cluster/kubeconfig`, `terraform/k3s-cluster/terraform.tfstate*`, and `terraform/k3s-cluster/terraform.tfvars`, add:

```
terraform/k3s-cluster/kubeconfig
terraform/k3s-cluster/terraform.tfstate
terraform/k3s-cluster/terraform.tfstate.backup
terraform/k3s-cluster/terraform.tfvars
```

- [ ] **Step 3: Verify with a throwaway file**

```bash
touch terraform/k3s-cluster/kubeconfig
git status --short terraform/k3s-cluster/kubeconfig
rm terraform/k3s-cluster/kubeconfig
```

Expected: no output from `git status` (file is ignored).

- [ ] **Step 4: Commit**

```bash
git add .gitignore
git commit -m "chore: gitignore k3s-cluster generated kubeconfig and tfstate"
```

(Skip the commit if Step 2 found nothing to add — the existing glob
patterns from the Talos module, e.g. `terraform/**/terraform.tfstate*`,
likely already cover this, in which case just note it and move on.)

---

## Task 7: First real apply and infra-specific validation

This task is operational — provisioning real infrastructure and validating
the LXC-specific risks called out in the spec. Not a code/test cycle.

- [ ] **Step 1: Fill in real tfvars**

```bash
cp terraform/k3s-cluster/terraform.tfvars.example terraform/k3s-cluster/terraform.tfvars
```

Edit `terraform/k3s-cluster/terraform.tfvars` with the real
`proxmox_api_token` (same token already used by the old `talos-cluster`
root, from `terraform@pve!davros=...`).

- [ ] **Step 2: Apply (you run this — real infra change)**

```bash
cd terraform/k3s-cluster
tofu init
tofu apply
```

- [ ] **Step 3: Validate NFS mount works inside the container**

```bash
ssh root@192.168.31.42 "pct exec 240 -- bash -c 'apt-get install -y nfs-common && mount -t nfs 192.168.31.42:/pool/data /mnt && umount /mnt && echo NFS_MOUNT_OK'"
```

Expected: `NFS_MOUNT_OK`. If this fails with a permission/mount-type error, the `features.mount = ["nfs"]` setting from Task 3 needs to be re-checked against the actual bpg/proxmox provider schema at the version pinned in `versions.tf` — the provider's exact `features` block field name for allowed mount types may differ slightly across versions and should be confirmed against `terraform providers schema -json` output if this step fails.

- [ ] **Step 4: Validate Cilium's eBPF requirements will work (capability + apparmor check)**

```bash
ssh root@192.168.31.42 "pct exec 240 -- bash -c 'cat /proc/sys/kernel/unprivileged_bpf_disabled; capsh --print | grep -i bpf'"
```

If this shows BPF is disabled or the container lacks `cap_bpf`/`cap_sys_admin`, set `lxc.apparmor.profile: unconfined` on the container (via the provider's raw LXC config passthrough, or `pct set 240 -lxc.apparmor.profile unconfined` directly, then `pct reboot 240`) before proceeding to install Cilium.

- [ ] **Step 5: Verify kubeconfig was generated correctly**

```bash
cat terraform/k3s-cluster/kubeconfig | grep server
```

Expected: `server: https://192.168.31.240:6443` (or whatever `node_ip` was set to), not `127.0.0.1`.

- [ ] **Step 6: Merge kubeconfig and verify cluster reachability**

```bash
KUBECONFIG=$HOME/.kube/config:terraform/k3s-cluster/kubeconfig kubectl config view --flatten > /tmp/k3s-kubeconfig-merged
mv /tmp/k3s-kubeconfig-merged $HOME/.kube/config
kubectl get nodes
```

Expected: one `Ready` node.

---

## Task 8: Update Cilium's `k8sServiceHost` from the old VIP to the new node IP

**Files:**
- Modify: `kubernetes/infrastructure/cilium/helmrelease.yaml`
- Modify: `kubernetes/infrastructure/cilium/tests/test.sh`

**Interfaces:** none new — this is a value change in an existing, already-tested file.

- [ ] **Step 1: Update the failing assertion first**

In `kubernetes/infrastructure/cilium/tests/test.sh`, change:

```bash
[ "$(echo "$helmrelease" | yq e '.spec.values.k8sServiceHost' -)" = "192.168.31.243" ] || { echo "FAIL: k8sServiceHost must be the kube-vip VIP"; exit 1; }
```

to:

```bash
[ "$(echo "$helmrelease" | yq e '.spec.values.k8sServiceHost' -)" = "192.168.31.240" ] || { echo "FAIL: k8sServiceHost must be the single k3s node's static ip, there is no vip anymore"; exit 1; }
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
bash kubernetes/infrastructure/cilium/tests/test.sh
```

Expected: FAIL — `helmrelease.yaml` still has the old VIP value.

- [ ] **Step 3: Update `helmrelease.yaml`**

In `kubernetes/infrastructure/cilium/helmrelease.yaml`, change:

```yaml
    k8sServiceHost: 192.168.31.243
```

to:

```yaml
    k8sServiceHost: 192.168.31.240
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
bash kubernetes/infrastructure/cilium/tests/test.sh
```

Expected: `PASS`.

- [ ] **Step 5: Commit**

```bash
git add kubernetes/infrastructure/cilium/helmrelease.yaml kubernetes/infrastructure/cilium/tests/test.sh
git commit -m "fix: point cilium k8sServiceHost at the single k3s node ip, no vip anymore"
```

---

## Task 9: Rewrite the Makefile's cluster targets for k3s-in-LXC

**Files:**
- Modify: `Makefile`

**Interfaces:** none new — this reuses `terraform/k3s-cluster`'s `kubeconfig_path` output (Task 5) and `terraform/k3s-cluster` as the new root path (Task 2/3) by exact name.

- [ ] **Step 1: Update `TF_ROOTS`**

Change:

```makefile
TF_ROOTS := terraform/talos-cluster terraform/cloudflare
```

to:

```makefile
TF_ROOTS := terraform/k3s-cluster terraform/cloudflare
```

- [ ] **Step 2: Update `plan-cluster`, `apply-cluster`, `destroy-cluster` to the new path**

Change every `cd terraform/talos-cluster` in these three targets to `cd terraform/k3s-cluster`.

- [ ] **Step 3: Delete the `talos-bootstrap` target entirely**

Remove:

```makefile
.PHONY: talos-bootstrap
talos-bootstrap: ## bootstrap etcd on the first control-plane node -- REAL CHANGE, run once per cluster lifetime
	$(MAKE) confirm MSG="about to bootstrap etcd on the talos cluster. only do this once."
	talosctl bootstrap --nodes $$(cd terraform/talos-cluster && tofu output -raw -json node_ips | python3 -c 'import json,sys; print(json.load(sys.stdin)["cp-0"])')
```

k3s bootstraps itself fully during install — there is no separate etcd
bootstrap step in this design.

- [ ] **Step 4: Rewrite the `kubeconfig` target**

Change:

```makefile
.PHONY: kubeconfig
kubeconfig: ## merge talosconfig and kubeconfig from terraform outputs into ~/.talos and ~/.kube
	cd terraform/talos-cluster && tofu output -raw talosconfig | talosctl config merge /dev/stdin
	cd terraform/talos-cluster && tofu output -raw kubeconfig > /tmp/davros-kubeconfig
	KUBECONFIG=$$HOME/.kube/config:/tmp/davros-kubeconfig kubectl config view --flatten > /tmp/davros-kubeconfig-merged
	mv /tmp/davros-kubeconfig-merged $$HOME/.kube/config
	rm -f /tmp/davros-kubeconfig
```

to:

```makefile
.PHONY: kubeconfig
kubeconfig: ## merge the k3s-cluster-generated kubeconfig into ~/.kube/config
	KUBECONFIG=$$HOME/.kube/config:terraform/k3s-cluster/kubeconfig kubectl config view --flatten > /tmp/davros-kubeconfig-merged
	mv /tmp/davros-kubeconfig-merged $$HOME/.kube/config
```

(No `talosctl config merge` step — there is no talosconfig in this design.
`terraform/k3s-cluster/kubeconfig` is the exact file `local_file.kubeconfig`
writes in Task 5.)

- [ ] **Step 5: Update `cilium-bootstrap`'s `k8sServiceHost` value**

Change:

```makefile
		--set k8sServiceHost=192.168.31.243 \
```

to:

```makefile
		--set k8sServiceHost=192.168.31.240 \
```

- [ ] **Step 6: Add a `sops-age-key` target that generates the age key only if missing**

The spec's one-command bootstrap requirement needs this: on a genuinely
fresh homelab rebuild, `~/.config/sops/age/keys.txt` may not exist yet, and
`sops-age-secret` currently assumes it does. Add, just above the existing
`sops-age-secret` target:

```makefile
.PHONY: sops-age-key
sops-age-key: ## generate the sops age keypair if it doesn't already exist -- REAL CHANGE, never overwrites an existing key
	@if [ -f "$(AGE_KEY_FILE)" ]; then \
		echo "age key already exists at $(AGE_KEY_FILE), leaving it alone"; \
	else \
		mkdir -p "$$(dirname "$(AGE_KEY_FILE)")"; \
		age-keygen -o "$(AGE_KEY_FILE)"; \
		echo "generated new age key at $(AGE_KEY_FILE) -- add its public key to .sops.yaml if not already present"; \
	fi
```

This is idempotent by construction: it only ever calls `age-keygen` when the
file is absent, and never deletes or regenerates an existing key (which
would break decryption of every secret already committed with the old
key).

- [ ] **Step 7: Wire `sops-age-key` into `sops-age-secret` as a prerequisite**

Change:

```makefile
.PHONY: sops-age-secret
sops-age-secret: ## deliver the sops age private key into the cluster so flux can decrypt secrets -- REAL CHANGE
	$(MAKE) confirm MSG="about to put the sops age private key into the flux-system namespace."
```

to:

```makefile
.PHONY: sops-age-secret
sops-age-secret: sops-age-key ## deliver the sops age private key into the cluster so flux can decrypt secrets -- REAL CHANGE
	$(MAKE) confirm MSG="about to put the sops age private key into the flux-system namespace."
```

- [ ] **Step 8: Remove `talos-bootstrap` from the `bootstrap` chain**

Change:

```makefile
.PHONY: bootstrap
bootstrap: ## full first-time cluster bring-up, step by step, each step asks to confirm -- REAL CHANGES
	$(MAKE) apply-cluster
	$(MAKE) talos-bootstrap
	$(MAKE) kubeconfig
	$(MAKE) cilium-bootstrap
	$(MAKE) flux-bootstrap
	$(MAKE) sops-age-secret
	$(MAKE) apply-cloudflare
```

to:

```makefile
.PHONY: bootstrap
bootstrap: ## full first-time cluster bring-up, step by step, each step asks to confirm -- REAL CHANGES
	$(MAKE) apply-cluster
	$(MAKE) kubeconfig
	$(MAKE) cilium-bootstrap
	$(MAKE) flux-bootstrap
	$(MAKE) sops-age-secret
	$(MAKE) apply-cloudflare
```

(`sops-age-secret` now pulls in `sops-age-key` automatically via its
prerequisite, so the chain doesn't need its own explicit step for it.)

- [ ] **Step 9: Run `make help` to verify the Makefile still parses correctly**

```bash
make help
```

Expected: a clean target list, no `talos-bootstrap` entry, a new
`sops-age-key` entry, no errors.

- [ ] **Step 10: Verify idempotency of the new target against the real, already-existing key**

```bash
make sops-age-key
```

Expected: prints `age key already exists at ..., leaving it alone` — does
NOT regenerate (this machine already has a real key from earlier this
session; confirm it's untouched: `sha256sum ~/.config/sops/age/keys.txt`
before and after should match).

- [ ] **Step 11: Commit**

```bash
git add Makefile
git commit -m "feat: rewire Makefile bootstrap chain for k3s-in-lxc, drop talos-bootstrap step"
```

---

## Task 10: Full end-to-end verification

Operational verification, not a code-test cycle — this is the plan's final
acceptance check.

- [ ] **Step 1: Run the full safe test suite**

```bash
make test
```

Expected: every `tofu test` and every `kustomize build` test passes,
including the new `terraform/k3s-cluster` tests and the updated Cilium
test from Task 8.

- [ ] **Step 2: Run the one-command bootstrap against the real cluster**

(Assumes Task 7's apply already ran — this exercises the remaining chain:
cilium, flux, sops-age, cloudflare. Each step still asks for `yes`.)

```bash
make cilium-bootstrap
make flux-bootstrap
make sops-age-secret
```

- [ ] **Step 3: Verify Flux reconciles cleanly against the new cluster**

```bash
flux check
kubectl get kustomization -n flux-system
```

Expected: `flux-system`, `infrastructure`, `infrastructure-configs`, `apps`
all show `READY: True`.

- [ ] **Step 4: Verify no etcd-related errors appear anywhere**

```bash
kubectl get pods -A | grep -v Running | grep -v Completed
```

Expected: no output, or only pods in a normal transient state (not
`CrashLoopBackOff`). The etcd-leader-election failure mode from this
session should structurally no longer be possible on a single-node
cluster.
