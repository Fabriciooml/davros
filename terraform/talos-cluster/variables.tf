variable "proxmox_api_endpoint" {
  type = string
}

variable "proxmox_api_token" {
  type      = string
  sensitive = true
}

variable "control_plane_count" {
  type    = number
  default = 3
}

variable "worker_count" {
  type    = number
  default = 0
}

variable "control_plane_cpu_cores" {
  type    = number
  default = 2
}

variable "control_plane_memory_mb" {
  type    = number
  default = 3072
}

variable "control_plane_disk_gb" {
  type    = number
  default = 32
}

variable "worker_cpu_cores" {
  type    = number
  default = 2
}

variable "worker_memory_mb" {
  type    = number
  default = 3072
}

variable "worker_disk_gb" {
  type    = number
  default = 32
}
