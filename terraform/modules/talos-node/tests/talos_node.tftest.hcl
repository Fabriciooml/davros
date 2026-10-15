mock_provider "proxmox" {}
provider "talos" {}

run "setup" {
  command = apply

  module {
    source = "./tests/setup"
  }
}

run "cp_node_zero_gets_first_ip_and_sizing" {
  command = plan

  variables {
    role             = "control-plane"
    index            = 0
    cpu_cores        = 2
    memory_mb        = 3072
    disk_gb          = 32
    network_cidr     = "192.168.31.240/29"
    gateway          = "192.168.31.1"
    proxmox_node     = "local"
    datastore_id     = "HD_2TB"
    vm_id            = 240
    boot_iso_file_id = "local:iso/test-talos.iso"

    cluster_name         = "davros"
    cluster_endpoint     = "https://192.168.31.243:6443"
    machine_secrets      = run.setup.machine_secrets
    client_configuration = run.setup.client_configuration
    install_image        = "factory.talos.dev/metal-installer/test-schematic-id:v1.9.0"
    talos_version        = "v1.9.0"
    kubernetes_version   = "v1.32.0"
  }

  assert {
    condition     = output.ip_address == "192.168.31.240"
    error_message = "first control-plane node must get the first host address in the carved CIDR"
  }

  assert {
    condition     = output.hostname == "talos-control-plane-0"
    error_message = "hostname must encode role and index"
  }

  assert {
    condition     = proxmox_virtual_environment_vm.this.cpu[0].cores == 2
    error_message = "vm cpu cores must match the cpu_cores input"
  }

  assert {
    condition     = proxmox_virtual_environment_vm.this.agent[0].enabled == true
    error_message = "qemu guest agent must be enabled so terraform can read the node's current dhcp ip during initial bootstrap, before our static config is applied"
  }

  assert {
    condition     = proxmox_virtual_environment_vm.this.network_device[0].mac_address == "BC:24:11:00:00:F0"
    error_message = "mac address must be deterministic (derived from vm_id), so a dhcp reservation can be made before the vm ever boots, giving it the same ip in maintenance mode and after our static config is applied"
  }

  assert {
    condition     = proxmox_virtual_environment_vm.this.cpu[0].type == "host"
    error_message = "vm must pass through the real host cpu, the default qemu64 virtual cpu lacks modern instruction sets (aes-ni etc) talos' kernel can hang or crash-loop on"
  }

  assert {
    condition     = proxmox_virtual_environment_vm.this.memory[0].dedicated == 3072
    error_message = "vm memory must match the memory_mb input"
  }

  assert {
    condition     = proxmox_virtual_environment_vm.this.cdrom[0].file_id == "local:iso/test-talos.iso"
    error_message = "vm must boot the talos image factory iso"
  }

  assert {
    condition     = proxmox_virtual_environment_vm.this.cdrom[0].interface == "ide3"
    error_message = "install iso must sit on ide3 since the initialization block's own cloud-init drive takes ide2"
  }

  assert {
    condition     = proxmox_virtual_environment_vm.this.boot_order[0] == "scsi0" && proxmox_virtual_environment_vm.this.boot_order[1] == "ide3"
    error_message = "boot order must try the disk first (empty on first boot, falls through) before the install iso on ide3, not the unrelated ide2 cloud-init drive"
  }

  assert {
    condition     = proxmox_virtual_environment_vm.this.network_device[0].bridge == "vmbr0"
    error_message = "vm must have a network device attached on the lan bridge, otherwise it has no nic at all"
  }

  assert {
    condition     = proxmox_virtual_environment_vm.this.serial_device[0].device == "socket"
    error_message = "vm must have a serial console so talos' kernel console output is actually visible, not silently lost to a vga console nobody reads"
  }

  assert {
    condition     = proxmox_virtual_environment_vm.this.operating_system[0].type == "l26"
    error_message = "vm must be tagged as a linux 2.6+ guest, otherwise proxmox applies a generic non-linux hardware profile that can hang linux kernels during acpi/pci init"
  }
}

run "worker_node_two_gets_third_ip" {
  command = plan

  variables {
    role             = "worker"
    index            = 2
    cpu_cores        = 2
    memory_mb        = 4096
    disk_gb          = 48
    network_cidr     = "192.168.31.240/29"
    gateway          = "192.168.31.1"
    proxmox_node     = "local"
    datastore_id     = "HD_2TB"
    vm_id            = 250
    boot_iso_file_id = "local:iso/test-talos.iso"

    cluster_name         = "davros"
    cluster_endpoint     = "https://192.168.31.243:6443"
    machine_secrets      = run.setup.machine_secrets
    client_configuration = run.setup.client_configuration
    install_image        = "factory.talos.dev/metal-installer/test-schematic-id:v1.9.0"
    talos_version        = "v1.9.0"
    kubernetes_version   = "v1.32.0"
  }

  assert {
    condition     = output.ip_address == "192.168.31.242"
    error_message = "index must offset within the carved CIDR, independent of role"
  }

  assert {
    condition     = output.hostname == "talos-worker-2"
    error_message = "hostname must encode role and index"
  }
}

run "cp_node_zero_machine_config_has_hostname_and_static_ip" {
  command = plan

  variables {
    role                 = "control-plane"
    index                = 0
    cpu_cores            = 2
    memory_mb            = 3072
    disk_gb              = 32
    network_cidr         = "192.168.31.240/29"
    gateway              = "192.168.31.1"
    proxmox_node         = "local"
    datastore_id         = "HD_2TB"
    vm_id                = 240
    boot_iso_file_id     = "local:iso/test-talos.iso"
    cluster_name         = "davros"
    cluster_endpoint     = "https://192.168.31.243:6443"
    machine_secrets      = run.setup.machine_secrets
    client_configuration = run.setup.client_configuration
    install_image        = "factory.talos.dev/metal-installer/test-schematic-id:v1.9.0"
    talos_version        = "v1.9.0"
    kubernetes_version   = "v1.32.0"
  }

  assert {
    condition     = yamldecode(output.machine_config).machine.network.hostname == "talos-control-plane-0"
    error_message = "rendered machine config must set the node's hostname"
  }

  assert {
    condition     = contains(yamldecode(output.machine_config).machine.network.interfaces[0].addresses, "192.168.31.240/24")
    error_message = "rendered machine config must set the node's static IP"
  }

  assert {
    condition     = yamldecode(output.machine_config).machine.install.image == "factory.talos.dev/metal-installer/test-schematic-id:v1.9.0"
    error_message = "install image must be pinned explicitly to our schematic+version, otherwise talos defaults to its own bundled version/schematic on install, silently dropping our extensions and ignoring our version pin"
  }

  assert {
    condition     = talos_machine_configuration_apply.this.node == "192.168.31.240"
    error_message = "config must be pushed to the node's final static ip, which the mac-based dhcp reservation guarantees it already has by boot"
  }

  assert {
    condition     = talos_machine_configuration_apply.this.endpoint == "192.168.31.240"
    error_message = "endpoint must target this specific node directly, not some other cluster member"
  }

  assert {
    condition     = yamldecode(output.machine_config).machine.network.interfaces[0].interface == "ens18"
    error_message = "interface name must match the real virtio-net device name proxmox gives the vm (ens18), not a guessed eth0 that doesn't exist"
  }

  assert {
    condition     = yamldecode(output.machine_config).machine.type == "controlplane"
    error_message = "control-plane role must map to talos machine type \"controlplane\""
  }

  assert {
    condition     = yamldecode(output.machine_config).cluster.network.cni.name == "none"
    error_message = "default flannel cni must be disabled so cilium can take over"
  }

  assert {
    condition     = yamldecode(output.machine_config).cluster.proxy.disabled == true
    error_message = "kube-proxy must be disabled so cilium's replacement can take over"
  }
}

run "cp_node_machine_config_has_vip" {
  command = plan

  variables {
    role                 = "control-plane"
    index                = 1
    cpu_cores            = 2
    memory_mb            = 3072
    disk_gb              = 32
    network_cidr         = "192.168.31.240/29"
    gateway              = "192.168.31.1"
    proxmox_node         = "local"
    datastore_id         = "HD_2TB"
    vm_id                = 241
    boot_iso_file_id     = "local:iso/test-talos.iso"
    cluster_name         = "davros"
    cluster_endpoint     = "https://192.168.31.243:6443"
    machine_secrets      = run.setup.machine_secrets
    client_configuration = run.setup.client_configuration
    install_image        = "factory.talos.dev/metal-installer/test-schematic-id:v1.9.0"
    talos_version        = "v1.9.0"
    kubernetes_version   = "v1.32.0"
    vip_address          = "192.168.31.243"
  }

  assert {
    condition     = yamldecode(output.machine_config).machine.network.interfaces[0].vip.ip == "192.168.31.243"
    error_message = "control-plane node must carry the kube-vip VIP on its network interface"
  }
}

run "worker_node_machine_config_has_no_vip" {
  command = plan

  variables {
    role                 = "worker"
    index                = 2
    cpu_cores            = 2
    memory_mb            = 4096
    disk_gb              = 48
    network_cidr         = "192.168.31.240/29"
    gateway              = "192.168.31.1"
    proxmox_node         = "local"
    datastore_id         = "HD_2TB"
    vm_id                = 250
    boot_iso_file_id     = "local:iso/test-talos.iso"
    cluster_name         = "davros"
    cluster_endpoint     = "https://192.168.31.243:6443"
    machine_secrets      = run.setup.machine_secrets
    client_configuration = run.setup.client_configuration
    install_image        = "factory.talos.dev/metal-installer/test-schematic-id:v1.9.0"
    talos_version        = "v1.9.0"
    kubernetes_version   = "v1.32.0"
  }

  assert {
    condition     = try(yamldecode(output.machine_config).machine.network.interfaces[0].vip, null) == null
    error_message = "worker nodes must not carry the control-plane VIP"
  }
}
