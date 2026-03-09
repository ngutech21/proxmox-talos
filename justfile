set shell := ["bash", "-ceu", "-o", "pipefail", "-c"]

cluster_config := "cluster.tfvars"
cluster_example := "cluster.tfvars.example"
cluster_secrets := "cluster.secrets.tfvars"
cluster_secrets_example := "cluster.secrets.tfvars.example"
provision_dir := "01-provision"
tfplan_path := "tfplan"

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
    terraform -chdir="{{provision_dir}}" plan -var-file="../{{cluster_config}}" -var-file="../{{cluster_secrets}}" -out="{{tfplan_path}}"
    terraform -chdir="{{provision_dir}}" apply "{{tfplan_path}}"
