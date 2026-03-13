#!/usr/bin/env zsh
set -euo pipefail

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require_cmd kubectl
require_cmd jq

kubeconfig_path="${KUBECONFIG:-}"
if [ -z "$kubeconfig_path" ]; then
  echo "KUBECONFIG must be set." >&2
  exit 1
fi

out_root="${1:-perf-baseline}"
timestamp="$(date +%F-%H%M%S)"
out_dir="${out_root%/}/$timestamp"
mkdir -p "$out_dir"

prometheus_proxy_base="/api/v1/namespaces/observability/services/http:kube-prometheus-stack-prometheus:9090/proxy/api/v1/query"
failures_file="$out_dir/failures.txt"
touch "$failures_file"

record_command() {
  local label="$1"
  shift

  local stdout_file="$out_dir/$label"
  local stderr_file="${stdout_file}.stderr"

  if "$@" >"$stdout_file" 2>"$stderr_file"; then
    if [ ! -s "$stderr_file" ]; then
      rm -f "$stderr_file"
    fi
    return 0
  fi

  echo "$label" >>"$failures_file"
  return 1
}

prom_query() {
  local label="$1"
  local query="$2"
  local encoded_query

  encoded_query="$(jq -rn --arg query "$query" '$query | @uri')"
  record_command "$label" \
    kubectl --kubeconfig "$kubeconfig_path" \
    get --raw "${prometheus_proxy_base}?query=${encoded_query}"
}

record_command "cluster-info.txt" \
  kubectl --kubeconfig "$kubeconfig_path" cluster-info || true
record_command "version.txt" \
  kubectl --kubeconfig "$kubeconfig_path" version || true
record_command "nodes-wide.txt" \
  kubectl --kubeconfig "$kubeconfig_path" get nodes -o wide || true
record_command "pods-wide.txt" \
  kubectl --kubeconfig "$kubeconfig_path" get pods -A -o wide || true
record_command "storageclasses.txt" \
  kubectl --kubeconfig "$kubeconfig_path" get storageclass || true
record_command "pvcs-pvs.txt" \
  kubectl --kubeconfig "$kubeconfig_path" get pvc,pv -A || true
record_command "longhorn-volumes.txt" \
  kubectl --kubeconfig "$kubeconfig_path" get volumes.longhorn.io -n longhorn-system || true
record_command "longhorn-replicas.txt" \
  kubectl --kubeconfig "$kubeconfig_path" get replicas.longhorn.io -n longhorn-system || true
record_command "longhorn-settings.txt" \
  kubectl --kubeconfig "$kubeconfig_path" get settings.longhorn.io -n longhorn-system || true
record_command "events.txt" \
  kubectl --kubeconfig "$kubeconfig_path" get events -A --sort-by=.lastTimestamp || true
record_command "nodes-describe.txt" \
  kubectl --kubeconfig "$kubeconfig_path" describe nodes || true

prom_query "prom-node-cpu.json" \
  '100 * (1 - avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])))' || true
prom_query "prom-node-mem-free.json" \
  '100 * (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)' || true
prom_query "prom-node-load1.json" \
  'node_load1' || true
prom_query "prom-pod-mem-top.json" \
  'topk(15, sum by (namespace, pod) (container_memory_working_set_bytes{container!="",image!=""}))' || true
prom_query "prom-pod-cpu-top.json" \
  'topk(15, sum by (namespace, pod) (rate(container_cpu_usage_seconds_total{container!="",image!=""}[5m])))' || true
prom_query "prom-node-disk-busy.json" \
  'sum by (instance) (rate(node_disk_read_time_seconds_total[5m]) + rate(node_disk_write_time_seconds_total[5m]))' || true

{
  echo "# Performance Baseline"
  echo
  echo "- Generated: $(date -Iseconds)"
  echo "- Output directory: $out_dir"
  echo "- Kubeconfig: $kubeconfig_path"
  echo

  if [ -s "$failures_file" ]; then
    echo "## Collection Gaps"
    sed 's/^/- /' "$failures_file"
    echo
  fi

  if [ -f "$out_dir/prom-node-cpu.json" ]; then
    echo "## Node CPU Usage (5m avg %)"
    jq -r '.data.result[] | "\(.metric.instance)\t\((.value[1] | tonumber) | round)"' "$out_dir/prom-node-cpu.json"
    echo
  fi

  if [ -f "$out_dir/prom-node-mem-free.json" ]; then
    echo "## Node Free Memory (%)"
    jq -r '.data.result[] | "\(.metric.instance)\t\((.value[1] | tonumber) | round)"' "$out_dir/prom-node-mem-free.json"
    echo
  fi

  if [ -f "$out_dir/prom-node-load1.json" ]; then
    echo "## Node Load1"
    jq -r '.data.result[] | "\(.metric.instance)\t\(.value[1])"' "$out_dir/prom-node-load1.json"
    echo
  fi

  if [ -f "$out_dir/prom-node-disk-busy.json" ]; then
    echo "## Node Disk Busy Fraction (5m)"
    jq -r '.data.result[] | "\(.metric.instance)\t\(.value[1])"' "$out_dir/prom-node-disk-busy.json"
    echo
  fi

  if [ -f "$out_dir/prom-pod-mem-top.json" ]; then
    echo "## Top Pods by Memory (MiB)"
    jq -r '.data.result[] | "\(.metric.namespace)/\(.metric.pod)\t\((.value[1] | tonumber) / 1048576 | floor)"' "$out_dir/prom-pod-mem-top.json"
    echo
  fi

  if [ -f "$out_dir/prom-pod-cpu-top.json" ]; then
    echo "## Top Pods by CPU Cores (5m avg)"
    jq -r '.data.result[] | "\(.metric.namespace)/\(.metric.pod)\t\(.value[1])"' "$out_dir/prom-pod-cpu-top.json"
    echo
  fi

  if [ -f "$out_dir/longhorn-replicas.txt" ]; then
    echo "## Longhorn Replica Count"
    awk 'NR > 1 { count++ } END { print count + 0 }' "$out_dir/longhorn-replicas.txt"
    echo
  fi

  if [ -f "$out_dir/longhorn-volumes.txt" ]; then
    echo "## Longhorn Volumes"
    awk 'NR == 1 || /attached|healthy|degraded|faulted/' "$out_dir/longhorn-volumes.txt"
    echo
  fi
} >"$out_dir/summary.md"

echo "Performance baseline written to $out_dir"
echo "Summary: $out_dir/summary.md"
