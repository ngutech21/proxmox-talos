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
require-kubeconfig:
    if [ ! -f "{{generated_dir}}/kubeconfig" ]; then echo "Missing {{generated_dir}}/kubeconfig. Run 'just bootstrap-cluster' first." >&2; exit 1; fi

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
    terraform apply -refresh-only -auto-approve -var-file="../{{cluster_config}}" -var-file="../{{cluster_secrets}}"

[private, working-directory: '02-bootstrap']
talos-init:
    terraform init

[private, working-directory: '02-bootstrap']
talos-plan:
    terraform plan -var-file="../{{cluster_config}}" -var-file="../{{cluster_secrets}}" -out="{{talos_plan_path}}"

[private, working-directory: '02-bootstrap']
talos-apply:
    terraform apply "{{talos_plan_path}}"
    
[private, working-directory: '01-provision']
tflint-provision:
    tflint --config=.tflint.hcl

[private, working-directory: '02-bootstrap']
tflint-bootstrap:
    tflint --config=.tflint.hcl

provision-vms: require-config provision-init provision-plan provision-apply

bootstrap-cluster: require-config ensure-generated-dir provision-init provision-refresh talos-init talos-plan talos-apply

tflint: tflint-provision tflint-bootstrap

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

reconcile-flux: require-kubeconfig
    env KUBECONFIG="$$(pwd)/{{generated_dir}}/kubeconfig" flux reconcile source git flux-system -n flux-system
    env KUBECONFIG="$$(pwd)/{{generated_dir}}/kubeconfig" flux reconcile kustomization flux-system -n flux-system --with-source

[working-directory: '01-provision']
destroy-cluster:
    terraform destroy -var-file="../{{cluster_config}}" -var-file="../{{cluster_secrets}}"
