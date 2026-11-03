run "defaults_are_small_and_point_at_pihole" {
  command = plan

  variables {
    proxmox_host = "192.168.31.42"
    datastore_id = "local-lvm"
    vm_id        = 241
    node_ip      = "192.168.31.241"
    gateway      = "192.168.31.1"
  }

  assert {
    condition     = var.cpu_cores == 1 && var.memory_mb == 256 && var.disk_gb == 2
    error_message = "ts-router must default to 1 core, 256 MB RAM, 2 GB disk"
  }

  assert {
    condition     = var.nameserver == "192.168.31.152"
    error_message = "nameserver must default to the Pi-hole"
  }

  assert {
    condition     = var.advertise_route == "192.168.31.0/24"
    error_message = "advertised route must default to the LAN"
  }
}

run "container_is_static_and_has_tun_passthrough" {
  command = plan

  variables {
    proxmox_host = "192.168.31.42"
    datastore_id = "local-lvm"
    vm_id        = 241
    node_ip      = "192.168.31.241"
    gateway      = "192.168.31.1"
  }

  assert {
    condition     = null_resource.container.triggers.vm_id == "241"
    error_message = "container must use the configured vm_id"
  }

  assert {
    condition     = null_resource.container.triggers.node_ip == "192.168.31.241"
    error_message = "container must get a static ip, not dhcp"
  }

  assert {
    condition     = null_resource.container.triggers.advertise_route == "192.168.31.0/24"
    error_message = "container must advertise the LAN route"
  }

  assert {
    condition     = strcontains(null_resource.container.triggers.lxc_conf, "lxc.cgroup2.devices.allow: c 10:200 rwm")
    error_message = "lxc conf must allow the tun device"
  }

  assert {
    condition     = strcontains(null_resource.container.triggers.lxc_conf, "lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file")
    error_message = "lxc conf must bind-mount /dev/net/tun"
  }

  assert {
    condition     = output.ip_address == "192.168.31.241" && output.hostname == "ts-router"
    error_message = "outputs must be the bare ip and ts-router"
  }
}
