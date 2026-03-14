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
  longhorn_mount_path         = "/var/mnt/longhorn"
  cluster_generated_dir       = "${path.module}/../03-infrastructure/clusters/${var.cluster_name}/.generated"
  metallb_generated_dir       = "${local.cluster_generated_dir}/metallb"
  pgadmin_generated_dir       = "${local.cluster_generated_dir}/pgadmin"
  polaris_generated_dir       = "${local.cluster_generated_dir}/polaris"
  observability_generated_dir = "${local.cluster_generated_dir}/observability"
  alloy_generated_dir         = "${local.cluster_generated_dir}/alloy"

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
            match = "'/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi1' in disk.symlinks"
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

  resolved_prometheus_host = trimspace(var.prometheus_host) != "" ? var.prometheus_host : "prometheus.${var.base_domain}"

  pgadmin_values_patch = <<-EOT
    - op: add
      path: /spec/values/env
      value:
        email: pgadmin@home.de
    - op: replace
      path: /spec/values/persistentVolume/size
      value: ${var.pgadmin_storage_size}
    - op: replace
      path: /spec/values/ingress/hosts
      value:
        - host: pgadmin.${var.base_domain}
          paths:
            - path: /
              pathType: Prefix
  EOT

  pgadmin_generated_kustomization = yamlencode({
    apiVersion = "kustomize.config.k8s.io/v1beta1"
    kind       = "Kustomization"
    resources = concat(
      [
        "../../../../apps/pgadmin",
      ],
      fileexists("${local.pgadmin_generated_dir}/credentials-secret.sops.yaml") ? [
        "credentials-secret.sops.yaml",
      ] : []
    )
    patches = [
      {
        path = "values-patch.yaml"
        target = {
          group     = "helm.toolkit.fluxcd.io"
          version   = "v2"
          kind      = "HelmRelease"
          name      = "pgadmin"
          namespace = "flux-system"
        }
      },
    ]
  })

  polaris_values_patch = <<-EOT
    - op: replace
      path: /spec/values/dashboard/ingress/hosts
      value:
        - ${var.polars_host}
  EOT

  polaris_generated_kustomization = yamlencode({
    apiVersion = "kustomize.config.k8s.io/v1beta1"
    kind       = "Kustomization"
    resources = [
      "../../../../apps/polaris",
    ]
    patches = [
      {
        path = "values-patch.yaml"
        target = {
          group     = "helm.toolkit.fluxcd.io"
          version   = "v2"
          kind      = "HelmRelease"
          name      = "polaris"
          namespace = "flux-system"
        }
      },
    ]
  })

  observability_values_patch = <<-EOT
    - op: add
      path: /spec/values/prometheus/ingress
      value:
        enabled: true
        ingressClassName: traefik
        hosts:
          - ${local.resolved_prometheus_host}
        paths:
          - /
        pathType: Prefix
    - op: add
      path: /spec/values/prometheus/prometheusSpec/externalUrl
      value: http://${local.resolved_prometheus_host}
  EOT

  observability_generated_kustomization = <<-EOT
    apiVersion: kustomize.config.k8s.io/v1beta1
    kind: Kustomization
    resources:
    - ../../../../infrastructure/observability
    patches:
    - path: values-patch.yaml
      target:
        group: helm.toolkit.fluxcd.io
        version: v2
        kind: HelmRelease
        name: kube-prometheus-stack
        namespace: flux-system
  EOT

  alloy_values_patch = <<-EOT
    - op: add
      path: /spec/values/alloy
      value:
        configMap:
          content: |
            logging {
              level  = "info"
              format = "logfmt"
            }

            discovery.kubernetes "pod" {
              role = "pod"
            }

            discovery.relabel "pod_logs" {
              targets = discovery.kubernetes.pod.targets

              rule {
                source_labels = ["__meta_kubernetes_namespace"]
                action        = "replace"
                target_label  = "namespace"
              }

              rule {
                source_labels = ["__meta_kubernetes_pod_name"]
                action        = "replace"
                target_label  = "pod"
              }

              rule {
                source_labels = ["__meta_kubernetes_pod_container_name"]
                action        = "replace"
                target_label  = "container"
              }

              rule {
                source_labels = ["__meta_kubernetes_pod_node_name"]
                action        = "replace"
                target_label  = "node"
              }

              rule {
                source_labels = ["__meta_kubernetes_pod_label_app_kubernetes_io_name"]
                action        = "replace"
                target_label  = "app"
              }

              rule {
                source_labels = ["__meta_kubernetes_namespace", "__meta_kubernetes_pod_container_name"]
                action        = "replace"
                target_label  = "job"
                separator     = "/"
                replacement   = "$1"
              }

              rule {
                source_labels = ["__meta_kubernetes_pod_container_id"]
                action        = "replace"
                target_label  = "container_runtime"
                regex         = `^(\\S+):\\/\\/.+$`
                replacement   = "$1"
              }
            }

            loki.source.kubernetes "pod_logs" {
              targets    = discovery.relabel.pod_logs.output
              forward_to = [loki.process.pod_logs.receiver]
            }

            loki.process "pod_logs" {
              stage.static_labels {
                values = {
                  cluster = "${var.cluster_name}",
                }
              }

              forward_to = [loki.write.external.receiver]
            }

            loki.write "external" {
              endpoint {
                url = "${var.loki_push_url}"
              }
            }
  EOT

  alloy_generated_kustomization = <<-EOT
    apiVersion: kustomize.config.k8s.io/v1beta1
    kind: Kustomization
    resources:
    - ../../../../infrastructure/alloy/core
    patches:
    - path: values-patch.yaml
      target:
        group: helm.toolkit.fluxcd.io
        version: v2
        kind: HelmRelease
        name: alloy
        namespace: flux-system
  EOT
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

resource "local_file" "polaris_values_patch" {
  content  = local.polaris_values_patch
  filename = "${local.polaris_generated_dir}/values-patch.yaml"
}

resource "local_file" "polaris_generated_kustomization" {
  content  = local.polaris_generated_kustomization
  filename = "${local.polaris_generated_dir}/kustomization.yaml"
}

resource "local_file" "observability_values_patch" {
  content  = local.observability_values_patch
  filename = "${local.observability_generated_dir}/values-patch.yaml"
}

resource "local_file" "observability_generated_kustomization" {
  content  = local.observability_generated_kustomization
  filename = "${local.observability_generated_dir}/kustomization.yaml"
}

resource "local_file" "alloy_values_patch" {
  content  = local.alloy_values_patch
  filename = "${local.alloy_generated_dir}/values-patch.yaml"
}

resource "local_file" "alloy_generated_kustomization" {
  content  = local.alloy_generated_kustomization
  filename = "${local.alloy_generated_dir}/kustomization.yaml"
}
