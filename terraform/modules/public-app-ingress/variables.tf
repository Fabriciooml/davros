variable "app_name" {
  type = string
}

variable "domain" {
  type = string
}

variable "zone_id" {
  type = string
}

variable "tunnel_id" {
  type = string
}

variable "target_url" {
  type        = string
  description = "Internal address the tunnel forwards this hostname's traffic to, e.g. http://<traefik-lb-ip>:80."
}

variable "origin_request" {
  type = object({
    no_tls_verify    = optional(bool)
    http_host_header = optional(string)
  })
  default     = null
  description = "Per-app tunnel origin overrides, for origins that need a self-signed cert accepted or a specific Host header."
}
