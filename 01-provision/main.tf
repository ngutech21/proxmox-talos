terraform {
  required_version = ">= 1.14.7"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.98.1"
    }
  }
}

locals {
  enabled_nodes = [
    for node in var.cluster_nodes : merge(node, {
      cores     = coalesce(try(node.cores, null), var.vm_cores)
      memory_mb = coalesce(try(node.memory_mb, null), var.vm_memory_mb)
      disk_gb   = coalesce(try(node.disk_gb, null), var.vm_disk_size_gb)
      tags      = distinct(concat(var.vm_tags, coalesce(try(node.tags, null), [])))
    })
    if try(node.enabled, true)
  ]

  control_plane_nodes = [
    for node in local.enabled_nodes : node
    if node.role == "control_plane"
  ]

  worker_nodes = [
    for node in local.enabled_nodes : node
    if node.role == "worker"
  ]

  image_file_id = "${var.talos_image_datastore}:import/${var.talos_image_filename}"
}

provider "proxmox" {
  endpoint  = var.proxmox_api_url
  api_token = "${var.proxmox_api_token_id}=${var.proxmox_api_token_secret}"
  insecure  = var.proxmox_insecure_tls
}

resource "proxmox_virtual_environment_vm" "talos_node" {
  for_each        = { for node in local.enabled_nodes : node.name => node }
  name            = each.value.name
  description     = "Talos ${each.value.role} node for ${var.cluster_name}"
  node_name       = each.value.proxmox_node
  vm_id           = each.value.vm_id
  started         = true
  on_boot         = true
  stop_on_destroy = true
  machine         = "q35"
  scsi_hardware   = var.vm_scsi_hardware

  tags = distinct(concat(["terraform", "talos"], each.value.tags))

  agent {
    enabled = true
    timeout = "10m"

    wait_for_ip {
      ipv4 = true
    }
  }

  cpu {
    cores = each.value.cores
    type  = "host"
  }

  memory {
    dedicated = each.value.memory_mb
  }

  operating_system {
    type = "l26"
  }

  disk {
    datastore_id = var.vm_disk_datastore
    import_from  = local.image_file_id
    interface    = "scsi0"
    file_format  = "raw"
    size         = each.value.disk_gb
    discard      = "on"
    iothread     = true
    ssd          = true
  }

  dynamic "disk" {
    for_each = each.value.role == "worker" && var.worker_data_disk_size_gb > 0 ? [1] : []

    content {
      datastore_id = var.vm_disk_datastore
      interface    = "scsi1"
      file_format  = "raw"
      size         = var.worker_data_disk_size_gb
      discard      = "on"
      iothread     = true
      ssd          = true
    }
  }

  network_device {
    bridge = var.vm_network_bridge
    model  = "virtio"
    queues = each.value.role == "worker" ? var.worker_vm_network_queues : 0
  }

  serial_device {}

  rng {
    source = "/dev/urandom"
  }

  lifecycle {
    precondition {
      condition     = trimspace(try(each.value.proxmox_node, "")) != ""
      error_message = "Each enabled node must define proxmox_node."
    }

    precondition {
      condition     = try(each.value.cores, 0) > 0
      error_message = "Each enabled node must define cores > 0."
    }

    precondition {
      condition     = try(each.value.memory_mb, 0) > 0
      error_message = "Each enabled node must define memory_mb > 0."
    }

    precondition {
      condition     = try(each.value.disk_gb, 0) > 0
      error_message = "Each enabled node must define disk_gb > 0."
    }
  }
}

locals {
  node_runtime_details = [
    for node in local.enabled_nodes : {
      name         = node.name
      role         = node.role
      proxmox_node = node.proxmox_node
      vm_id        = node.vm_id
      ip           = node.ip
      current_ip = try([
        for address in flatten(proxmox_virtual_environment_vm.talos_node[node.name].ipv4_addresses) : address
        if address != "" && !startswith(address, "127.") && !startswith(address, "169.254.")
      ][0], null)
      current_ips = try([
        for address in flatten(proxmox_virtual_environment_vm.talos_node[node.name].ipv4_addresses) : address
        if address != "" && !startswith(address, "127.") && !startswith(address, "169.254.")
      ], [])
      network_interface_names = try(flatten(proxmox_virtual_environment_vm.talos_node[node.name].network_interface_names), [])
      mac_addresses           = try(flatten(proxmox_virtual_environment_vm.talos_node[node.name].mac_addresses), [])
    }
  ]
}

output "cluster_name" {
  description = "Cluster name from the Terraform cluster definition"
  value       = var.cluster_name
}

output "api_vip" {
  description = "API VIP reserved for the Talos control plane"
  value       = var.api_vip
}

output "image_file_id" {
  description = "Imported Talos raw image file ID used by VM disks"
  value       = local.image_file_id
}

output "node_details" {
  description = "Details for all enabled nodes"
  value       = local.node_runtime_details
}

output "control_plane_ips" {
  description = "IP addresses of enabled control-plane nodes"
  value       = [for node in local.control_plane_nodes : node.ip]
}

output "worker_ips" {
  description = "IP addresses of enabled worker nodes"
  value       = [for node in local.worker_nodes : node.ip]
}

output "bootstrap_endpoints" {
  description = "Current IPv4 addresses discovered via the QEMU guest agent for each enabled node"
  value = {
    for node in local.node_runtime_details : node.name => node.current_ip
  }
}
