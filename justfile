set shell := ["bash", "-ceu", "-o", "pipefail", "-c"]

cluster_config := "cluster.tfvars"
cluster_example := "cluster.tfvars.example"
cluster_secrets := "cluster.secrets.tfvars"
cluster_secrets_example := "cluster.secrets.tfvars.example"
provision_dir := "01-provision"
provision_plan_path := "tfplan"
talos_dir := "02-talos"
talos_plan_path := "tfplan"
generated_dir := "02-talos/.generated"

default:
    @just --list

init-config:
    if [ -f "{{cluster_config}}" ]; then echo "{{cluster_config}} already exists" >&2; exit 1; fi
    if [ -f "{{cluster_secrets}}" ]; then echo "{{cluster_secrets}} already exists" >&2; exit 1; fi
    cp "{{cluster_example}}" "{{cluster_config}}"
    cp "{{cluster_secrets_example}}" "{{cluster_secrets}}"
    echo "Created {{cluster_config}} from {{cluster_example}}"
    echo "Created {{cluster_secrets}} from {{cluster_secrets_example}}"

provision-vms:
    if [ ! -f "{{cluster_config}}" ]; then echo "Missing {{cluster_config}}. Run 'just init-config' first." >&2; exit 1; fi
    if [ ! -f "{{cluster_secrets}}" ]; then echo "Missing {{cluster_secrets}}. Run 'just init-config' first." >&2; exit 1; fi
    terraform -chdir="{{provision_dir}}" init
    terraform -chdir="{{provision_dir}}" plan -var-file="../{{cluster_config}}" -var-file="../{{cluster_secrets}}" -out="{{provision_plan_path}}"
    terraform -chdir="{{provision_dir}}" apply "{{provision_plan_path}}"

bootstrap-cluster:
    if [ ! -f "{{cluster_config}}" ]; then echo "Missing {{cluster_config}}. Run 'just init-config' first." >&2; exit 1; fi
    if [ ! -f "{{cluster_secrets}}" ]; then echo "Missing {{cluster_secrets}}. Run 'just init-config' first." >&2; exit 1; fi
    mkdir -p "{{generated_dir}}"
    terraform -chdir="{{provision_dir}}" init
    terraform -chdir="{{provision_dir}}" apply -refresh-only -auto-approve -var-file="../{{cluster_config}}" -var-file="../{{cluster_secrets}}"
    terraform -chdir="{{talos_dir}}" init
    terraform -chdir="{{talos_dir}}" plan -var-file="../{{cluster_config}}" -var-file="../{{cluster_secrets}}" -out="{{talos_plan_path}}"
    terraform -chdir="{{talos_dir}}" apply "{{talos_plan_path}}"

kubeconfig:
    if [ ! -f "{{generated_dir}}/kubeconfig" ]; then echo "Missing {{generated_dir}}/kubeconfig. Run 'just bootstrap-cluster' first." >&2; exit 1; fi
    printf '%s\n' "$$(pwd)/{{generated_dir}}/kubeconfig"

print-cluster-info:
    terraform -chdir="{{talos_dir}}" output cluster_info

destroy-cluster:
    terraform -chdir="{{provision_dir}}" destroy -var-file="../{{cluster_config}}" -var-file="../{{cluster_secrets}}"
