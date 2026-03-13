variable "proxmox_api_url" {
  description = "Proxmox API endpoint, for example https://pve.lab.local:8006/api2/json"
  type        = string
}

variable "proxmox_api_token_id" {
  description = "Proxmox API token ID, for example terraform@pve!talos"
  type        = string
  sensitive   = true
}

variable "proxmox_api_token_secret" {
  description = "Proxmox API token secret"
  type        = string
  sensitive   = true
}

variable "proxmox_insecure_tls" {
  description = "Set to true when Proxmox uses a self-signed certificate"
  type        = bool
  default     = true
}

variable "cluster_name" {
  description = "Logical cluster name used in VM metadata"
  type        = string

  validation {
    condition     = trimspace(var.cluster_name) != ""
    error_message = "cluster_name must not be empty."
  }
}

variable "api_vip" {
  description = "Talos API VIP used by the control plane"
  type        = string

  validation {
    condition     = trimspace(var.api_vip) != ""
    error_message = "api_vip must not be empty."
  }
}

variable "talos_image_datastore" {
  description = "Datastore that contains the Talos raw image as import content"
  type        = string

  validation {
    condition     = trimspace(var.talos_image_datastore) != ""
    error_message = "talos_image_datastore must not be empty."
  }
}

variable "talos_image_filename" {
  description = "Filename of the Talos raw image in the import content store"
  type        = string

  validation {
    condition     = trimspace(var.talos_image_filename) != ""
    error_message = "talos_image_filename must not be empty."
  }
}

variable "talos_install_disk" {
  description = "Install disk path used when generating Talos machine configs"
  type        = string
  default     = "/dev/sda"

  validation {
    condition     = trimspace(var.talos_install_disk) != ""
    error_message = "talos_install_disk must not be empty."
  }
}

variable "talos_installer_image" {
  description = "Talos installer image. This must match the boot image and should include qemu guest agent support when bootstrap IP discovery relies on Proxmox guest-agent data."
  type        = string

  validation {
    condition     = trimspace(var.talos_installer_image) != ""
    error_message = "talos_installer_image must not be empty."
  }
}

variable "talos_version" {
  description = "Talos version used by the Talos Terraform provider when generating machine configs"
  type        = string

  validation {
    condition     = trimspace(var.talos_version) != ""
    error_message = "talos_version must not be empty."
  }
}

variable "talos_kubernetes_version" {
  description = "Optional Kubernetes version for generated Talos machine configs. Leave empty to use talosctl defaults."
  type        = string
  default     = ""
}

variable "talos_dns_domain" {
  description = "Kubernetes DNS domain for generated Talos machine configs"
  type        = string
  default     = "cluster.local"

  validation {
    condition     = trimspace(var.talos_dns_domain) != ""
    error_message = "talos_dns_domain must not be empty."
  }
}

variable "cluster_nodes" {
  description = "Explicit VM definitions for the Talos cluster"
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
    condition     = length(distinct([for n in var.cluster_nodes : n.name])) == length(var.cluster_nodes)
    error_message = "Each cluster_nodes.name must be unique."
  }

  validation {
    condition     = length(distinct([for n in var.cluster_nodes : n.vm_id])) == length(var.cluster_nodes)
    error_message = "Each cluster_nodes.vm_id must be unique."
  }

  validation {
    condition     = length(distinct([for n in var.cluster_nodes : n.ip])) == length(var.cluster_nodes)
    error_message = "Each cluster_nodes.ip must be unique."
  }

  validation {
    condition = length([
      for n in var.cluster_nodes : n
      if n.role == "control_plane" && try(n.enabled, true)
    ]) > 0
    error_message = "At least one enabled control_plane node is required in cluster_nodes."
  }

  validation {
    condition = length([
      for n in var.cluster_nodes : n
      if try(n.enabled, true)
    ]) > 0
    error_message = "At least one enabled node is required in cluster_nodes."
  }
}

variable "vm_cores" {
  description = "Default number of vCPU cores per VM"
  type        = number
  default     = 2

  validation {
    condition     = var.vm_cores > 0
    error_message = "vm_cores must be greater than 0."
  }
}

variable "vm_memory_mb" {
  description = "Default memory in MiB per VM"
  type        = number
  default     = 4096

  validation {
    condition     = var.vm_memory_mb > 0
    error_message = "vm_memory_mb must be greater than 0."
  }
}

variable "vm_disk_datastore" {
  description = "Datastore used for the VM disk"
  type        = string
  default     = "local-lvm"

  validation {
    condition     = trimspace(var.vm_disk_datastore) != ""
    error_message = "vm_disk_datastore must not be empty."
  }
}

variable "vm_disk_size_gb" {
  description = "Default system disk size in GB"
  type        = number
  default     = 40

  validation {
    condition     = var.vm_disk_size_gb > 0
    error_message = "vm_disk_size_gb must be greater than 0."
  }
}

variable "vm_scsi_hardware" {
  description = "SCSI controller presented to the VM"
  type        = string
  default     = "virtio-scsi-single"

  validation {
    condition     = trimspace(var.vm_scsi_hardware) != ""
    error_message = "vm_scsi_hardware must not be empty."
  }
}

variable "worker_data_disk_size_gb" {
  description = "Optional additional data disk size in GB for worker nodes. Set to 0 to disable the extra Longhorn disk."
  type        = number
  default     = 100

  validation {
    condition     = var.worker_data_disk_size_gb >= 0
    error_message = "worker_data_disk_size_gb must be greater than or equal to 0."
  }
}

variable "vm_network_bridge" {
  description = "Bridge to attach the VM NIC to"
  type        = string
  default     = "vmbr0"

  validation {
    condition     = trimspace(var.vm_network_bridge) != ""
    error_message = "vm_network_bridge must not be empty."
  }
}

variable "worker_vm_network_queues" {
  description = "Number of VirtIO multiqueue NIC queues to expose on worker nodes. Set to 0 to disable multiqueue."
  type        = number
  default     = 4

  validation {
    condition     = var.worker_vm_network_queues >= 0
    error_message = "worker_vm_network_queues must be greater than or equal to 0."
  }
}

variable "vm_ip_cidr" {
  description = "CIDR prefix length used for Talos static node networking"
  type        = number
  default     = 24

  validation {
    condition     = var.vm_ip_cidr >= 1 && var.vm_ip_cidr <= 32
    error_message = "vm_ip_cidr must be between 1 and 32."
  }
}

variable "vm_gateway" {
  description = "Default gateway used for Talos static node networking"
  type        = string
  default     = "192.168.178.1"

  validation {
    condition     = trimspace(var.vm_gateway) != ""
    error_message = "vm_gateway must not be empty."
  }
}

variable "vm_dns_servers" {
  description = "DNS servers used for Talos static node networking"
  type        = list(string)
  default     = ["1.1.1.1"]

  validation {
    condition     = length(var.vm_dns_servers) > 0
    error_message = "vm_dns_servers must contain at least one server."
  }
}

variable "vm_tags" {
  description = "Default VM tags appended to every node"
  type        = list(string)
  default     = []
}

variable "metallb_addresses" {
  description = "MetalLB address ranges, declared here so the shared tfvars file can be reused across both Terraform stages"
  type        = list(string)
  default     = []
}

variable "loki_push_url" {
  description = "External Loki push URL, declared here so the shared tfvars file can be reused across both Terraform stages"
  type        = string
  default     = ""
}
