# proxmox-talos

Declarative Talos-on-Proxmox homelab platform with a clear split between infrastructure, cluster bootstrap, and GitOps delivery.

The first implemented stage provisions Talos VMs on Proxmox with Terraform from an existing `talos-nocloud-amd64.raw` image that is already present on each target Proxmox node.

## Quick Start

1. Initialize the cluster config:

   ```bash
   just init-config
   ```

2. Edit `cluster.tfvars` with your Proxmox endpoint, network details, and node layout.

3. Edit `cluster.secrets.tfvars` with your Proxmox API token values.

4. Provision the VMs:

   ```bash
   just provision-vms
   ```

## Cluster Config

The shared root config lives in `cluster.tfvars`, following the same Terraform HCL style as `proxmox-k3s`:

```hcl
proxmox_api_url      = "https://pve.example.internal:8006/api2/json"
proxmox_insecure_tls = true

cluster_name = "talos-homelab"
api_vip      = "192.168.178.50"

talos_image_datastore = "local"
talos_image_filename  = "talos-nocloud-amd64.raw"

cluster_nodes = [
  { name = "talos-cp-01", role = "control_plane", proxmox_node = "pve1", vm_id = 9001, ip = "192.168.178.101" }
]

vm_cores          = 2
vm_memory_mb      = 4096
vm_disk_datastore = "local-lvm"
vm_disk_size_gb   = 40
vm_network_bridge = "vmbr0"
vm_ip_cidr        = 24

vm_gateway     = "192.168.178.1"
vm_dns_servers = ["192.168.178.1"]
```

Secrets live separately in `cluster.secrets.tfvars`:

```hcl
proxmox_api_token_id     = "terraform@pve!talos"
proxmox_api_token_secret = "00000000-0000-0000-0000-000000000000"
```

## Current Scope

- Terraform provisions Proxmox VMs only
- Talos bootstrap is intentionally out of scope for this stage
- Argo CD is intentionally out of scope for this stage
- Static node IPs remain part of the declarative cluster description for later stages
