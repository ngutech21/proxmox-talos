terraform {
  required_version = ">= 1.14.7"

  required_providers {
    local = {
      source  = "hashicorp/local"
      version = "~> 2.7"
    }

    talos = {
      source  = "siderolabs/talos"
      version = "~> 0.10.1"
    }
  }
}

locals {
  longhorn_mount_path   = "/var/mnt/longhorn"
  cluster_generated_dir = "${path.module}/../03-infrastructure/clusters/${var.cluster_name}/.generated"
  metallb_generated_dir = "${local.cluster_generated_dir}/metallb"
  pgadmin_generated_dir = "${local.cluster_generated_dir}/pgadmin"

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
        node.role == "worker" && var.worker_data_disk_size_gb > 0 ? {
          kubelet = {
            extraMounts = [
              {
                destination = local.longhorn_mount_path
                type        = "bind"
                source      = local.longhorn_mount_path
                options     = ["bind", "rshared", "rw"]
              }
            ]
          }
        } : {}
      )

      cluster = {
        network = {
          dnsDomain = var.talos_dns_domain
        }
      }
    })
  }
}

locals {
  longhorn_volume_documents = {
    for name, node in local.nodes_by_name : name => (
      node.role == "worker" && var.worker_data_disk_size_gb > 0 ? yamlencode({
        apiVersion = "v1alpha1"
        kind       = "UserVolumeConfig"
        name       = "longhorn"
        volumeType = "disk"
        provisioning = {
          diskSelector = {
            match = "disk.dev_path == '/dev/sdb'"
          }
        }
      }) : null
    )
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

locals {
  rendered_machine_configuration = {
    for name, config in data.talos_machine_configuration.node :
    name => join("\n---\n", compact([
      config.machine_configuration,
      local.longhorn_volume_documents[name],
    ]))
  }
}

locals {
  metallb_ip_address_pool = yamlencode({
    apiVersion = "metallb.io/v1beta1"
    kind       = "IPAddressPool"
    metadata = {
      name      = "lan-pool"
      namespace = "metallb-system"
    }
    spec = {
      addresses = var.metallb_addresses
    }
  })

  metallb_generated_kustomization = yamlencode({
    apiVersion = "kustomize.config.k8s.io/v1beta1"
    kind       = "Kustomization"
    resources = [
      "ip-address-pool.yaml",
    ]
  })

  pgadmin_values_patch = yamlencode({
    apiVersion = "helm.toolkit.fluxcd.io/v2"
    kind       = "HelmRelease"
    metadata = {
      name      = "pgadmin"
      namespace = "flux-system"
    }
    spec = {
      values = {
        env = {
          email = "pgadmin@${var.base_domain}"
        }
        persistentVolume = {
          size = var.pgadmin_storage_size
        }
        ingress = {
          hosts = [
            {
              host = "pgadmin.${var.base_domain}"
              paths = [
                {
                  path     = "/"
                  pathType = "Prefix"
                }
              ]
            }
          ]
        }
      }
    }
  })

  pgadmin_generated_kustomization = yamlencode({
    apiVersion = "kustomize.config.k8s.io/v1beta1"
    kind       = "Kustomization"
    resources = [
      "../../../../apps/pgadmin",
    ]
    patchesStrategicMerge = [
      "values-patch.yaml",
    ]
  })
}

resource "talos_machine_configuration_apply" "node" {
  for_each = local.nodes_by_name

  depends_on = [
    terraform_data.bootstrap_endpoints_ready
  ]

  client_configuration        = talos_machine_secrets.cluster.client_configuration
  machine_configuration_input = local.rendered_machine_configuration[each.key]
  apply_mode                  = "reboot"
  endpoint                    = local.bootstrap_endpoints[each.key]
  node                        = local.bootstrap_endpoints[each.key]

  timeouts = {
    create = "20m"
    update = "20m"
  }
}

resource "local_sensitive_file" "machine_config" {
  for_each = data.talos_machine_configuration.node

  content  = local.rendered_machine_configuration[each.key]
  filename = "${path.module}/.generated/${each.key}.yaml"
}

resource "local_sensitive_file" "talosconfig" {
  content  = data.talos_client_configuration.cluster.talos_config
  filename = "${path.module}/.generated/talosconfig"
}

resource "local_file" "metallb_ip_address_pool" {
  content  = local.metallb_ip_address_pool
  filename = "${local.metallb_generated_dir}/ip-address-pool.yaml"
}

resource "local_file" "metallb_generated_kustomization" {
  content  = local.metallb_generated_kustomization
  filename = "${local.metallb_generated_dir}/kustomization.yaml"
}

resource "local_file" "pgadmin_values_patch" {
  content  = local.pgadmin_values_patch
  filename = "${local.pgadmin_generated_dir}/values-patch.yaml"
}

resource "local_file" "pgadmin_generated_kustomization" {
  content  = local.pgadmin_generated_kustomization
  filename = "${local.pgadmin_generated_dir}/kustomization.yaml"
}
