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
  cluster-specific Flux `Kustomization` objects that point at the shared MetalLB, Traefik, cert-manager, and Longhorn bases
- `clusters/talos-homelab/metallb/`
  cluster-specific MetalLB address-pool configuration for the homelab LAN
- `infrastructure/metallb/`
  minimal MetalLB install via `HelmRepository` and `HelmRelease`
- `infrastructure/traefik/`
  minimal Traefik install via `HelmRepository` and `HelmRelease`
- `infrastructure/cert-manager/`
  minimal cert-manager install via the official Jetstack OCI Helm chart, with CRDs enabled in the Helm release
- `infrastructure/longhorn/`
  minimal Longhorn install via `HelmRepository` and `HelmRelease`, using `/var/mnt/longhorn` as `defaultDataPath`
  and exposing the UI through Traefik at `longhorn.home.arpa`
- `apps/pgadmin/`
  pgAdmin 4 as a concrete app workload, using Longhorn for persistence and Traefik ingress at `pgadmin.home.arpa`
- `smoke-tests/longhorn/`
  manual PVC+Pod validation for Longhorn, intended to be applied with `kubectl apply -k` or `just smoke-longhorn-apply`
