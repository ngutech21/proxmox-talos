variable "proxmox_api_url" {
  description = "Proxmox API endpoint, declared here so the shared tfvars file can be reused across both Terraform stages"
  type        = string
}

variable "proxmox_api_token_id" {
  description = "Proxmox API token ID, declared here so the shared secrets tfvars file can be reused across both Terraform stages"
  type        = string
  sensitive   = true
}

variable "proxmox_api_token_secret" {
  description = "Proxmox API token secret, declared here so the shared secrets tfvars file can be reused across both Terraform stages"
  type        = string
  sensitive   = true
}

variable "proxmox_insecure_tls" {
  description = "Whether Proxmox uses an insecure certificate, declared here so the shared tfvars file can be reused across both Terraform stages"
  type        = bool
  default     = true
}

variable "cluster_name" {
  description = "Logical Talos cluster name"
  type        = string

  validation {
    condition     = trimspace(var.cluster_name) != ""
    error_message = "cluster_name must not be empty."
  }
}

variable "api_vip" {
  description = "Talos control-plane VIP and Kubernetes API endpoint"
  type        = string

  validation {
    condition     = trimspace(var.api_vip) != ""
    error_message = "api_vip must not be empty."
  }
}

variable "talos_image_datastore" {
  description = "Talos raw image datastore, declared here so the shared tfvars file can be reused across both Terraform stages"
  type        = string
}

variable "talos_image_filename" {
  description = "Talos raw image filename, declared here so the shared tfvars file can be reused across both Terraform stages"
  type        = string
}

variable "talos_install_disk" {
  description = "Install disk path used in Talos machine configs"
  type        = string
  default     = "/dev/sda"

  validation {
    condition     = trimspace(var.talos_install_disk) != ""
    error_message = "talos_install_disk must not be empty."
  }
}

variable "talos_installer_image" {
  description = "Talos installer image that matches the boot image build"
  type        = string

  validation {
    condition     = trimspace(var.talos_installer_image) != ""
    error_message = "talos_installer_image must not be empty."
  }
}

variable "talos_version" {
  description = "Talos version used for generated machine configs and machine secrets"
  type        = string

  validation {
    condition     = trimspace(var.talos_version) != ""
    error_message = "talos_version must not be empty."
  }
}

variable "talos_kubernetes_version" {
  description = "Optional Kubernetes version override for generated Talos machine configs"
  type        = string
  default     = ""
}

variable "talos_dns_domain" {
  description = "Kubernetes DNS domain inside the Talos cluster"
  type        = string
  default     = "cluster.local"

  validation {
    condition     = trimspace(var.talos_dns_domain) != ""
    error_message = "talos_dns_domain must not be empty."
  }
}

variable "base_domain" {
  description = "Base domain used for ingress hosts and app-local email addresses"
  type        = string
  default     = "home.arpa"

  validation {
    condition     = trimspace(var.base_domain) != ""
    error_message = "base_domain must not be empty."
  }
}

variable "cluster_nodes" {
  description = "Explicit Talos node definitions shared with the provisioning stage"
  type = list(object({
    name         = string
    role         = string
    proxmox_node = string
    vm_id        = number
    ip           = string
    cores        = optional(number)
    memory_mb    = optional(number)
    disk_gb      = optional(number)
    tags         = optional(list(string))
    enabled      = optional(bool, true)
  }))

  validation {
    condition = length([
      for n in var.cluster_nodes : n
      if contains(["control_plane", "worker"], n.role)
    ]) == length(var.cluster_nodes)
    error_message = "Each cluster_nodes.role must be one of: control_plane, worker."
  }

  validation {
    condition = length([
      for n in var.cluster_nodes : n
      if try(n.enabled, true) && n.role == "control_plane"
    ]) > 0
    error_message = "At least one enabled control_plane node is required in cluster_nodes."
  }
}

variable "vm_cores" {
  description = "Default number of vCPU cores per VM, declared here so the shared tfvars file can be reused across both Terraform stages"
  type        = number
  default     = 2
}

variable "vm_memory_mb" {
  description = "Default VM memory, declared here so the shared tfvars file can be reused across both Terraform stages"
  type        = number
  default     = 4096
}

variable "vm_disk_datastore" {
  description = "VM disk datastore, declared here so the shared tfvars file can be reused across both Terraform stages"
  type        = string
  default     = "local-lvm"
}

variable "vm_disk_size_gb" {
  description = "VM disk size, declared here so the shared tfvars file can be reused across both Terraform stages"
  type        = number
  default     = 40
}

variable "worker_data_disk_size_gb" {
  description = "Additional worker-only data disk size in GB, declared here so the shared tfvars file can be reused across both Terraform stages"
  type        = number
  default     = 100

  validation {
    condition     = var.worker_data_disk_size_gb >= 0
    error_message = "worker_data_disk_size_gb must be greater than or equal to 0."
  }
}

variable "vm_network_bridge" {
  description = "VM network bridge, declared here so the shared tfvars file can be reused across both Terraform stages"
  type        = string
  default     = "vmbr0"
}

variable "vm_ip_cidr" {
  description = "CIDR prefix length used for Talos static networking"
  type        = number
  default     = 24

  validation {
    condition     = var.vm_ip_cidr >= 1 && var.vm_ip_cidr <= 32
    error_message = "vm_ip_cidr must be between 1 and 32."
  }
}

variable "vm_gateway" {
  description = "Default gateway used for Talos static networking"
  type        = string
  default     = "192.168.178.1"

  validation {
    condition     = trimspace(var.vm_gateway) != ""
    error_message = "vm_gateway must not be empty."
  }
}

variable "vm_dns_servers" {
  description = "DNS servers used for Talos static networking"
  type        = list(string)
  default     = ["1.1.1.1"]

  validation {
    condition     = length(var.vm_dns_servers) > 0
    error_message = "vm_dns_servers must contain at least one server."
  }
}

variable "vm_tags" {
  description = "VM tags, declared here so the shared tfvars file can be reused across both Terraform stages"
  type        = list(string)
  default     = []
}

variable "metallb_addresses" {
  description = "MetalLB address ranges for the cluster-specific IPAddressPool"
  type        = list(string)

  validation {
    condition     = length(var.metallb_addresses) > 0
    error_message = "metallb_addresses must contain at least one address range."
  }
}

variable "pgadmin_storage_size" {
  description = "Persistent volume size for the pgAdmin workload"
  type        = string
  default     = "5Gi"

  validation {
    condition     = trimspace(var.pgadmin_storage_size) != ""
    error_message = "pgadmin_storage_size must not be empty."
  }
}
