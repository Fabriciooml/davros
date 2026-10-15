output "ip_address" {
  value = local.ip_address
}

output "hostname" {
  value = local.hostname
}

output "vm_id" {
  value = proxmox_virtual_environment_vm.this.vm_id
}

output "mac_address" {
  value = local.mac_address
}

output "machine_config" {
  value     = data.talos_machine_configuration.this.machine_configuration
  sensitive = true
}
