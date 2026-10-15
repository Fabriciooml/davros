output "hostname" {
  value = local.hostname
}

output "ingress_rule" {
  value = {
    hostname       = local.hostname
    service        = var.target_url
    origin_request = var.origin_request
  }
}
