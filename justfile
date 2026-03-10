set shell := ["bash", "-ceu", "-o", "pipefail", "-c"]

cluster_config := "cluster.tfvars"
cluster_example := "cluster.tfvars.example"
cluster_secrets := "cluster.secrets.tfvars"
cluster_secrets_example := "cluster.secrets.tfvars.example"
provision_plan_path := "tfplan"
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

[private]
require-config:
    if [ ! -f "{{cluster_config}}" ]; then echo "Missing {{cluster_config}}. Run 'just init-config' first." >&2; exit 1; fi
    if [ ! -f "{{cluster_secrets}}" ]; then echo "Missing {{cluster_secrets}}. Run 'just init-config' first." >&2; exit 1; fi

[private]
ensure-generated-dir:
    mkdir -p "{{generated_dir}}"

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

[private, working-directory: '02-talos']
talos-init:
    terraform init

[private, working-directory: '02-talos']
talos-plan:
    terraform plan -var-file="../{{cluster_config}}" -var-file="../{{cluster_secrets}}" -out="{{talos_plan_path}}"

[private, working-directory: '02-talos']
talos-apply:
    terraform apply "{{talos_plan_path}}"
    

provision-vms: require-config provision-init provision-plan provision-apply

bootstrap-cluster: require-config ensure-generated-dir provision-init provision-refresh talos-init talos-plan talos-apply

kubeconfig:
    if [ ! -f "{{generated_dir}}/kubeconfig" ]; then echo "Missing {{generated_dir}}/kubeconfig. Run 'just bootstrap-cluster' first." >&2; exit 1; fi
    printf '%s\n' "$$(pwd)/{{generated_dir}}/kubeconfig"

[private, working-directory: '02-talos']
print-cluster-info:
    terraform output cluster_info

[working-directory: '01-provision']
destroy-cluster:
    terraform destroy -var-file="../{{cluster_config}}" -var-file="../{{cluster_secrets}}"
