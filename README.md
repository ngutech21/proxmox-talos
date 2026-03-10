# proxmox-talos

Declarative Talos-on-Proxmox homelab platform with a clear split between infrastructure, cluster bootstrap, and GitOps delivery.

The current workflow uses two Terraform stages:

- `01-provision` creates Talos VMs on Proxmox from an existing raw image.
- `02-talos` uses the official Talos Terraform provider to generate machine configs, apply them, bootstrap the cluster, and write `talosconfig` plus `kubeconfig`.

The Talos boot image must include `qemu-guest-agent`, because the bootstrap stage discovers each VM's initial DHCP address through the Proxmox guest agent before Talos switches the node onto its final static IP.

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

5. Bootstrap Talos and write `02-talos/.generated/kubeconfig`:

   ```bash
   just bootstrap-cluster
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
talos_installer_image = "factory.talos.dev/installer/<schematic-id>:v1.12.4"
talos_version         = "v1.12.4"

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

## Talos Bootstrap

The second stage reuses the same `cluster.tfvars`, reads the current VM addresses from `01-provision` state, and writes Talos artifacts into `02-talos/.generated/`.

Commands:

```bash
just bootstrap-cluster
just kubeconfig
just print-cluster-info
```

`just bootstrap-cluster` performs:

- Talos secrets generation inside Terraform state
- one machine config per node with static IP, gateway, DNS, hostname, install disk, installer image, and control-plane VIP
- config apply to the currently reachable VM addresses reported by Proxmox guest agent
- cluster bootstrap on the first control-plane node
- `talosconfig` and `kubeconfig` written to `02-talos/.generated/`

Then fetch kubeconfig and inspect the cluster:

```bash
export KUBECONFIG="$(pwd)/02-talos/.generated/kubeconfig"
kubectl get nodes
```

## Notes

- `talos_installer_image` must match the raw image build. If the raw image contains extensions such as `siderolabs/qemu-guest-agent`, the installer image must contain the same extensions.
- `talos_version` should match the Talos version of the raw and installer images.
- `talos_install_disk` defaults to `/dev/sda`. If your imported disk appears as a different device, update `cluster.tfvars` before running `just bootstrap-cluster`.
- `just bootstrap-cluster` relies on guest-agent-discovered IPv4 addresses from `01-provision`. If those are missing, the boot image likely does not start `qemu-guest-agent`.
