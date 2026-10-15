output "node_ips" {
  value = { for k, m in module.node : k => m.ip_address }
}

output "node_hostnames" {
  value = { for k, m in module.node : k => m.hostname }
}

output "vip_address" {
  value = local.vip_address
}

output "node_mac_addresses" {
  value = { for k, m in module.node : k => m.mac_address }
}

output "talosconfig" {
  value     = data.talos_client_configuration.this.talos_config
  sensitive = true
}
