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

out_root="${1:-perf-disk}"
storageclass="${2:-longhorn}"
claim_size="${3:-8Gi}"
runtime_seconds="${4:-30}"
target_node="${5:-}"
fio_image="${6:-docker.io/xridge/fio:latest}"
keep_resources="${7:-false}"
test_file_size="${8:-1G}"
replica_count="${9:-}"

timestamp="$(date +%F-%H%M%S)"
run_id="${timestamp//[^0-9]/}"
out_dir="${out_root%/}/$timestamp"
namespace="perf-disk-${run_id}"
pvc_name="fio-pvc-${run_id}"
prefill_job="fio-prefill-${run_id}"
effective_storageclass="$storageclass"
temp_storageclass=""

mkdir -p "$out_dir"

cleanup() {
  if [ "$keep_resources" = "true" ]; then
    return 0
  fi

  kubectl --kubeconfig "$kubeconfig_path" -n "$namespace" delete job --ignore-not-found "$prefill_job" >/dev/null 2>&1 || true
  kubectl --kubeconfig "$kubeconfig_path" -n "$namespace" delete pvc --ignore-not-found "$pvc_name" >/dev/null 2>&1 || true
  kubectl --kubeconfig "$kubeconfig_path" delete namespace --ignore-not-found "$namespace" >/dev/null 2>&1 || true
  if [ -n "$temp_storageclass" ]; then
    kubectl --kubeconfig "$kubeconfig_path" delete storageclass --ignore-not-found "$temp_storageclass" >/dev/null 2>&1 || true
  fi
}

trap cleanup EXIT

kubectl --kubeconfig "$kubeconfig_path" get namespace "$namespace" >/dev/null 2>&1 || \
  kubectl --kubeconfig "$kubeconfig_path" create namespace "$namespace" >/dev/null

if [ -n "$replica_count" ]; then
  temp_storageclass="longhorn-bench-r${replica_count}-${run_id}"
  effective_storageclass="$temp_storageclass"

  cat <<EOF | kubectl --kubeconfig "$kubeconfig_path" apply -f - >/dev/null
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ${temp_storageclass}
provisioner: driver.longhorn.io
allowVolumeExpansion: true
reclaimPolicy: Delete
volumeBindingMode: Immediate
parameters:
  numberOfReplicas: "${replica_count}"
  staleReplicaTimeout: "30"
  fsType: ext4
EOF
fi

cat <<EOF | kubectl --kubeconfig "$kubeconfig_path" apply -f - >/dev/null
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${pvc_name}
  namespace: ${namespace}
spec:
  accessModes:
  - ReadWriteOnce
  storageClassName: ${effective_storageclass}
  resources:
    requests:
      storage: ${claim_size}
EOF

kubectl --kubeconfig "$kubeconfig_path" -n "$namespace" wait --for=jsonpath='{.status.phase}'=Bound "pvc/${pvc_name}" --timeout=5m >/dev/null

create_job() {
  local job_name="$1"
  shift

  local node_section=""
  if [ -n "$target_node" ]; then
    node_section="      nodeName: ${target_node}"
  fi

  {
    cat <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: ${job_name}
  namespace: ${namespace}
spec:
  backoffLimit: 0
  template:
    spec:
${node_section}
      restartPolicy: Never
      containers:
      - name: fio
        image: ${fio_image}
        imagePullPolicy: IfNotPresent
        command: ["fio"]
        args:
EOF
    for arg in "$@"; do
      printf '        - %s\n' "$(printf '%s' "$arg" | jq -Rr @json)"
    done
    cat <<EOF
        volumeMounts:
        - mountPath: /data
          name: benchmark-volume
      volumes:
      - name: benchmark-volume
        persistentVolumeClaim:
          claimName: ${pvc_name}
EOF
  } | kubectl --kubeconfig "$kubeconfig_path" apply -f - >/dev/null
}

wait_and_capture() {
  local job_name="$1"
  local output_file="$2"

  kubectl --kubeconfig "$kubeconfig_path" -n "$namespace" wait --for=condition=Complete "job/${job_name}" --timeout=20m >/dev/null
  kubectl --kubeconfig "$kubeconfig_path" -n "$namespace" logs "job/${job_name}" >"$output_file"
}

summarize_result() {
  local label="$1"
  local json_file="$2"

  jq -r --arg label "$label" '
    .jobs[0] as $job
    | $job.jobname as $jobname
    | if ($job.read.io_bytes // 0) > 0 then
        [$label, "read", (($job.read.bw_bytes // 0) / 1048576), ($job.read.iops // 0), (($job.read.clat_ns.mean // 0) / 1000000)]
      else
        [$label, "write", (($job.write.bw_bytes // 0) / 1048576), ($job.write.iops // 0), (($job.write.clat_ns.mean // 0) / 1000000)]
      end
    | @tsv
  ' "$json_file"
}

create_job "$prefill_job" \
  "--name=prefill" \
  "--filename=/data/read-test.bin" \
  "--rw=write" \
  "--bs=1M" \
  "--size=${test_file_size}" \
  "--iodepth=32" \
  "--direct=1" \
  "--ioengine=libaio" \
  "--output-format=json"
wait_and_capture "$prefill_job" "$out_dir/prefill.json"

typeset -a profiles
profiles=(
  "seqread|--name=seqread --filename=/data/read-test.bin --rw=read --bs=1M --size=${test_file_size} --iodepth=32 --direct=1 --ioengine=libaio --runtime=${runtime_seconds} --time_based --group_reporting --output-format=json"
  "seqwrite|--name=seqwrite --filename=/data/seqwrite.bin --rw=write --bs=1M --size=${test_file_size} --iodepth=32 --direct=1 --ioengine=libaio --runtime=${runtime_seconds} --time_based --group_reporting --output-format=json"
  "randread4k|--name=randread4k --filename=/data/read-test.bin --rw=randread --bs=4k --size=${test_file_size} --iodepth=32 --numjobs=4 --direct=1 --ioengine=libaio --runtime=${runtime_seconds} --time_based --group_reporting --output-format=json"
  "randwrite4k|--name=randwrite4k --filename=/data/randwrite.bin --rw=randwrite --bs=4k --size=${test_file_size} --iodepth=32 --numjobs=4 --direct=1 --ioengine=libaio --runtime=${runtime_seconds} --time_based --group_reporting --output-format=json"
)

for profile in "${profiles[@]}"; do
  local_label="${profile%%|*}"
  arg_blob="${profile#*|}"
  job_name="fio-${local_label}-${run_id}"
  output_file="$out_dir/${local_label}.json"

  IFS=' ' read -rA args <<<"$arg_blob"
  create_job "$job_name" "${args[@]}"
  wait_and_capture "$job_name" "$output_file"
done

{
  echo "# Disk Speed Benchmark"
  echo
  echo "- Generated: $(date -Iseconds)"
  echo "- Output directory: $out_dir"
  echo "- StorageClass: $effective_storageclass"
  echo "- Base StorageClass: $storageclass"
  echo "- Claim size: $claim_size"
  echo "- Test file size: $test_file_size"
  echo "- Runtime per test: ${runtime_seconds}s"
  echo "- Target node: ${target_node:-scheduler default}"
  echo "- FIO image: $fio_image"
  echo "- Replica count: ${replica_count:-storageclass default}"
  echo "- Namespace: $namespace"
  echo
  echo "## Results"
  echo
  echo "| Profile | Direction | MiB/s | IOPS | Mean latency (ms) |"
  echo "| --- | --- | ---: | ---: | ---: |"
  for result_file in "$out_dir"/seqread.json "$out_dir"/seqwrite.json "$out_dir"/randread4k.json "$out_dir"/randwrite4k.json; do
    summarize_result "${result_file:t:r}" "$result_file" | awk -F '\t' '{ printf("| %s | %s | %.2f | %.0f | %.2f |\n", $1, $2, $3, $4, $5) }'
  done
} >"$out_dir/summary.md"

echo "Disk benchmark written to $out_dir"
echo "Summary: $out_dir/summary.md"
