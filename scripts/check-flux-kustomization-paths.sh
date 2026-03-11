#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

status=0

while IFS= read -r file; do
  if ! grep -Eq '^apiVersion:[[:space:]]+kustomize\.toolkit\.fluxcd\.io/' "$file"; then
    continue
  fi

  if ! grep -Eq '^kind:[[:space:]]+Kustomization$' "$file"; then
    continue
  fi

  name="$(awk '
    $1 == "metadata:" { in_metadata = 1; next }
    in_metadata && $1 == "name:" { print $2; exit }
  ' "$file")"

  path_value="$(awk '
    $1 == "spec:" { in_spec = 1; next }
    in_spec && $1 == "path:" { print $2; exit }
  ' "$file")"

  if [[ -z "$path_value" ]]; then
    echo "Missing spec.path in Flux Kustomization ${name:-<unknown>} ($file)" >&2
    status=1
    continue
  fi

  target_path="$repo_root/${path_value#./}"
  if [[ ! -d "$target_path" ]]; then
    echo "Flux Kustomization ${name:-<unknown>} points to missing directory: $path_value ($file)" >&2
    status=1
  fi
done < <(find 03-infrastructure -type f -name '*.yaml' | sort)

exit "$status"
