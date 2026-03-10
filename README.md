# proxmox-talos

[![CI](https://img.shields.io/github/actions/workflow/status/ngutech21/proxmox-talos/ci.yml?branch=master&label=ci)](https://github.com/ngutech21/proxmox-talos/actions/workflows/ci.yml)
[![Actionlint](https://img.shields.io/github/actions/workflow/status/ngutech21/proxmox-talos/actionlint.yml?branch=master&label=actionlint)](https://github.com/ngutech21/proxmox-talos/actions/workflows/actionlint.yml)

Declarative Talos-on-Proxmox homelab platform with a clear split between infrastructure, cluster bootstrap, and GitOps delivery.

The current workflow uses two Terraform stages:

- `01-provision` creates Talos VMs on Proxmox from an existing raw image.
- `02-bootstrap` uses the official Talos Terraform provider to generate machine configs, apply them, bootstrap the cluster, and write `talosconfig` plus `kubeconfig`.

The next planned layers are:

- `03-infrastructure` for Flux CD bootstrap and cluster-wide platform services like ingress, certificates, and storage
- `04-apps` for example workloads or concrete user applications

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

5. Bootstrap Talos and write `02-bootstrap/.generated/kubeconfig`:

   ```bash
   just bootstrap-cluster
   ```

6. Bootstrap Flux CD into this GitHub repository:

   ```bash
   export GITHUB_TOKEN='<github-pat>'
   just install-flux
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

The second stage reuses the same `cluster.tfvars`, reads the current VM addresses from `01-provision` state, and writes Talos artifacts into `02-bootstrap/.generated/`.

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
- `talosconfig` and `kubeconfig` written to `02-bootstrap/.generated/`

Then fetch kubeconfig and inspect the cluster:

```bash
export KUBECONFIG="$(pwd)/02-bootstrap/.generated/kubeconfig"
kubectl get nodes
```

## Planned Next Layers

- `03-infrastructure` will bootstrap Flux CD and reconcile platform components such as Traefik, cert-manager, and Longhorn.
- `04-apps` is reserved for example applications or concrete workloads that should stay separate from the platform layer.

## Flux Bootstrap

Flux bootstrap writes its own manifests into this repository under:

```text
03-infrastructure/clusters/<cluster_name>/
```

The repository already contains the stage skeleton:

- `03-infrastructure/clusters/` for cluster-specific Flux bootstrap output
- `03-infrastructure/infrastructure/` for shared platform components managed by Flux
- `04-apps/` for example or user workloads

The `just install-flux` command:

- reads `cluster_name` from `cluster.tfvars`
- reuses `02-bootstrap/.generated/kubeconfig`
- derives the GitHub owner and repository from the `origin` remote by default
- runs `flux bootstrap github --token-auth`

Required environment variable:

```bash
export GITHUB_TOKEN='<github-pat>'
```

Optional overrides if the `origin` remote should not be used:

```bash
just install-flux owner=<github-owner> repo=<github-repo> branch=main cluster=<cluster-name>
```

## Dependency Updates

Renovate is configured via [renovate.json5](/Users/steffen/projects/proxmox-talos/renovate.json5).

This repository is intended to use the hosted Renovate GitHub App, not a self-hosted GitHub Actions workflow. Once the Renovate App is enabled for this repository, it will read `renovate.json5` automatically.

After bootstrap, you can force an immediate reconciliation with:

```bash
just reconcile-flux
```

## Notes

- `talos_installer_image` must match the raw image build. If the raw image contains extensions such as `siderolabs/qemu-guest-agent`, the installer image must contain the same extensions.
- `talos_version` should match the Talos version of the raw and installer images.
- `talos_install_disk` defaults to `/dev/sda`. If your imported disk appears as a different device, update `cluster.tfvars` before running `just bootstrap-cluster`.
- `just bootstrap-cluster` relies on guest-agent-discovered IPv4 addresses from `01-provision`. If those are missing, the boot image likely does not start `qemu-guest-agent`.
