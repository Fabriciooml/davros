locals {
  hostname     = "talos-${var.role}-${var.index}"
  ip_address   = cidrhost(var.network_cidr, var.index)
  machine_type = var.role == "control-plane" ? "controlplane" : "worker"
  mac_address  = "BC:24:11:00:00:${format("%02X", var.vm_id)}"

  interface_config = merge(
    {
      interface = "ens18"
      addresses = ["${local.ip_address}/24"]
      routes = [
        {
          network = "0.0.0.0/0"
          gateway = var.gateway
        }
      ]
    },
    var.role == "control-plane" && var.vip_address != null ? { vip = { ip = var.vip_address } } : {}
  )

  machine_config_patch = yamlencode({
    machine = {
      network = {
        hostname   = local.hostname
        interfaces = [local.interface_config]
      }
      install = {
        image = var.install_image
      }
    }
    cluster = {
      network = {
        cni = {
          name = "none"
        }
      }
      proxy = {
        disabled = true
      }
      allowSchedulingOnControlPlanes = true
    }
  })
}

data "talos_machine_configuration" "this" {
  cluster_name       = var.cluster_name
  cluster_endpoint   = var.cluster_endpoint
  machine_secrets    = var.machine_secrets
  machine_type       = local.machine_type
  talos_version      = var.talos_version
  kubernetes_version = var.kubernetes_version
  config_patches     = [local.machine_config_patch]
}

resource "talos_machine_configuration_apply" "this" {
  client_configuration        = var.client_configuration
  machine_configuration_input = data.talos_machine_configuration.this.machine_configuration
  node                        = local.ip_address
  endpoint                    = local.ip_address
}

resource "proxmox_virtual_environment_vm" "this" {
  name      = local.hostname
  node_name = var.proxmox_node
  vm_id     = var.vm_id

  boot_order = ["scsi0", "ide3"]

  cpu {
    cores = var.cpu_cores
    type  = "host"
  }

  agent {
    enabled = true
  }

  memory {
    dedicated = var.memory_mb
  }

  disk {
    datastore_id = var.datastore_id
    size         = var.disk_gb
    interface    = "scsi0"
  }

  cdrom {
    interface = "ide3"
    file_id   = var.boot_iso_file_id
  }

  network_device {
    bridge      = "vmbr0"
    mac_address = local.mac_address
  }

  serial_device {
    device = "socket"
  }

  operating_system {
    type = "l26"
  }

  initialization {
    ip_config {
      ipv4 {
        address = "${local.ip_address}/24"
        gateway = var.gateway
      }
    }
  }
}
