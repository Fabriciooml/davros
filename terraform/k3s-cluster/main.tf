locals {
  hostname = "k3s-node"
}

resource "proxmox_virtual_environment_download_file" "debian_template" {
  node_name    = var.proxmox_node
  datastore_id = "local"
  content_type = "vztmpl"
  file_name    = "debian-12-standard_12.12-1_amd64.tar.zst"
  url          = "http://download.proxmox.com/images/system/debian-12-standard_12.12-1_amd64.tar.zst"
}

# Proxmox hardcodes both "creating" and "changing feature flags for" a
# privileged container to root@pam only -- no pveum role/permission can
# grant either to a scoped API token user, and unprivileged/features can't
# be changed on a container after creation either (`pct set -unprivileged`
# errors "unable to modify read-only option"). So the container itself is
# created, started, and destroyed over a root SSH session using `pct`
# directly, bypassing the Proxmox REST API (and its root@pam-only check)
# for this one step -- the same root-SSH trust boundary the k3s install
# below already uses, just extended to container creation too.
resource "null_resource" "container" {
  depends_on = [proxmox_virtual_environment_download_file.debian_template]

  triggers = {
    vm_id            = tostring(var.vm_id)
    proxmox_host     = var.proxmox_host
    proxmox_node     = var.proxmox_node
    template_file_id = proxmox_virtual_environment_download_file.debian_template.id
    hostname         = local.hostname
    node_ip          = var.node_ip
    gateway          = var.gateway
    datastore_id     = var.datastore_id
    disk_gb          = tostring(var.disk_gb)
    cpu_cores        = tostring(var.cpu_cores)
    memory_mb        = tostring(var.memory_mb)
  }

  provisioner "local-exec" {
    # --start is deliberately omitted from `pct create`: two raw lxc.*
    # config lines need to land in /etc/pve/lxc/<id>.conf before first
    # boot, discovered only by hitting real infra:
    #  - lxc.apparmor.profile=unconfined: the default privileged-container
    #    apparmor profile still denies mounting nfs (and other) filesystems.
    #  - lxc.mount.auto=proc:rw sys:rw: separately from apparmor, lxc's
    #    default mount namespace masks several /proc/sys paths read-only
    #    (vm.overcommit_memory, kernel.panic, kernel.panic_on_oops) that
    #    kubelet insists on writing at startup, crashlooping k3s otherwise.
    # `pct create` on the CLI doesn't auto-inject a DNS resolver the way
    # Proxmox's own GUI/cloud-init flow does, so without an explicit
    # --nameserver the container gets no /etc/resolv.conf at all and every
    # apt-get/curl call fails resolving hostnames.
    command = "ssh root@${self.triggers.proxmox_host} 'pct create ${self.triggers.vm_id} ${self.triggers.template_file_id} --hostname ${self.triggers.hostname} --cores ${self.triggers.cpu_cores} --memory ${self.triggers.memory_mb} --rootfs ${self.triggers.datastore_id}:${self.triggers.disk_gb} --net0 name=eth0,bridge=vmbr0,ip=${self.triggers.node_ip}/24,gw=${self.triggers.gateway} --nameserver 192.168.31.152 --searchdomain fabriciooml.dev --unprivileged 0 --features nesting=1,mount=nfs && echo \"lxc.apparmor.profile: unconfined\" >> /etc/pve/lxc/${self.triggers.vm_id}.conf && echo \"lxc.mount.auto: proc:rw sys:rw\" >> /etc/pve/lxc/${self.triggers.vm_id}.conf && pct start ${self.triggers.vm_id}'"
  }

  provisioner "local-exec" {
    when    = destroy
    command = "ssh root@${self.triggers.proxmox_host} 'pct stop ${self.triggers.vm_id} || true; pct destroy ${self.triggers.vm_id}'"
  }
}

resource "null_resource" "k3s_install" {
  depends_on = [null_resource.container]

  triggers = {
    vm_id = var.vm_id
  }

  provisioner "local-exec" {
    # /dev is tmpfs, recreated empty on every boot, so the kmsg->console
    # symlink kubelet needs (LXC doesn't expose a real /dev/kmsg) has to be
    # a tmpfiles.d rule applied on every start, not a one-off symlink.
    command = "ssh root@${var.proxmox_host} 'pct exec ${var.vm_id} -- mkdir -p /etc/tmpfiles.d'"
  }

  provisioner "local-exec" {
    command = "ssh root@${var.proxmox_host} \"pct exec ${var.vm_id} -- sh -c 'echo \\\"L /dev/kmsg - - - - /dev/console\\\" > /etc/tmpfiles.d/kmsg.conf'\""
  }

  provisioner "local-exec" {
    command = "ssh root@${var.proxmox_host} 'pct exec ${var.vm_id} -- systemd-tmpfiles --create /etc/tmpfiles.d/kmsg.conf'"
  }

  provisioner "local-exec" {
    # Flags, beyond --snapshotter=native (see above):
    #  - --disable=traefik: k3s bundles its own Traefik by default; this
    #    repo installs its own Traefik HelmRelease via Flux instead.
    #  - --disable=local-storage: k3s's bundled local-path-provisioner
    #    isn't used -- csi-driver-nfs is this cluster's StorageClass.
    #  - --node-ip: avoids ambiguity in kubelet's own node-address
    #    detection on a bare-metal/LXC host with a single static IP;
    #    k3s's own docs recommend this explicitly for setups like this.
    #
    # Deliberately keeping k3s's DEFAULT CNI (flannel) and default
    # LoadBalancer controller (servicelb/klipper-lb) rather than disabling
    # them for Cilium. Cilium's eBPF networking, BGP/L2 LB without
    # MetalLB, and Hubble observability are real advantages at multi-node
    # scale, but add meaningful bootstrap complexity (a manual
    # cilium-bootstrap step that has to run before Flux even exists, plus
    # several real LXC-specific quirks: SYS_MODULE capability, a
    # containerd-overlay interaction, and friction fitting a chicken-and-egg
    # pre-Flux CNI install into this cluster's single-node lifecycle) that
    # isn't worth it for one node. k3s's bundled flannel+servicelb need
    # zero bootstrap dance at all -- the node goes Ready as part of the
    # normal k3s install with no extra step.
    command = "ssh root@${var.proxmox_host} 'pct exec ${var.vm_id} -- bash -c \"set -o pipefail; apt-get update && apt-get install -y curl && curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC=\\\"server --snapshotter=native --disable=traefik --disable=local-storage --node-ip=${var.node_ip}\\\" sh -\"'"
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
