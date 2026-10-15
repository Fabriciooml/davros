locals {
  hostname = "${var.app_name}.${var.domain}"
}

resource "cloudflare_dns_record" "this" {
  zone_id = var.zone_id
  name    = local.hostname
  type    = "CNAME"
  content = "${var.tunnel_id}.cfargotunnel.com"
  ttl     = 1
  proxied = true
}
