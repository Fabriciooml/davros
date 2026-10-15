mock_provider "proxmox" {}
provider "talos" {}

run "three_control_plane_nodes_get_distinct_ips_and_shared_vip" {
  command = plan

  override_resource {
    target = proxmox_download_file.talos_iso
    values = {
      id = "local:iso/talos-v1.9.0-test.iso"
    }
  }

  variables {
    proxmox_api_endpoint = "https://test-pve.invalid:8006"
    proxmox_api_token    = "test-token"
  }

  assert {
    condition     = length(output.node_ips) == 3
    error_message = "cluster must provision exactly 3 control-plane nodes"
  }

  assert {
    condition     = length(distinct(values(output.node_ips))) == 3
    error_message = "every node must get a distinct IP address"
  }

  assert {
    condition     = output.node_ips["cp-0"] == "192.168.31.240"
    error_message = "first control-plane node must get the first host address in the carved CIDR"
  }

  assert {
    condition     = output.node_ips["cp-2"] == "192.168.31.242"
    error_message = "third control-plane node must get the third host address in the carved CIDR"
  }

  assert {
    condition = alltrue([
      for hostname in values(output.node_hostnames) : can(regex("^talos-control-plane-[0-2]$", hostname))
    ])
    error_message = "every node hostname must encode its control-plane role and index"
  }

  assert {
    condition     = output.vip_address == "192.168.31.243"
    error_message = "with the default 3 control-plane/0 worker topology the vip must sit right after the 3 node IPs"
  }
}

run "control_plane_and_worker_counts_are_configurable" {
  command = plan

  override_resource {
    target = proxmox_download_file.talos_iso
    values = {
      id = "local:iso/talos-v1.9.0-test.iso"
    }
  }

  variables {
    proxmox_api_endpoint = "https://test-pve.invalid:8006"
    proxmox_api_token    = "test-token"
    control_plane_count  = 2
    worker_count         = 2
  }

  assert {
    condition     = length(output.node_ips) == 4
    error_message = "node count must follow control_plane_count + worker_count"
  }

  assert {
    condition     = length(distinct(values(output.node_ips))) == 4
    error_message = "every node must still get a distinct IP address"
  }

  assert {
    condition     = output.node_ips["cp-0"] == "192.168.31.240" && output.node_ips["cp-1"] == "192.168.31.241"
    error_message = "control-plane nodes must occupy the first offsets"
  }

  assert {
    condition     = output.node_ips["worker-0"] == "192.168.31.242" && output.node_ips["worker-1"] == "192.168.31.243"
    error_message = "worker nodes must occupy the offsets right after the control-plane nodes, not collide with them"
  }

  assert {
    condition     = output.vip_address == "192.168.31.244"
    error_message = "vip must move to the offset right after all nodes, so it never collides with a worker IP"
  }
}
