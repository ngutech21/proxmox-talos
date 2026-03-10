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
  cluster-specific Flux `Kustomization` that points at the shared Traefik base
- `infrastructure/traefik/`
  minimal Traefik install via `HelmRepository` and `HelmRelease`
