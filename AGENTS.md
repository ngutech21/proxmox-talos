# AGENTS.md

## Purpose

This project builds a reproducible Kubernetes platform on top of Proxmox using:

- `Terraform` for VM provisioning
- `Talos` for the node OS and Kubernetes bootstrap
- `Flux CD` for cluster services and application delivery

The goal is to keep the workflow simple, declarative, and opinionated:

- describe the cluster once
- create the VMs with Terraform
- bootstrap Talos with `talosctl`
- let Flux CD install and reconcile platform services and apps

## Architecture Rules

- Treat `Terraform`, `Talos`, and `Flux CD` as separate layers with clear responsibilities.
- Do not mix Talos bootstrap logic into Terraform unless there is a very strong reason.
- Do not use Kubernetes-in-cluster infrastructure operators in the MVP.
- Keep the first version focused on a single Talos cluster on Proxmox, not self-hosted KaaS.
- Prefer declarative config files over ad-hoc shell commands and one-off scripts.

## Responsibility Split

### Terraform

Terraform is responsible for infrastructure state:

- Proxmox VMs
- CPU, memory, disks, NICs
- VM IDs, host placement, and naming
- Talos image or template references
- static IP-related VM metadata if needed

Terraform should not be the main place for:

- `talosctl bootstrap`
- Kubernetes health orchestration
- imperative cluster bring-up sequencing

### Talos

`talosctl` is responsible for cluster state:

- generating Talos machine configs
- applying Talos config to nodes
- bootstrapping the cluster
- retrieving kubeconfig
- OS upgrades
- Kubernetes upgrades
- day-2 Talos operations

### Flux CD

Flux CD is responsible for platform and app delivery after the cluster exists:

- platform controllers
- ingress or gateway stack
- storage
- certificates
- app operators
- user workloads

Flux CD should not be required for the initial Talos bootstrap.

## MVP Scope

The first version should stay intentionally small:

- Proxmox VM provisioning with Terraform
- HA Talos control plane
- optional worker nodes
- Talos API VIP for the Kubernetes API endpoint
- `talosctl bootstrap`
- kubeconfig retrieval
- Flux CD installation
- one ingress solution
- one storage solution

Good default MVP targets:

- `Flux CD`
- `Traefik` as initial ingress controller
- `cert-manager`
- `Longhorn`

## Explicit Non-Goals For MVP

- no Omni
- no `omni-infra-provider-proxmox`
- no Proxmox Operator
- no Proxmox CCM or CSI unless there is a specific later need
- no multi-cluster management
- no self-hosted Kubernetes as a Service layer
- no Gateway API as a hard requirement in the first version

## Recommended Delivery Model

- Bootstrap Flux CD after Talos is up.
- Access Flux components initially with `kubectl port-forward` if a UI is needed later, but do not require ingress for the first bootstrap.
- Install Traefik after Flux CD if needed.
- Expose workloads through ingress only after the ingress layer exists.

## Design Preferences

- Keep the same repo philosophy as the existing `proxmox-k3s` project:
  - minimal user-edited config
  - generated downstream artifacts where useful
  - clear stage boundaries
  - `just` as the main user interface
- Prefer one or two root config files over many stage-local config files.
- Keep naming and workflows easy to scan from the README.
- Optimize for reproducibility and low operator confusion over maximal flexibility.

## Suggested Commands

The new project should likely expose commands similar to:

- `just init-config`
- `just doctor`
- `just provision-vms`
- `just bootstrap-cluster`
- `just install-flux`
- `just install-platform`
- `just print-cluster-info`

## Validation Expectations

Before committing changes:

- run `terraform fmt`
- run `terraform validate`
- run `tflint`
- run `ansible-lint` if any Ansible remains in the repo
- run `helm lint` for local charts
- run `helmfile build` if Helmfile is used anywhere
- run `actionlint` for GitHub workflow changes

## Documentation Expectations

- The root `README.md` must explain the benefit of the project before the internal implementation details.
- Show a declarative cluster config example early in the README.
- Make the quick-start path obvious.
- Explain clearly what Terraform does, what Talos does, and what Flux CD does.
- Document that Flux CD can be installed before ingress and that platform reconciliation does not require ingress to exist first.

## Product Positioning

This project is not trying to replicate a managed cloud Kubernetes offering.
It should be positioned as:

- a reproducible Talos-on-Proxmox homelab platform
- a clean learning path for Talos and GitOps
- a simpler alternative to hand-rolled Proxmox + Kubernetes glue
