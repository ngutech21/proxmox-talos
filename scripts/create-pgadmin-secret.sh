#!/usr/bin/env zsh

set -euo pipefail

if ! command -v sops >/dev/null 2>&1; then
  echo "Missing 'sops' in PATH." >&2
  exit 1
fi

out_path="${1:-}"
password="${2:-}"

if [[ -z "$out_path" ]]; then
  echo "Usage: create-pgadmin-secret.sh <output-path> [password]" >&2
  exit 1
fi

mkdir -p "$(dirname "$out_path")"

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
case "$out_path" in
  "$repo_root"/*)
    sops_path="${out_path#$repo_root/}"
    ;;
  *)
    sops_path="$out_path"
    ;;
esac

generated_password="false"
if [[ -z "$password" ]]; then
  if ! command -v openssl >/dev/null 2>&1; then
    echo "Missing 'openssl' in PATH to generate a password automatically." >&2
    exit 1
  fi
  password="$(openssl rand -base64 24 | tr -d '\n')"
  generated_password="true"
fi

tmp_plain="$(mktemp)"
trap 'rm -f "$tmp_plain"' EXIT

cat >"$tmp_plain" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: pgadmin-credentials
  namespace: pgadmin
type: Opaque
stringData:
  password: ${password}
EOF

sops --encrypt --filename-override "$sops_path" --input-type yaml --output-type yaml "$tmp_plain" >"$out_path"

echo "Wrote encrypted pgAdmin secret to $out_path"
if [[ "$generated_password" == "true" ]]; then
  echo "Generated pgAdmin password: $password"
fi
