output "ip_address" {
  value = var.node_ip
}

output "hostname" {
  value = local.hostname
}

output "kubeconfig_path" {
  value = local_file.kubeconfig.filename
}
