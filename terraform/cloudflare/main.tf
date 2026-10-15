module "app" {
  source = "../modules/public-app-ingress"

  for_each = var.public_apps

  app_name       = each.key
  domain         = var.domain
  zone_id        = var.zone_id
  tunnel_id      = var.tunnel_id
  target_url     = each.value.target_url
  origin_request = each.value.origin_request
}

locals {
  app_ingress_rules = [
    for name, app in var.public_apps : {
      hostname       = module.app[name].ingress_rule.hostname
      path           = null
      service        = module.app[name].ingress_rule.service
      origin_request = module.app[name].ingress_rule.origin_request
    }
  ]

  catch_all_rule = {
    hostname       = null
    path           = null
    service        = "http_status:404"
    origin_request = null
  }

  ingress_rules = concat(local.app_ingress_rules, [local.catch_all_rule])
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "this" {
  account_id = var.account_id
  tunnel_id  = var.tunnel_id

  config = {
    ingress = local.ingress_rules
  }
}
