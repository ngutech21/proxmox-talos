#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl is required" >&2
  exit 1
fi

if ! command -v kubeconform >/dev/null 2>&1; then
  echo "kubeconform is required" >&2
  exit 1
fi

mapfile -t dirs < <(find 03-infrastructure -type f -name 'kustomization.yaml' -print | xargs -n1 dirname | sort -u)

for dir in "${dirs[@]}"; do
  echo "Rendering $dir"
  rendered="$(mktemp)"
  kubectl kustomize "$dir" >"$rendered"

  echo "Validating $dir"
  kubeconform \
    -strict \
    -summary \
    -ignore-missing-schemas \
    "$rendered"

  rm -f "$rendered"
done
