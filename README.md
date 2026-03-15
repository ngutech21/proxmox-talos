# proxmox-talos

[![CI](https://img.shields.io/github/actions/workflow/status/ngutech21/proxmox-talos/ci.yml?branch=master&label=CI)](https://github.com/ngutech21/proxmox-talos/actions/workflows/ci.yml)
[![Actionlint](https://img.shields.io/github/actions/workflow/status/ngutech21/proxmox-talos/actionlint.yml?branch=master&label=Actionlint)](https://github.com/ngutech21/proxmox-talos/actions/workflows/actionlint.yml)
[![Talos](https://img.shields.io/badge/Talos-Linux-0f172a?logo=linux&logoColor=white)](https://www.talos.dev/)
[![Terraform](https://img.shields.io/badge/Terraform-Infrastructure-623CE4?logo=terraform&logoColor=white)](https://www.terraform.io/)
[![Flux](https://img.shields.io/badge/Flux-GitOps-5468FF?logo=flux&logoColor=white)](https://fluxcd.io/)
[![Proxmox](https://img.shields.io/badge/Proxmox-Virtualization-E57000?logo=proxmox&logoColor=white)](https://www.proxmox.com/)

🚀 A product-style Talos-on-Proxmox platform for homelabs that want a clean path from VM provisioning to a reproducible Kubernetes cluster.

This repository is opinionated on purpose:

- define the cluster once
- provision Talos VMs on Proxmox
- bootstrap the cluster with Talos
- connect the cluster to GitOps

It is designed for operators who want a simpler alternative to hand-rolled Proxmox plus Kubernetes glue.

## ✨ Why Use This

Most homelab Kubernetes setups accumulate complexity fast:

- Proxmox settings drift from cluster docs
- bootstrap steps live in shell history instead of source control
- Talos, Terraform, and GitOps responsibilities blur together
- the path from raw VM to running cluster becomes hard to repeat

`proxmox-talos` keeps that workflow compact and explicit.

You get:

- **Declarative cluster definition** with a single root config file
- **Clear stage boundaries** between infrastructure, bootstrap, and GitOps
- **Talos-first workflow** instead of generic VM automation pretending to manage cluster state
- **Generated access artifacts** like `talosconfig` and `kubeconfig`
- **A cleaner learning path** for Talos and GitOps on Proxmox

## 📦 What Gets Installed

Today, this repository builds the foundation of a Talos-based Kubernetes platform.

| Layer | Tooling | What it installs or creates |
| --- | --- | --- |
| Infrastructure | `Terraform` | Talos virtual machines on Proxmox with declared CPU, memory, disks, placement, VM IDs, and networking metadata |
| Cluster bootstrap | `Talos` | Machine configs, static node networking, control-plane VIP config, cluster bootstrap, `talosconfig`, and `kubeconfig` |
| GitOps entrypoint | `Flux` | GitOps bootstrap into the cluster and repo structure under `03-infrastructure/` |
| Platform layer | `Flux` manifests | Shared infrastructure components for MetalLB, Traefik, cert-manager, Longhorn, CloudNativePG, Metrics Server, Prometheus, Alertmanager, and Alloy |

Current repository stages:

- `01-provision`: creates Talos VMs on Proxmox from an existing raw image
- `02-bootstrap`: configures and bootstraps the Talos cluster
- `03-infrastructure`: Flux-managed platform layer skeleton
- `04-apps`: reserved for workloads and example apps

## ✅ What You End Up With

After the main bootstrap flow, you have:

- a Talos-based Kubernetes cluster running on Proxmox VMs
- a declared Kubernetes API endpoint via `api_vip`
- generated `02-bootstrap/.generated/talosconfig`
- generated `02-bootstrap/.generated/kubeconfig`
- an optional GitOps bootstrap path via Flux
- MetalLB for `LoadBalancer` services
- Traefik as the ingress controller
- Longhorn as the storage layer
- cert-manager for certificate management
- CloudNativePG as the PostgreSQL operator
- Prometheus and Alertmanager for metrics and alerting
- Metrics Server for the Kubernetes resource metrics API and `kubectl top`
- Alloy for shipping cluster logs to an external Loki instance

If worker data disks are configured, worker nodes also get a Talos `UserVolumeConfig` named `longhorn`, mounted at `/var/mnt/longhorn`.

## 🧭 Quick Start

1. Create local config files from the examples:

   ```bash
   just init-config
   ```

2. Edit `cluster.tfvars` with:
   - your Proxmox API endpoint
   - your node layout
   - your static IP plan
   - your Talos image settings
   - your `api_vip`

3. Edit `cluster.secrets.tfvars` with your Proxmox API token values.

4. Provision the VMs:

   ```bash
   just provision-vms
   ```

5. Bootstrap Talos and generate access artifacts:

   ```bash
   just bootstrap-cluster
   ```

6. Use the generated kubeconfig:

   ```bash
   export KUBECONFIG="$(pwd)/02-bootstrap/.generated/kubeconfig"
   kubectl get nodes
   ```

7. Optionally bootstrap Flux into this repository:

   ```bash
   export GITHUB_TOKEN='<github-pat>'
   just install-flux
   ```

   This also activates the GitOps-managed infrastructure layer under `03-infrastructure/`,
   which reconciles shared platform components such as MetalLB, Traefik, cert-manager,
   Longhorn, CloudNativePG, Prometheus, Alertmanager, and Alloy.

8. If you use SOPS-encrypted manifests such as the Postgres smoke test secrets, import your Age private key into Flux:

   ```bash
   just install-sops-age age_key_file=/path/to/age-key.txt
   ```

## 🧱 Declarative Cluster Config

The main user-edited file is `cluster.tfvars`.

Example:

```hcl
proxmox_api_url      = "https://pve.example.internal:8006/api2/json"
proxmox_insecure_tls = true

cluster_name = "talos-homelab"
api_vip      = "192.168.178.50"

talos_image_datastore = "local"
talos_image_filename  = "talos-nocloud-amd64.raw"
talos_install_disk    = "/dev/sda"
talos_installer_image = "factory.talos.dev/installer/<schematic-id>:v1.12.5"
talos_version         = "v1.12.5"
talos_dns_domain      = "cluster.local"

cluster_nodes = [
  { name = "talos-cp-01", role = "control_plane", proxmox_node = "pve-1", vm_id = 9001, ip = "192.168.178.101" },
  { name = "talos-cp-02", role = "control_plane", proxmox_node = "pve-2", vm_id = 9002, ip = "192.168.178.102" },
  { name = "talos-cp-03", role = "control_plane", proxmox_node = "pve-3", vm_id = 9003, ip = "192.168.178.103" },
  { name = "talos-wk-01", role = "worker", proxmox_node = "pve-1", vm_id = 9101, ip = "192.168.178.111" }
]

vm_cores                 = 2
vm_memory_mb             = 4096
vm_disk_datastore        = "local-zfs"
vm_disk_size_gb          = 40
vm_scsi_hardware         = "virtio-scsi-single"
worker_data_disk_size_gb = 100
vm_network_bridge        = "vmbr0"
worker_vm_network_queues = 4
vm_ip_cidr               = 24
vm_tags                  = ["homelab"]

vm_gateway     = "192.168.178.1"
vm_dns_servers = ["192.168.178.1", "1.1.1.1"]

metallb_addresses     = ["192.168.178.240-192.168.178.249"]
base_domain           = "home.arpa"
polaris_host          = "polaris.home.arpa"
prometheus_host       = "prometheus.home.arpa"
loki_push_url         = "http://loki.home.arpa:3100/loki/api/v1/push"
```

Secrets live separately in `cluster.secrets.tfvars`:

```hcl
proxmox_api_token_id     = "terraform@pve!talos"
proxmox_api_token_secret = "00000000-0000-0000-0000-000000000000"
```

## 🏗️ How The Platform Is Structured

### `01-provision`

This stage owns infrastructure state.

It is responsible for:

- VM creation on Proxmox
- CPU, memory, disks, NICs, and VM placement
- Talos image references
- VM IDs, names, and network metadata

It does not perform cluster bootstrap.

### `02-bootstrap`

This stage owns cluster bring-up.

It is responsible for:

- generating Talos machine configs
- rendering Talos config and client artifacts for each node
- setting static addresses, gateway, DNS, hostname, and control-plane VIP
- applying Talos config to each node with `talosctl`
- bootstrapping the cluster
- retrieving `talosconfig` and `kubeconfig`
- running readiness checks

Useful commands:

```bash
just bootstrap-cluster
just bootstrap-render
just bootstrap-apply-config
just bootstrap-etcd
just bootstrap-kubeconfig
just bootstrap-wait-ready
just generate-artifacts
just kubeconfig
just print-cluster-info
```

`just bootstrap-cluster` performs:

- Talos secrets generation inside Terraform state
- one machine config per node
- config apply with `talosctl apply-config` to the currently reachable VM addresses, preferring the declared node IP once it is active and otherwise falling back to the Proxmox guest agent
- `talosctl bootstrap` on the first control-plane node
- `talosctl kubeconfig` into `02-bootstrap/.generated/kubeconfig`
- Talos and Kubernetes readiness checks

`just bootstrap-render` only renders the Talos machine configs, `talosconfig`, and generated cluster-local artifacts. It does not push config to nodes.

`just generate-artifacts` only refreshes the locally generated Terraform artifacts from `02-bootstrap`, such as:

- `02-bootstrap/.generated/talosconfig`
- per-node machine configs under `02-bootstrap/.generated/`
- generated cluster-local manifests under `03-infrastructure/clusters/<cluster-name>/.generated/`

Use it when you change generated inputs like the MetalLB address pool or Talos config patches and want to refresh the rendered files without re-running cluster bootstrap.

### `03-infrastructure`

This stage is the GitOps-managed platform layer.

Right now the repository contains:

- cluster-specific Flux bootstrap output under `03-infrastructure/clusters/`
- shared infrastructure components under `03-infrastructure/infrastructure/`
- MetalLB for `LoadBalancer` services
- Traefik as the ingress controller
- Longhorn as the storage layer
- cert-manager for certificate management
- CloudNativePG as the PostgreSQL operator
- Prometheus and Alertmanager via `kube-prometheus-stack`
- Metrics Server for `kubectl top` and HPA/VPA-style resource metrics
- Alloy for forwarding cluster logs to an external Loki instance

### `04-apps`

This stage is reserved for workloads that should remain separate from the shared platform layer.

## 🔁 Flux Bootstrap

Flux bootstrap writes cluster-specific manifests into:

```text
03-infrastructure/clusters/<cluster_name>/
```

The `just install-flux` command:

- reads `cluster_name` from `cluster.tfvars`
- reuses `02-bootstrap/.generated/kubeconfig`
- derives the GitHub owner and repository from the `origin` remote by default
- runs `flux bootstrap github --token-auth`

Required environment variable:

```bash
export GITHUB_TOKEN='<github-pat>'
```

Optional overrides:

```bash
just install-flux owner=<github-owner> repo=<github-repo> branch=main cluster=<cluster-name>
```

The default branch used by `just install-flux` is currently `master`. Pass `branch=main` explicitly if your repository uses `main`.

After bootstrap, you can trigger reconciliation manually:

```bash
just reconcile-flux
```

When you change generated GitOps inputs such as:

- `metallb_addresses`
- `prometheus_host`
- `loki_push_url`
- generated app hostnames or storage sizes

refresh the generated artifacts first:

```bash
just generate-artifacts
```

Then commit the updated files under `03-infrastructure/clusters/<cluster-name>/.generated/`
so Flux can reconcile the new desired state from Git.

## 🛠️ Requirements

- A Talos raw image is already available in the configured Proxmox datastore.
- The Talos boot image includes `qemu-guest-agent`.
- The installer image matches the raw image build and Talos version.
- Your IP plan and `api_vip` fit your network.

The guest agent is required because the bootstrap stage may need each VM's initial DHCP address before Talos switches the node to its final static IP. Once the declared static IP is active, the Terraform outputs prefer that address.

## 📝 Operational Notes

- `talos_installer_image` must match the raw image build. If the raw image contains extensions such as `siderolabs/qemu-guest-agent`, the installer image must contain the same extensions.
- `talos_version` should match the Talos version of the raw and installer images.
- `talos_install_disk` defaults to `/dev/sda`. If your imported disk appears as a different device, update `cluster.tfvars` before running `just bootstrap-cluster`.
- `worker_data_disk_size_gb` defaults to `100`. Worker nodes receive an additional `scsi1` disk of this size, and Talos provisions `/dev/sdb` as a `UserVolumeConfig` named `longhorn`.
- `just bootstrap-cluster` prefers each node's declared static IP from `01-provision` once it is active, and otherwise falls back to guest-agent-discovered IPv4 addresses. If the fallback addresses are missing during initial bootstrap, the boot image likely does not start `qemu-guest-agent`.

## 🧾 Generated Files

This repository uses two different kinds of generated output, and they are intentionally treated differently.

### Local Generated Artifacts

`02-bootstrap/.generated/` contains local bootstrap artifacts such as:

- `talosconfig`
- `kubeconfig`
- per-node machine configs

These files are local operator artifacts and should not be committed.

### Versioned GitOps Generated Artifacts

`03-infrastructure/clusters/<cluster-name>/.generated/` contains cluster-specific manifests derived from the root config, for example:

- MetalLB address-pool manifests
- Prometheus ingress patches
- Alloy configuration patches
- app-specific generated overlays

These files are generated, but they are also part of the GitOps input that Flux reconciles from Git.

That means:

- do not edit them by hand
- regenerate them from the root config
- commit them when they change

In this repository, `.generated` under `03-infrastructure/clusters/` means "derived and not hand-maintained", not "gitignored".

## 🔄 Dependency Updates

Renovate is configured via [renovate.json5](./renovate.json5).

This repository is intended to use the hosted Renovate GitHub App, not a self-hosted GitHub Actions workflow. Once the Renovate App is enabled for this repository, it will read `renovate.json5` automatically.
