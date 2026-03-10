# 03-infrastructure

This stage owns GitOps-managed platform infrastructure after the Talos cluster exists.

Expected layout:

- `clusters/<cluster-name>/`
  Flux bootstrap output and cluster-specific entrypoints
- `infrastructure/<component>/`
  shared platform components such as Traefik, cert-manager, or Longhorn

`just install-flux` bootstraps Flux into:

- `03-infrastructure/clusters/<cluster-name>/`

The first planned platform component is Traefik.

Current structure:

- `clusters/talos-homelab/infrastructure.yaml`
  cluster-specific Flux `Kustomization` objects that point at the shared MetalLB, Traefik, and Longhorn bases
- `clusters/talos-homelab/metallb/`
  cluster-specific MetalLB address-pool configuration for the homelab LAN
- `infrastructure/metallb/`
  minimal MetalLB install via `HelmRepository` and `HelmRelease`
- `infrastructure/traefik/`
  minimal Traefik install via `HelmRepository` and `HelmRelease`
- `infrastructure/longhorn/`
  minimal Longhorn install via `HelmRepository` and `HelmRelease`, using `/var/mnt/longhorn` as `defaultDataPath`
