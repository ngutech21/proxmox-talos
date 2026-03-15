set shell := ["bash", "-ceu", "-o", "pipefail", "-c"]

cluster_config := "cluster.tfvars"
cluster_example := "cluster.tfvars.example"
cluster_secrets := "cluster.secrets.tfvars"
cluster_secrets_example := "cluster.secrets.tfvars.example"
provision_plan_path := "tfplan"
talos_plan_path := "tfplan"
generated_dir := "02-bootstrap/.generated"
infrastructure_dir := "03-infrastructure"

default:
    @just --list

init-config:
    if [ -f "{{cluster_config}}" ]; then echo "{{cluster_config}} already exists" >&2; exit 1; fi
    if [ -f "{{cluster_secrets}}" ]; then echo "{{cluster_secrets}} already exists" >&2; exit 1; fi
    cp "{{cluster_example}}" "{{cluster_config}}"
    cp "{{cluster_secrets_example}}" "{{cluster_secrets}}"
    echo "Created {{cluster_config}} from {{cluster_example}}"
    echo "Created {{cluster_secrets}} from {{cluster_secrets_example}}"

[private]
require-config:
    if [ ! -f "{{cluster_config}}" ]; then echo "Missing {{cluster_config}}. Run 'just init-config' first." >&2; exit 1; fi
    if [ ! -f "{{cluster_secrets}}" ]; then echo "Missing {{cluster_secrets}}. Run 'just init-config' first." >&2; exit 1; fi

[private]
ensure-generated-dir:
    mkdir -p "{{generated_dir}}"

[private]
ensure-cluster-generated-dirs: require-config
    #!/usr/bin/env bash
    set -euo pipefail
    cluster_name="$(sed -nE 's/^cluster_name[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' "{{cluster_config}}" | head -n1)"
    if [ -z "$cluster_name" ]; then
      echo "Could not determine cluster_name from {{cluster_config}}." >&2
      exit 1
    fi
    mkdir -p "{{infrastructure_dir}}/clusters/$cluster_name/.generated/metallb"
    mkdir -p "{{infrastructure_dir}}/clusters/$cluster_name/.generated/observability"
    mkdir -p "{{infrastructure_dir}}/clusters/$cluster_name/.generated/pgadmin"
    mkdir -p "{{infrastructure_dir}}/clusters/$cluster_name/.generated/polaris"
    mkdir -p "{{infrastructure_dir}}/clusters/$cluster_name/.generated/alloy"

[private]
require-kubeconfig:
    if [ ! -f "{{generated_dir}}/kubeconfig" ]; then echo "Missing {{generated_dir}}/kubeconfig. Run 'just bootstrap-cluster' first." >&2; exit 1; fi

[private]
require-talosconfig:
    if [ ! -f "{{generated_dir}}/talosconfig" ]; then echo "Missing {{generated_dir}}/talosconfig. Run 'just bootstrap-cluster' first." >&2; exit 1; fi

[private]
require-github-token:
    if [ -z "${GITHUB_TOKEN:-}" ]; then echo "Missing GITHUB_TOKEN. Export a GitHub PAT for flux bootstrap." >&2; exit 1; fi

[private]
ensure-infrastructure-dirs:
    mkdir -p "{{infrastructure_dir}}/clusters" "{{infrastructure_dir}}/infrastructure"

[private, working-directory: '01-provision']
provision-init:
    terraform init

[private, working-directory: '01-provision']
provision-plan:
    terraform plan -var-file="../{{cluster_config}}" -var-file="../{{cluster_secrets}}" -out="{{provision_plan_path}}"

[private, working-directory: '01-provision']
provision-apply:
    terraform apply "{{provision_plan_path}}"

[private, working-directory: '01-provision']
provision-refresh:
    terraform apply -refresh-only -var-file="../{{cluster_config}}" -var-file="../{{cluster_secrets}}"

[private, working-directory: '01-provision']
provision-destroy:
    terraform destroy -var-file="../{{cluster_config}}" -var-file="../{{cluster_secrets}}"

[private, working-directory: '02-bootstrap']
talos-init:
    terraform init

[private, working-directory: '02-bootstrap']
talos-plan:
    terraform plan -var-file="../{{cluster_config}}" -var-file="../{{cluster_secrets}}" -out="{{talos_plan_path}}"

[private, working-directory: '02-bootstrap']
talos-apply:
    terraform apply "{{talos_plan_path}}"

[private, working-directory: '02-bootstrap']
talos-generate:
    terraform apply -auto-approve \
      -var-file="../{{cluster_config}}" \
      -var-file="../{{cluster_secrets}}" \
      -target=local_sensitive_file.machine_config \
      -target=local_sensitive_file.talosconfig \
      -target=local_file.metallb_ip_address_pool \
      -target=local_file.metallb_generated_kustomization \
      -target=local_file.pgadmin_values_patch \
      -target=local_file.pgadmin_generated_kustomization \
      -target=local_file.polaris_values_patch \
      -target=local_file.polaris_generated_kustomization \
      -target=local_file.observability_values_patch \
      -target=local_file.observability_generated_kustomization \
      -target=local_file.alloy_values_patch \
      -target=local_file.alloy_generated_kustomization

[private, working-directory: '02-bootstrap']
talos-destroy:
    terraform destroy -var-file="../{{cluster_config}}" -var-file="../{{cluster_secrets}}"
    
[private, working-directory: '01-provision']
tflint-provision:
    tflint --config=.tflint.hcl

[private, working-directory: '02-bootstrap']
tflint-bootstrap:
    tflint --config=.tflint.hcl

provision-vms: require-config provision-init provision-plan provision-apply

# Render Talos artifacts and generated overlays; `talosctl` handles apply/bootstrap.
bootstrap-render: require-config ensure-generated-dir ensure-cluster-generated-dirs provision-init provision-refresh talos-init talos-plan talos-apply

generate-artifacts: require-config ensure-generated-dir ensure-cluster-generated-dirs talos-init talos-generate

pgadmin-secret password='': require-config ensure-cluster-generated-dirs
    #!/usr/bin/env bash
    set -euo pipefail
    cluster_name="$(sed -nE 's/^cluster_name[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' "{{cluster_config}}" | head -n1)"
    if [ -z "$cluster_name" ]; then
      echo "Could not determine cluster_name from {{cluster_config}}." >&2
      exit 1
    fi
    output_path="$PWD/03-infrastructure/clusters/$cluster_name/.generated/pgadmin/credentials-secret.sops.yaml"
    zsh "$PWD/scripts/create-pgadmin-secret.sh" "$output_path" "{{password}}"
    just generate-artifacts

bootstrap-apply-config: require-config ensure-generated-dir
    #!/usr/bin/env bash
    set -euo pipefail
    kubeconfig_path="$(pwd)/{{generated_dir}}/kubeconfig"
    if [ -f "$kubeconfig_path" ] && kubectl --kubeconfig "$kubeconfig_path" get nodes >/dev/null 2>&1; then
      echo "Cluster already reachable with existing kubeconfig; skipping talos apply-config"
      exit 0
    fi
    if ! command -v jq >/dev/null 2>&1; then
      echo "Missing jq. Install jq to use 'just bootstrap-apply-config'." >&2
      exit 1
    fi

    bootstrap_endpoints_json="$(terraform -chdir=02-bootstrap output -json bootstrap_endpoints)"
    missing_nodes="$(printf '%s' "$bootstrap_endpoints_json" | jq -r 'to_entries[] | select(.value == null or .value == "") | .key')"
    if [ -n "$missing_nodes" ]; then
      printf 'Missing current IPv4 addresses from 01-provision for nodes:\n%s\n' "$missing_nodes" >&2
      echo "Ensure the boot image starts qemu-guest-agent, rerun 'just provision-vms', and then rerun 'just bootstrap-cluster'." >&2
      exit 1
    fi

    while IFS=$'\t' read -r node_name endpoint; do
      config_path="$(pwd)/{{generated_dir}}/${node_name}.yaml"
      if [ ! -f "$config_path" ]; then
        echo "Missing machine config '$config_path'. Run 'just bootstrap-render' first." >&2
        exit 1
      fi

      deadline=$((SECONDS + 1200))
      while true; do
        if output="$(talosctl apply-config --insecure --mode=reboot --nodes "$endpoint" --endpoints "$endpoint" --file "$config_path" 2>&1)"; then
          printf '%s\n' "$output"
          break
        fi
        if ! printf '%s' "$output" | grep -Eqi "connection refused|connect: no route to host|connect: host is down|transport: Error while dialing|rpc error: code = Unavailable|context deadline exceeded|i/o timeout|EOF|tls: first record does not look like a TLS handshake"; then
          printf '%s\n' "$output" >&2
          exit 1
        fi
        if [ "$SECONDS" -ge "$deadline" ]; then
          printf '%s\n' "$output" >&2
          echo "Timed out applying Talos config to $node_name via $endpoint" >&2
          exit 1
        fi
        sleep 10
      done
    done < <(printf '%s' "$bootstrap_endpoints_json" | jq -r 'to_entries[] | [.key, .value] | @tsv')

bootstrap-etcd: require-talosconfig
    #!/usr/bin/env bash
    set -euo pipefail
    bootstrap_node="$(terraform -chdir=02-bootstrap output -raw bootstrap_node_ip)"
    talosconfig_path="$(pwd)/{{generated_dir}}/talosconfig"
    kubeconfig_path="$(pwd)/{{generated_dir}}/kubeconfig"
    deadline=$((SECONDS + 1200))
    if [ -f "$kubeconfig_path" ] && kubectl --kubeconfig "$kubeconfig_path" get nodes >/dev/null 2>&1; then
      echo "Cluster already reachable with existing kubeconfig; skipping talos bootstrap"
      exit 0
    fi
    until talosctl --talosconfig "$talosconfig_path" --endpoints "$bootstrap_node" --nodes "$bootstrap_node" version >/dev/null 2>&1; do
      if [ "$SECONDS" -ge "$deadline" ]; then
        echo "Timed out waiting for Talos API on $bootstrap_node before bootstrap" >&2
        exit 1
      fi
      sleep 5
    done
    while true; do
      if output="$(talosctl --talosconfig "$talosconfig_path" --endpoints "$bootstrap_node" --nodes "$bootstrap_node" bootstrap 2>&1)"; then
        printf '%s\n' "$output"
        break
      fi
      if printf '%s' "$output" | grep -Eqi "bootstrap is not available yet|already bootstrapped|AlreadyExists|etcd data directory is not empty"; then
        if printf '%s' "$output" | grep -Eqi "bootstrap is not available yet"; then
          echo "Talos bootstrap is not available yet on $bootstrap_node; retrying..." >&2
        else
          printf '%s\n' "$output"
        fi
        if printf '%s' "$output" | grep -Eqi "already bootstrapped|AlreadyExists|etcd data directory is not empty"; then
          break
        fi
      elif printf '%s' "$output" | grep -Eqi "connection refused|connect: no route to host|connect: host is down|transport: Error while dialing|rpc error: code = Unavailable|context deadline exceeded|i/o timeout|EOF"; then
        :
      else
        printf '%s\n' "$output" >&2
        exit 1
      fi
      if [ "$SECONDS" -ge "$deadline" ]; then
        printf '%s\n' "$output" >&2
        echo "Timed out waiting for Talos bootstrap to become available on $bootstrap_node" >&2
        exit 1
      fi
      sleep 10
    done

bootstrap-kubeconfig: require-talosconfig ensure-generated-dir
    #!/usr/bin/env bash
    set -euo pipefail
    bootstrap_node="$(terraform -chdir=02-bootstrap output -raw bootstrap_node_ip)"
    talosconfig_path="$(pwd)/{{generated_dir}}/talosconfig"
    kubeconfig_path="$(pwd)/{{generated_dir}}/kubeconfig"
    deadline=$((SECONDS + 1200))
    while true; do
      if output="$(talosctl --talosconfig "$talosconfig_path" --endpoints "$bootstrap_node" --nodes "$bootstrap_node" kubeconfig "$kubeconfig_path" --merge=false --force 2>&1)"; then
        printf '%s\n' "$output"
        break
      fi
      if ! printf '%s' "$output" | grep -Eqi "connection refused|connect: no route to host|connect: host is down|transport: Error while dialing|rpc error: code = Unavailable|context deadline exceeded|i/o timeout|EOF"; then
        printf '%s\n' "$output" >&2
        exit 1
      fi
      if [ "$SECONDS" -ge "$deadline" ]; then
        printf '%s\n' "$output" >&2
        echo "Timed out retrieving kubeconfig from $bootstrap_node" >&2
        exit 1
      fi
      sleep 10
    done

bootstrap-wait-ready: require-talosconfig require-kubeconfig
    #!/usr/bin/env bash
    set -euo pipefail
    api_vip="$(terraform -chdir=02-bootstrap output -raw api_vip)"
    control_plane_ips="$(terraform -chdir=02-bootstrap output -json control_plane_ips | tr -d '[]\"[:space:]')"
    worker_ips="$(terraform -chdir=02-bootstrap output -json worker_ips | tr -d '[]\"[:space:]')"
    talosconfig_path="$(pwd)/{{generated_dir}}/talosconfig"
    kubeconfig_path="$(pwd)/{{generated_dir}}/kubeconfig"
    deadline=$((SECONDS + 900))

    health_args=(
      --talosconfig "$talosconfig_path"
      --endpoints "$control_plane_ips"
      --control-plane-nodes "$control_plane_ips"
      --k8s-endpoint "https://$api_vip:6443"
      --wait-timeout 5m
    )

    if [ -n "$worker_ips" ]; then
      health_args+=(--worker-nodes "$worker_ips")
    fi

    while true; do
      if output="$(kubectl --kubeconfig "$kubeconfig_path" wait --for=condition=Ready nodes --all --timeout=60s 2>&1)"; then
        printf '%s\n' "$output"
        break
      fi
      if [ "$SECONDS" -ge "$deadline" ]; then
        printf '%s\n' "$output" >&2
        echo "Timed out waiting for Kubernetes nodes to become Ready" >&2
        exit 1
      fi
      if printf '%s' "$output" | grep -Eqi "connection refused|EOF|i/o timeout|Unable to connect to the server|The connection to the server .* was refused|net/http: TLS handshake timeout|the server is currently unable to handle the request"; then
        sleep 10
        continue
      fi
      printf '%s\n' "$output" >&2
      exit 1
    done

    if ! talosctl health "${health_args[@]}"; then
      echo "talosctl health did not fully converge after Kubernetes became Ready; continuing" >&2
    fi

bootstrap-cluster: bootstrap-render bootstrap-apply-config bootstrap-etcd bootstrap-kubeconfig bootstrap-wait-ready

tflint: tflint-provision tflint-bootstrap

validate-manifests path='03-infrastructure':
    bash scripts/validate-gitops-kustomize.sh "{{path}}"

smoke-longhorn-apply: require-kubeconfig
    kubectl --kubeconfig "{{generated_dir}}/kubeconfig" apply -k 03-infrastructure/smoke-tests/longhorn

smoke-longhorn-delete: require-kubeconfig
    kubectl --kubeconfig "{{generated_dir}}/kubeconfig" delete -k 03-infrastructure/smoke-tests/longhorn --ignore-not-found

kubeconfig: require-kubeconfig
    printf '%s\n' "$$(pwd)/{{generated_dir}}/kubeconfig"

[private, working-directory: '02-bootstrap']
bootstrap-output-cluster-info:
    terraform output cluster_info

print-cluster-info: bootstrap-output-cluster-info

install-flux owner='' repo='' branch='master' cluster='': require-config require-kubeconfig require-github-token ensure-infrastructure-dirs
    #!/usr/bin/env bash
    set -euo pipefail
    cluster_name="{{cluster}}"
    if [ -z "$cluster_name" ]; then
      cluster_name="$(sed -nE 's/^cluster_name[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' "{{cluster_config}}" | head -n1)"
    fi
    if [ -z "$cluster_name" ]; then
      echo "Could not determine cluster_name from {{cluster_config}}." >&2
      exit 1
    fi
    owner_name="{{owner}}"
    repo_name="{{repo}}"
    if [ -z "$owner_name" ] || [ -z "$repo_name" ]; then
      remote_url="$(git remote get-url origin)"
      case "$remote_url" in
        git@github.com:*)
          repo_path="${remote_url#git@github.com:}"
          ;;
        https://github.com/*)
          repo_path="${remote_url#https://github.com/}"
          ;;
        ssh://git@github.com/*)
          repo_path="${remote_url#ssh://git@github.com/}"
          ;;
        *)
          echo "Unsupported origin remote '$remote_url'. Pass owner=<github-owner> repo=<github-repo> explicitly." >&2
          exit 1
          ;;
      esac
      repo_path="${repo_path%.git}"
      derived_owner="${repo_path%%/*}"
      derived_repo="${repo_path##*/}"
      if [ -z "$owner_name" ]; then owner_name="$derived_owner"; fi
      if [ -z "$repo_name" ]; then repo_name="$derived_repo"; fi
    fi
    export KUBECONFIG="$(pwd)/{{generated_dir}}/kubeconfig"
    flux bootstrap github \
      --owner="$owner_name" \
      --repository="$repo_name" \
      --branch="{{branch}}" \
      --path="{{infrastructure_dir}}/clusters/$cluster_name" \
      --personal \
      --token-auth

install-sops-age age_key_file='': require-kubeconfig
    #!/usr/bin/env bash
    set -euo pipefail
    resolved="{{age_key_file}}"
    case "$resolved" in
      age_key_file=*)
        resolved="${resolved#age_key_file=}"
        ;;
    esac
    if [ -z "$resolved" ]; then
      echo "Missing age key file. Pass age_key_file=/path/to/key.txt." >&2
      exit 1
    fi
    if [ ! -f "$resolved" ]; then
      echo "Age key file '$resolved' does not exist." >&2
      exit 1
    fi
    tmp_manifest="$(mktemp)"
    trap 'rm -f "$tmp_manifest"' EXIT
    kubectl --kubeconfig "{{generated_dir}}/kubeconfig" -n flux-system create secret generic sops-age \
      --from-file=age.agekey="$resolved" \
      --dry-run=client \
      -o yaml > "$tmp_manifest"
    kubectl --kubeconfig "{{generated_dir}}/kubeconfig" apply -f "$tmp_manifest"

reconcile-flux: require-kubeconfig
    flux --kubeconfig "{{generated_dir}}/kubeconfig" reconcile source git flux-system -n flux-system
    flux --kubeconfig "{{generated_dir}}/kubeconfig" reconcile kustomization flux-system -n flux-system --with-source

baseline-performance out_root='perf-baseline': require-kubeconfig
    /bin/zsh -lc 'set -euo pipefail; KUBECONFIG="$PWD/{{generated_dir}}/kubeconfig" zsh "$PWD/scripts/baseline-performance.sh" "{{out_root}}"'

disk-speed-benchmark storageclass='longhorn' size='8Gi' runtime='30' node='' fio_image='docker.io/xridge/fio:latest' keep='false' out_root='perf-disk' replica_count='': require-kubeconfig
    /bin/zsh -lc 'set -euo pipefail; KUBECONFIG="$PWD/{{generated_dir}}/kubeconfig" zsh "$PWD/scripts/disk-speed-benchmark.sh" "{{out_root}}" "{{storageclass}}" "{{size}}" "{{runtime}}" "{{node}}" "{{fio_image}}" "{{keep}}" "1G" "{{replica_count}}"'

destroy-cluster: require-config talos-init talos-destroy provision-init provision-destroy
