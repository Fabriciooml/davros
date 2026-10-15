locals {
  cluster_name       = "davros"
  network_cidr       = "192.168.31.240/29"
  gateway            = "192.168.31.1"
  proxmox_node       = "local"
  datastore_id       = "HD_2TB"
  talos_version      = "v1.9.0"
  kubernetes_version = "v1.32.0"

  talos_schematic_id  = "ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515"
  talos_iso_url       = "https://factory.talos.dev/image/${local.talos_schematic_id}/${local.talos_version}/metal-amd64.iso"
  talos_install_image = "factory.talos.dev/metal-installer/${local.talos_schematic_id}:${local.talos_version}"

  vip_offset       = var.control_plane_count + var.worker_count
  vip_address      = cidrhost(local.network_cidr, local.vip_offset)
  cluster_endpoint = "https://${local.vip_address}:6443"

  control_plane_nodes = {
    for i in range(var.control_plane_count) : "cp-${i}" => {
      role      = "control-plane"
      index     = i
      cpu_cores = var.control_plane_cpu_cores
      memory_mb = var.control_plane_memory_mb
      disk_gb   = var.control_plane_disk_gb
      vm_id     = 240 + i
    }
  }

  worker_nodes = {
    for i in range(var.worker_count) : "worker-${i}" => {
      role      = "worker"
      index     = var.control_plane_count + i
      cpu_cores = var.worker_cpu_cores
      memory_mb = var.worker_memory_mb
      disk_gb   = var.worker_disk_gb
      vm_id     = 240 + var.control_plane_count + i
    }
  }

  nodes = merge(local.control_plane_nodes, local.worker_nodes)
}

resource "talos_machine_secrets" "this" {}

resource "proxmox_download_file" "talos_iso" {
  node_name    = local.proxmox_node
  datastore_id = "local"
  content_type = "iso"
  file_name    = "talos-${local.talos_version}-qemu-guest-agent.iso"
  url          = local.talos_iso_url
}

module "node" {
  source = "../modules/talos-node"

  for_each = local.nodes

  role         = each.value.role
  index        = each.value.index
  cpu_cores    = each.value.cpu_cores
  memory_mb    = each.value.memory_mb
  disk_gb      = each.value.disk_gb
  network_cidr = local.network_cidr
  gateway      = local.gateway
  proxmox_node = local.proxmox_node
  datastore_id = local.datastore_id
  vm_id        = each.value.vm_id

  boot_iso_file_id = proxmox_download_file.talos_iso.id

  cluster_name         = local.cluster_name
  cluster_endpoint     = local.cluster_endpoint
  machine_secrets      = talos_machine_secrets.this.machine_secrets
  client_configuration = talos_machine_secrets.this.client_configuration
  install_image        = local.talos_install_image
  talos_version        = local.talos_version
  kubernetes_version   = local.kubernetes_version
  vip_address          = each.value.role == "control-plane" ? local.vip_address : null
}

data "talos_client_configuration" "this" {
  cluster_name         = local.cluster_name
  client_configuration = talos_machine_secrets.this.client_configuration
  nodes                = [for k, m in module.node : m.ip_address]
  endpoints            = [local.vip_address]
}
