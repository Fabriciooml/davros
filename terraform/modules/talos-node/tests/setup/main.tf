terraform {
  required_providers {
    talos = {
      source = "siderolabs/talos"
    }
    proxmox = {
      source = "bpg/proxmox"
    }
  }
}

resource "talos_machine_secrets" "this" {}

output "machine_secrets" {
  value     = talos_machine_secrets.this.machine_secrets
  sensitive = true
}

output "client_configuration" {
  value     = talos_machine_secrets.this.client_configuration
  sensitive = true
}
