terraform {
  required_version = ">= 1.6.0"

  required_providers {
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }

    talos = {
      source  = "siderolabs/talos"
      version = "~> 0.8.1"
    }
  }
}

locals {
  enabled_nodes = [
    for node in var.cluster_nodes : merge(node, {
      enabled = try(node.enabled, true)
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

  nodes_by_name = {
    for node in local.enabled_nodes : node.name => node
  }

  control_plane_ips = [for node in local.control_plane_nodes : node.ip]
  worker_ips        = [for node in local.worker_nodes : node.ip]

  cluster_endpoint = "https://${var.api_vip}:6443"

  provision_nodes_by_name = {
    for node in try(data.terraform_remote_state.provision.outputs.node_details, []) : node.name => node
  }

  bootstrap_endpoints = {
    for name, node in local.nodes_by_name : name => try(local.provision_nodes_by_name[name].current_ip, null)
  }

  missing_bootstrap_endpoints = [
    for name, endpoint in local.bootstrap_endpoints : name
    if endpoint == null || trimspace(endpoint) == ""
  ]

  bootstrap_node = local.control_plane_nodes[0]

  machine_config_patches = {
    for name, node in local.nodes_by_name : name => yamlencode({
      machine = merge(
        {
          install = merge(
            {
              disk = var.talos_install_disk
            },
            var.talos_installer_image != "" ? {
              image = var.talos_installer_image
            } : {}
          )

          network = {
            hostname    = node.name
            nameservers = var.vm_dns_servers
            interfaces = [
              merge(
                {
                  deviceSelector = {
                    physical = true
                  }

                  addresses = [
                    "${node.ip}/${var.vm_ip_cidr}"
                  ]

                  routes = [
                    {
                      network = "0.0.0.0/0"
                      gateway = var.vm_gateway
                    }
                  ]
                },
                node.role == "control_plane" ? {
                  vip = {
                    ip = var.api_vip
                  }
                } : {}
              )
            ]
          }
        },
        {}
      )

      cluster = {
        network = {
          dnsDomain = var.talos_dns_domain
        }
      }
    })
  }
}

data "terraform_remote_state" "provision" {
  backend = "local"

  config = {
    path = "${path.module}/../01-provision/terraform.tfstate"
  }
}

resource "terraform_data" "bootstrap_endpoints_ready" {
  input = local.bootstrap_endpoints

  lifecycle {
    precondition {
      condition     = length(local.missing_bootstrap_endpoints) == 0
      error_message = "Missing current IPv4 addresses from 01-provision for nodes: ${join(", ", local.missing_bootstrap_endpoints)}. Ensure the boot image starts qemu-guest-agent, rerun `just provision-vms`, and then rerun `just bootstrap-cluster`."
    }
  }
}

resource "talos_machine_secrets" "cluster" {
  talos_version = var.talos_version
}

data "talos_machine_configuration" "node" {
  for_each = local.nodes_by_name

  cluster_name       = var.cluster_name
  cluster_endpoint   = local.cluster_endpoint
  machine_type       = each.value.role == "control_plane" ? "controlplane" : "worker"
  machine_secrets    = talos_machine_secrets.cluster.machine_secrets
  talos_version      = var.talos_version
  kubernetes_version = var.talos_kubernetes_version != "" ? var.talos_kubernetes_version : null
  docs               = false
  examples           = false
  config_patches = [
    local.machine_config_patches[each.key]
  ]
}

data "talos_client_configuration" "cluster" {
  cluster_name         = var.cluster_name
  client_configuration = talos_machine_secrets.cluster.client_configuration
  endpoints            = local.control_plane_ips
  nodes                = [local.bootstrap_node.ip]
}

resource "talos_machine_configuration_apply" "node" {
  for_each = local.nodes_by_name

  depends_on = [
    terraform_data.bootstrap_endpoints_ready
  ]

  client_configuration        = talos_machine_secrets.cluster.client_configuration
  machine_configuration_input = data.talos_machine_configuration.node[each.key].machine_configuration
  apply_mode                  = "reboot"
  endpoint                    = local.bootstrap_endpoints[each.key]
  node                        = local.bootstrap_endpoints[each.key]

  timeouts = {
    create = "20m"
    update = "20m"
  }
}

resource "talos_machine_bootstrap" "cluster" {
  depends_on = [
    talos_machine_configuration_apply.node
  ]

  client_configuration = talos_machine_secrets.cluster.client_configuration
  endpoint             = local.bootstrap_node.ip
  node                 = local.bootstrap_node.ip

  timeouts = {
    create = "10m"
  }
}

resource "talos_cluster_kubeconfig" "cluster" {
  depends_on = [
    talos_machine_bootstrap.cluster
  ]

  client_configuration = talos_machine_secrets.cluster.client_configuration
  endpoint             = local.bootstrap_node.ip
  node                 = local.bootstrap_node.ip

  timeouts = {
    create = "10m"
    update = "10m"
  }
}

resource "local_sensitive_file" "machine_config" {
  for_each = data.talos_machine_configuration.node

  content  = each.value.machine_configuration
  filename = "${path.module}/.generated/${each.key}.yaml"
}

resource "local_sensitive_file" "talosconfig" {
  content  = data.talos_client_configuration.cluster.talos_config
  filename = "${path.module}/.generated/talosconfig"
}

resource "local_sensitive_file" "kubeconfig" {
  content  = talos_cluster_kubeconfig.cluster.kubeconfig_raw
  filename = "${path.module}/.generated/kubeconfig"
}
