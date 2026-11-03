locals {
  hostname = "ts-router"
  lxc_conf = join("\n", [
    "lxc.cgroup2.devices.allow: c 10:200 rwm",
    "lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file",
  ])
}

resource "null_resource" "container" {
  triggers = {
    vm_id            = tostring(var.vm_id)
    proxmox_host     = var.proxmox_host
    template_file_id = var.template_file_id
    hostname         = local.hostname
    node_ip          = var.node_ip
    gateway          = var.gateway
    nameserver       = var.nameserver
    datastore_id     = var.datastore_id
    disk_gb          = tostring(var.disk_gb)
    cpu_cores        = tostring(var.cpu_cores)
    memory_mb        = tostring(var.memory_mb)
    advertise_route  = var.advertise_route
    lxc_conf         = local.lxc_conf
  }

  provisioner "local-exec" {
    command = "ssh root@${self.triggers.proxmox_host} 'pct create ${self.triggers.vm_id} ${self.triggers.template_file_id} --hostname ${self.triggers.hostname} --cores ${self.triggers.cpu_cores} --memory ${self.triggers.memory_mb} --rootfs ${self.triggers.datastore_id}:${self.triggers.disk_gb} --net0 name=eth0,bridge=vmbr0,ip=${self.triggers.node_ip}/24,gw=${self.triggers.gateway} --nameserver ${self.triggers.nameserver} --unprivileged 1 --onboot 1 && printf \"%s\\n\" \"${self.triggers.lxc_conf}\" >> /etc/pve/lxc/${self.triggers.vm_id}.conf && pct start ${self.triggers.vm_id}'"
  }

  provisioner "local-exec" {
    when    = destroy
    command = "ssh root@${self.triggers.proxmox_host} 'pct stop ${self.triggers.vm_id} || true; pct destroy ${self.triggers.vm_id}'"
  }
}

resource "null_resource" "tailscale_install" {
  depends_on = [null_resource.container]

  triggers = {
    container_id = null_resource.container.id
  }

  provisioner "local-exec" {
    command = "ssh root@${var.proxmox_host} 'pct exec ${var.vm_id} -- bash -c \"set -o pipefail; apt-get update && apt-get install -y curl && curl -fsSL https://tailscale.com/install.sh | sh\"'"
  }

  provisioner "local-exec" {
    command = "ssh root@${var.proxmox_host} 'pct exec ${var.vm_id} -- sh -c \"printf \\\"net.ipv4.ip_forward = 1\\n\\\" > /etc/sysctl.d/99-tailscale.conf && sysctl -p /etc/sysctl.d/99-tailscale.conf\"'"
  }
}

resource "null_resource" "tailscale_up" {
  depends_on = [null_resource.tailscale_install]

  triggers = {
    container_id    = null_resource.container.id
    advertise_route = var.advertise_route
  }

  # the one-time key comes from the process environment via the script, never from tofu config
  provisioner "local-exec" {
    command = "${path.module}/scripts/tailscale-up.sh ${var.proxmox_host} ${var.vm_id} ${var.advertise_route} ${local.hostname}"
  }
}
