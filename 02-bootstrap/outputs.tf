output "api_vip" {
  description = "API VIP used by the Talos control plane"
  value       = var.api_vip
}

output "control_plane_ips" {
  description = "Final static IPv4 addresses of control-plane nodes"
  value       = local.control_plane_ips
}

output "worker_ips" {
  description = "Final static IPv4 addresses of worker nodes"
  value       = local.worker_ips
}

output "bootstrap_endpoints" {
  description = "Initial IPv4 addresses discovered via the Proxmox guest agent before Talos applies static node networking"
  value       = local.bootstrap_endpoints
}

output "talosconfig" {
  description = "Talos client configuration"
  value       = data.talos_client_configuration.cluster.talos_config
  sensitive   = true
}

output "kubeconfig" {
  description = "Kubernetes client configuration"
  value       = talos_cluster_kubeconfig.cluster.kubeconfig_raw
  sensitive   = true
}

output "cluster_info" {
  description = "High-level cluster access information"
  value = {
    api_vip           = var.api_vip
    control_plane_ips = local.control_plane_ips
    worker_ips        = local.worker_ips
    talosconfig_path  = "${path.module}/.generated/talosconfig"
    kubeconfig_path   = "${path.module}/.generated/kubeconfig"
  }
}
