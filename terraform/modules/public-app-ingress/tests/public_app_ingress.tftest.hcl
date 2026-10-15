mock_provider "cloudflare" {}

run "app_gets_dns_record_and_ingress_rule_fragment" {
  command = plan

  variables {
    app_name   = "jellyfin"
    domain     = "fabriciooml.dev"
    zone_id    = "zone-abc123"
    tunnel_id  = "tunnel-def456"
    target_url = "http://192.168.31.244:80"
  }

  assert {
    condition     = output.hostname == "jellyfin.fabriciooml.dev"
    error_message = "hostname must be app_name joined to domain"
  }

  assert {
    condition     = cloudflare_dns_record.this.name == "jellyfin.fabriciooml.dev"
    error_message = "dns record name must be the full hostname"
  }

  assert {
    condition     = cloudflare_dns_record.this.type == "CNAME"
    error_message = "dns record must be a CNAME pointing at the tunnel"
  }

  assert {
    condition     = cloudflare_dns_record.this.content == "tunnel-def456.cfargotunnel.com"
    error_message = "dns record must point at this tunnel's cfargotunnel.com address"
  }

  assert {
    condition     = cloudflare_dns_record.this.proxied == true
    error_message = "record must be proxied through cloudflare, not dns-only"
  }

  assert {
    condition     = output.ingress_rule.hostname == "jellyfin.fabriciooml.dev"
    error_message = "ingress rule fragment must carry the same hostname as the dns record"
  }

  assert {
    condition     = output.ingress_rule.service == "http://192.168.31.244:80"
    error_message = "ingress rule fragment must point at the given target_url"
  }

  assert {
    condition     = output.ingress_rule.origin_request == null
    error_message = "origin_request must default to null when the app needs no origin overrides"
  }
}

run "app_with_self_signed_origin_and_host_header_override" {
  command = plan

  variables {
    app_name   = "vault"
    domain     = "fabriciooml.dev"
    zone_id    = "zone-abc123"
    tunnel_id  = "tunnel-def456"
    target_url = "https://192.168.31.108:8000"
    origin_request = {
      no_tls_verify    = true
      http_host_header = "vault.fabriciooml.dev"
    }
  }

  assert {
    condition     = output.ingress_rule.origin_request.no_tls_verify == true
    error_message = "origin_request.no_tls_verify must pass through for self-signed origins"
  }

  assert {
    condition     = output.ingress_rule.origin_request.http_host_header == "vault.fabriciooml.dev"
    error_message = "origin_request.http_host_header must pass through when the origin needs a specific host header"
  }
}
