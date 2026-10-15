variable "role" {
  type = string

  validation {
    condition     = contains(["control-plane", "worker"], var.role)
    error_message = "role must be \"control-plane\" or \"worker\"."
  }
}

variable "index" {
  type = number
}

variable "cpu_cores" {
  type = number
}

variable "memory_mb" {
  type = number
}

variable "disk_gb" {
  type = number
}

variable "network_cidr" {
  type        = string
  description = "CIDR block the node IP is carved from, e.g. 192.168.31.240/29."
}

variable "gateway" {
  type = string
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

variable "boot_iso_file_id" {
  type        = string
  description = "Proxmox file_id of the talos image factory iso, shared across all node VMs."
}

variable "cluster_name" {
  type = string
}

variable "cluster_endpoint" {
  type = string
}

variable "machine_secrets" {
  type      = any
  sensitive = true
}

variable "client_configuration" {
  type      = any
  sensitive = true
}

variable "install_image" {
  type        = string
  description = "Exact talos installer image reference (factory.talos.dev/<type>/<schematic-id>:<version>), explicitly pinned so install never silently falls back to talos' own bundled default version/schematic."
}

variable "talos_version" {
  type = string
}

variable "kubernetes_version" {
  type = string
}

variable "vip_address" {
  type     = string
  nullable = true
  default  = null
}
