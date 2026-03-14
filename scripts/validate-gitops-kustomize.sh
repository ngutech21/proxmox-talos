#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
polaris_config="$repo_root/.polaris.yaml"

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl is required" >&2
  exit 1
fi

if ! command -v kubeconform >/dev/null 2>&1; then
  echo "kubeconform is required" >&2
  exit 1
fi

if ! command -v polaris >/dev/null 2>&1; then
  echo "polaris is required" >&2
  exit 1
fi

if [ ! -f "$polaris_config" ]; then
  echo "Missing Polaris config: $polaris_config" >&2
  exit 1
fi

collect_dirs() {
  local input="$1"

  if [ ! -e "$input" ]; then
    echo "Path not found: $input" >&2
    exit 1
  fi

  if [ -f "$input" ]; then
    if [ "$(basename "$input")" != "kustomization.yaml" ]; then
      echo "Expected a kustomization.yaml file, got: $input" >&2
      exit 1
    fi
    dirname "$input"
    return
  fi

  if [ -f "$input/kustomization.yaml" ]; then
    printf '%s\n' "$input"
    return
  fi

  while IFS= read -r file; do
    dirname "$file"
  done < <(find "$input" -type f -name 'kustomization.yaml' -print)
}

if [ "$#" -eq 0 ]; then
  set -- 03-infrastructure
fi

temp_root="${TMPDIR:-/tmp}"
temp_root="${temp_root%/}"

tmp_dirs="$(mktemp)"
trap 'rm -f "$tmp_dirs"' EXIT

for input in "$@"; do
  collect_dirs "$input" >>"$tmp_dirs"
done

mapfile -t dirs < <(sort -u "$tmp_dirs")

if [ "${#dirs[@]}" -eq 0 ]; then
  echo "No kustomization.yaml files found in: $*" >&2
  exit 1
fi

for dir in "${dirs[@]}"; do
  echo "Rendering $dir"
  rendered="$(mktemp "${temp_root}/validate-manifests.XXXXXX")"
  mv "$rendered" "${rendered}.yaml"
  rendered="${rendered}.yaml"
  kubectl kustomize "$dir" >"$rendered"

  echo "Validating $dir"
  kubeconform \
    -strict \
    -summary \
    -ignore-missing-schemas \
    "$rendered"

  echo "Auditing $dir"
  polaris_output="$(polaris audit \
    --config "$polaris_config" \
    --audit-path "$rendered" \
    --format pretty \
    --only-show-failed-tests)"
  printf '%s\n' "$polaris_output"

  if printf '%s\n' "$polaris_output" | grep -q 'Controllers: 0'; then
    echo "Note: Polaris found no native controllers in $dir; the score is not meaningful for Flux/HelmRelease-only manifests." >&2
  fi

  rm -f "$rendered"
done
