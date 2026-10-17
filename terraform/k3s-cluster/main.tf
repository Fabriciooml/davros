locals {
  hostname    = "k3s-node"
  k3s_version = "v1.36.5+k3s1"
}

resource "proxmox_virtual_environment_download_file" "debian_template" {
  node_name    = var.proxmox_node
  datastore_id = "local"
  content_type = "vztmpl"
  file_name    = "debian-12-standard_12.12-1_amd64.tar.zst"
  url          = "http://download.proxmox.com/images/system/debian-12-standard_12.12-1_amd64.tar.zst"
  checksum           = "50c85eaaece677a3ebe01cc909b83872e9da2a22c29ae652838afce71e83222fdf40f6accecd7d52b180e912fc1f85ecdf7b3fc4d3027da4d865e509a9e76597"
  checksum_algorithm = "sha512"

  lifecycle {
    ignore_changes = [checksum, checksum_algorithm]
  }
}

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
  }

  provisioner "local-exec" {
    command = "ssh root@${self.triggers.proxmox_host} 'pct create ${self.triggers.vm_id} ${self.triggers.template_file_id} --hostname ${self.triggers.hostname} --cores ${var.cpu_cores} --memory ${var.memory_mb} --rootfs ${self.triggers.datastore_id}:${self.triggers.disk_gb} --net0 name=eth0,bridge=vmbr0,ip=${self.triggers.node_ip}/24,gw=${self.triggers.gateway} --nameserver 192.168.31.152 --searchdomain fabriciooml.dev --unprivileged 0 --features nesting=1,mount=nfs && echo \"lxc.apparmor.profile: unconfined\" >> /etc/pve/lxc/${self.triggers.vm_id}.conf && echo \"lxc.mount.auto: proc:rw sys:rw\" >> /etc/pve/lxc/${self.triggers.vm_id}.conf && pct start ${self.triggers.vm_id}'"
  }

  provisioner "local-exec" {
    when    = destroy
    command = "ssh root@${self.triggers.proxmox_host} 'pct stop ${self.triggers.vm_id} || true; pct destroy ${self.triggers.vm_id}'"
  }
}

resource "null_resource" "resize" {
  depends_on = [null_resource.container]

  triggers = {
    cpu_cores = tostring(var.cpu_cores)
    memory_mb = tostring(var.memory_mb)
  }

  provisioner "local-exec" {
    command = "ssh root@${var.proxmox_host} 'pct set ${var.vm_id} --cores ${var.cpu_cores} --memory ${var.memory_mb}'"
  }
}

resource "null_resource" "k3s_install" {
  depends_on = [null_resource.container]

  triggers = {
    vm_id        = var.vm_id
    container_id = null_resource.container.id
  }

  provisioner "local-exec" {
    command = "ssh root@${var.proxmox_host} 'pct exec ${var.vm_id} -- mkdir -p /etc/tmpfiles.d'"
  }

  provisioner "local-exec" {
    command = "ssh root@${var.proxmox_host} \"pct exec ${var.vm_id} -- sh -c 'echo \\\"L /dev/kmsg - - - - /dev/console\\\" > /etc/tmpfiles.d/kmsg.conf'\""
  }

  provisioner "local-exec" {
    command = "ssh root@${var.proxmox_host} 'pct exec ${var.vm_id} -- systemd-tmpfiles --create /etc/tmpfiles.d/kmsg.conf'"
  }

  provisioner "local-exec" {
    command = "ssh root@${var.proxmox_host} 'pct exec ${var.vm_id} -- sh -c \"sysctl -w net.ipv6.conf.all.disable_ipv6=1; sysctl -w net.ipv6.conf.default.disable_ipv6=1; printf \\\"net.ipv6.conf.all.disable_ipv6 = 1\\nnet.ipv6.conf.default.disable_ipv6 = 1\\n\\\" > /etc/sysctl.d/99-disable-ipv6.conf\"'"
  }

  provisioner "local-exec" {
    command = "ssh root@${var.proxmox_host} 'pct exec ${var.vm_id} -- bash -c \"set -o pipefail; apt-get update && apt-get install -y curl && curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=${local.k3s_version} INSTALL_K3S_EXEC=\\\"server --snapshotter=native --disable=traefik --disable=local-storage --node-ip=${var.node_ip} --kubelet-arg=runtime-request-timeout=5m\\\" sh -\"'"
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
  content         = sensitive(base64decode(data.external.kubeconfig.result.kubeconfig_b64))
  filename        = "${path.module}/kubeconfig"
  file_permission = "0600"
}
