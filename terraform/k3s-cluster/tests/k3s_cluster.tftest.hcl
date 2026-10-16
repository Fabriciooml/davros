mock_provider "proxmox" {
  override_resource {
    target = proxmox_virtual_environment_download_file.debian_template
    values = {
      id = "local:vztmpl/debian-12-standard_12.12-1_amd64.tar.zst"
    }
  }
}

run "variables_have_expected_defaults" {
  command = plan

  variables {
    proxmox_api_endpoint = "https://192.168.31.42:8006/"
    proxmox_api_token    = "test-token"
    proxmox_host         = "192.168.31.42"
    proxmox_node         = "local"
    datastore_id         = "local-lvm"
    vm_id                = 240
    node_ip              = "192.168.31.240"
    gateway              = "192.168.31.1"
  }

  assert {
    condition     = var.cpu_cores == 2
    error_message = "cpu_cores must default to 2"
  }

  assert {
    condition     = var.memory_mb == 4096
    error_message = "memory_mb must default to 4096"
  }

  assert {
    condition     = var.disk_gb == 32
    error_message = "disk_gb must default to 32"
  }
}

run "container_has_static_ip_and_correct_sizing" {
  command = plan

  variables {
    proxmox_api_endpoint = "https://192.168.31.42:8006/"
    proxmox_api_token    = "test-token"
    proxmox_host         = "192.168.31.42"
    proxmox_node         = "local"
    datastore_id         = "local-lvm"
    vm_id                = 240
    node_ip              = "192.168.31.240"
    gateway              = "192.168.31.1"
  }

  # proxmox hardcodes both "creating" and "changing feature flags for" a
  # privileged container to root@pam only, and unprivileged/features can't
  # be changed on an existing container at all (`pct set -unprivileged`
  # errors "unable to modify read-only option"). So the container is
  # created entirely over root ssh via `pct create` in null_resource.container
  # (see main.tf), not as a declarative proxmox_virtual_environment_container
  # resource. Its triggers map is still built entirely from plan-time-known
  # variables (plus the mocked template id above), so it's still worth
  # asserting on directly, even though the actual `pct create` invocation
  # itself is only exercised for real during the actual apply.
  assert {
    condition     = null_resource.container.triggers.vm_id == "240"
    error_message = "container must be created with the configured vm_id"
  }

  assert {
    condition     = null_resource.container.triggers.node_ip == "192.168.31.240"
    error_message = "container must get a static ip, not dhcp"
  }

  assert {
    condition     = null_resource.container.triggers.gateway == "192.168.31.1"
    error_message = "container must use the configured gateway"
  }

  assert {
    condition     = null_resource.container.triggers.template_file_id == "local:vztmpl/debian-12-standard_12.12-1_amd64.tar.zst"
    error_message = "container must be created from the downloaded debian template"
  }

  assert {
    condition     = null_resource.container.triggers.cpu_cores == "2"
    error_message = "container cpu cores must match cpu_cores variable default"
  }

  assert {
    condition     = null_resource.container.triggers.memory_mb == "4096"
    error_message = "container memory must match memory_mb variable default"
  }

  assert {
    condition     = output.ip_address == "192.168.31.240"
    error_message = "ip_address output must be the bare node ip"
  }

  assert {
    condition     = output.hostname == "k3s-node"
    error_message = "hostname output must be k3s-node"
  }
}
