variable "proxmox_host" {
  type        = string
  description = "Plain SSH-reachable address of the proxmox host (e.g. 192.168.31.42), used to run pct commands."
}

variable "datastore_id" {
  type = string
}

variable "vm_id" {
  type = number
}

variable "node_ip" {
  type        = string
  description = "Bare static IPv4 address for ts-router, e.g. 192.168.31.241 (no CIDR suffix)."
}

variable "gateway" {
  type = string
}

variable "nameserver" {
  type    = string
  default = "192.168.31.152"
}

variable "advertise_route" {
  type        = string
  default     = "192.168.31.0/24"
  description = "LAN CIDR advertised to the tailnet."
}

variable "template_file_id" {
  type        = string
  default     = "local:vztmpl/debian-12-standard_12.12-1_amd64.tar.zst"
  description = "Debian template already on the proxmox host (downloaded by the k3s-cluster root)."
}

variable "cpu_cores" {
  type    = number
  default = 1
}

variable "memory_mb" {
  type    = number
  default = 256
}

variable "disk_gb" {
  type    = number
  default = 2
}
