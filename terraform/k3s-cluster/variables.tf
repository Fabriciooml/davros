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
