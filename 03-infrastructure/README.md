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
  cluster-specific Flux `Kustomization` objects that point at the shared MetalLB, Traefik, cert-manager, Longhorn,
  and their integration overlays
- `clusters/talos-homelab/metallb/`
  cluster-specific MetalLB address-pool configuration for the homelab LAN
- `infrastructure/metallb/`
  minimal MetalLB install via `HelmRepository` and `HelmRelease`
- `infrastructure/traefik/`
  Traefik split into `core/` (namespace, repository, Helm release) and `monitoring/` (ServiceMonitor)
- `infrastructure/cert-manager/`
  minimal cert-manager install via the official Jetstack OCI Helm chart, with CRDs enabled in the Helm release
- `infrastructure/cloudnative-pg/`
  minimal CloudNativePG operator install via the official `cnpg/cloudnative-pg` Helm chart in `cnpg-system`
- `infrastructure/metrics-server/`
  minimal Metrics Server install in `kube-system` so `kubectl top` and the Kubernetes resource metrics API work;
  the current Talos setup uses `--kubelet-insecure-tls` until kubelet serving cert rotation is enabled
- `infrastructure/longhorn/`
  Longhorn split into `core/` (namespace, repository, Helm release), `ingress/` (UI ingress), and
  `monitoring/` (ServiceMonitor); `core/` uses `/var/mnt/longhorn` as `defaultDataPath` with
  homelab-tuned defaults (`defaultReplicaCount=2`, `defaultDataLocality=best-effort`, single-replica UI);
  the chart-managed default `longhorn` StorageClass is also configured to provision with two replicas
  and `best-effort` data locality
- `infrastructure/observability/`
  minimal `kube-prometheus-stack` install with Prometheus and Alertmanager enabled, but Grafana disabled so an external Grafana can be used;
  retention and PVC sizing are trimmed for homelab use to reduce steady Longhorn write load
- `infrastructure/alloy/`
  minimal Grafana Alloy install that collects pod logs and forwards them to an external Loki endpoint
- `apps/pgadmin/`
  pgAdmin 4 as a concrete app workload, using Longhorn for persistence and Traefik ingress at `pgadmin.home.arpa`
- `apps/polaris/`
  Fairwinds Polaris dashboard as a Flux-managed Helm workload, exposed through Traefik at the configured `polaris_host`
- `clusters/<cluster-name>/.generated/pgadmin/`
  cluster-specific generated overlay for pgAdmin values such as ingress host and PVC size; the encrypted credentials secret can be created with `just pgadmin-secret`
- `clusters/<cluster-name>/.generated/polaris/`
  cluster-specific generated overlay for the Polaris ingress host, derived from the root `polaris_host`
- `clusters/<cluster-name>/.generated/alloy/`
  cluster-specific generated overlay for the Alloy config, especially the external Loki push URL and cluster label
- `smoke-tests/longhorn/`
  manual PVC+Pod validation for Longhorn, intended to be applied with `kubectl apply -k` or `just smoke-longhorn-apply`
