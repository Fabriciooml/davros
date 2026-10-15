variable "account_id" {
  type = string
}

variable "zone_id" {
  type = string
}

variable "tunnel_id" {
  type = string
}

variable "domain" {
  type = string
}

variable "public_apps" {
  type = map(object({
    target_url = string
    origin_request = optional(object({
      no_tls_verify    = optional(bool)
      http_host_header = optional(string)
    }))
  }))
  default = {}
}
