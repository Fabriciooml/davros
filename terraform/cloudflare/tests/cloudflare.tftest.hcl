mock_provider "cloudflare" {}

run "zero_apps_gives_only_the_catch_all_rule" {
  command = plan

  variables {
    account_id  = "account-123"
    zone_id     = "zone-abc123"
    tunnel_id   = "tunnel-def456"
    domain      = "fabriciooml.dev"
    public_apps = {}
  }

  assert {
    condition     = length(cloudflare_zero_trust_tunnel_cloudflared_config.this.config.ingress) == 1
    error_message = "with no public apps, only the mandatory catch-all rule must exist"
  }

  assert {
    condition     = cloudflare_zero_trust_tunnel_cloudflared_config.this.config.ingress[0].service == "http_status:404"
    error_message = "the ingress list's last (and here only) rule must be the catch-all"
  }
}

run "one_app_gets_its_own_rule_before_the_catch_all" {
  command = plan

  variables {
    account_id = "account-123"
    zone_id    = "zone-abc123"
    tunnel_id  = "tunnel-def456"
    domain     = "fabriciooml.dev"
    public_apps = {
      jellyfin = {
        target_url = "http://192.168.31.244:80"
      }
    }
  }

  assert {
    condition     = length(cloudflare_zero_trust_tunnel_cloudflared_config.this.config.ingress) == 2
    error_message = "one app must add exactly one rule, plus the catch-all"
  }

  assert {
    condition     = cloudflare_zero_trust_tunnel_cloudflared_config.this.config.ingress[0].hostname == "jellyfin.fabriciooml.dev"
    error_message = "the app's rule must come before the catch-all and carry its hostname"
  }

  assert {
    condition     = cloudflare_zero_trust_tunnel_cloudflared_config.this.config.ingress[0].service == "http://192.168.31.244:80"
    error_message = "the app's rule must forward to its target_url"
  }

  assert {
    condition     = cloudflare_zero_trust_tunnel_cloudflared_config.this.config.ingress[1].service == "http_status:404"
    error_message = "the catch-all rule must remain last"
  }
}
