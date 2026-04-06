#!/usr/bin/env bash
# scripts/check-manifest-refs.sh
#
# Cross-checks that all secretKeyRef/configMapKeyRef keys in Deployment manifests
# exist in the corresponding base secret.yaml / configmap.yaml, and that every
# ExternalSecret secretKey appears in the base secret.yaml for that secret name.
#
# Usage: bash scripts/check-manifest-refs.sh
# Exit: 0 = clean, 1 = mismatches found
set -euo pipefail

errors=0

# ── Require yq ────────────────────────────────────────────────────────────────
if ! command -v yq >/dev/null 2>&1; then
  echo "ERROR: yq is required (brew install yq)" >&2
  exit 1
fi

# ── Per-deployment checks ──────────────────────────────────────────────────────
while IFS= read -r deploy; do
  ns_dir=$(dirname "$deploy")

  # secretKeyRef: verify each referenced key exists in the base secret
  while IFS= read -r line; do
    secret_name=$(echo "$line" | yq '.secretKeyRef.name // ""')
    key=$(echo "$line"         | yq '.secretKeyRef.key  // ""')
    [[ -z "$secret_name" || -z "$key" ]] && continue

    secret_file=$(find "$ns_dir" -maxdepth 1 -name "secret.yaml" | head -1)
    if [[ -z "$secret_file" ]]; then
      # tolerate — base secret may live elsewhere (ESO-only repos)
      continue
    fi

    if ! { yq '(.stringData // {}) | keys | .[]' "$secret_file" 2>/dev/null; \
            yq '(.data // {}) | keys | .[]' "$secret_file" 2>/dev/null; } \
        | grep -qx "$key"; then
      echo "ERROR: $deploy — secretKeyRef key '$key' (secret: $secret_name) not in $secret_file" >&2
      errors=$((errors + 1))
    fi
  done < <(yq '.spec.template.spec.containers[].env[]?.valueFrom // {}' "$deploy" 2>/dev/null)

  # configMapKeyRef: verify each referenced key exists in the base configmap
  while IFS= read -r line; do
    cm_name=$(echo "$line" | yq '.configMapKeyRef.name // ""')
    key=$(echo "$line"     | yq '.configMapKeyRef.key  // ""')
    [[ -z "$cm_name" || -z "$key" ]] && continue

    cm_file=$(find "$ns_dir" -maxdepth 1 -name "configmap.yaml" | head -1)
    [[ -z "$cm_file" ]] && continue

    if ! yq '.data // {} | keys | .[]' "$cm_file" 2>/dev/null \
        | grep -qx "$key"; then
      echo "ERROR: $deploy — configMapKeyRef key '$key' (configmap: $cm_name) not in $cm_file" >&2
      errors=$((errors + 1))
    fi
  done < <(yq '.spec.template.spec.containers[].env[]?.valueFrom // {}' "$deploy" 2>/dev/null)

done < <(find . -path "*/k8s/base/deployment.yaml" -not -path "./.git/*")

# ── ExternalSecret checks ──────────────────────────────────────────────────────
while IFS= read -r es; do
  es_dir=$(dirname "$es")

  while IFS= read -r secret_key; do
    [[ -z "$secret_key" ]] && continue

    # ExternalSecret writes into the secret named in spec.target.name (or metadata.name)
    target=$(yq '.spec.target.name // .metadata.name' "$es" 2>/dev/null)

    secret_file=$(find "$es_dir" -maxdepth 1 -name "secret.yaml" | head -1)
    # Also search parent dir (infra repos keep secrets alongside data-layer)
    if [[ -z "$secret_file" ]]; then
      while IFS= read -r candidate; do
        if grep -q "name: $target" "$candidate" 2>/dev/null; then
          secret_file="$candidate"
          break
        fi
      done < <(find "$(dirname "$es_dir")" -maxdepth 2 -name "secret.yaml" -print)
    fi
    [[ -z "$secret_file" ]] && continue

    if ! { yq '(.stringData // {}) | keys | .[]' "$secret_file" 2>/dev/null; \
            yq '(.data // {}) | keys | .[]' "$secret_file" 2>/dev/null; } \
        | grep -qx "$secret_key"; then
      echo "ERROR: $es — ExternalSecret secretKey '$secret_key' not in $secret_file" >&2
      errors=$((errors + 1))
    fi
  done < <(yq '.spec.data[].secretKey' "$es" 2>/dev/null)

done < <(find . -name "*externalsecret*.yaml" -not -path "./.git/*")

# ── Result ─────────────────────────────────────────────────────────────────────
if [[ $errors -gt 0 ]]; then
  echo "manifest-cross-check: $errors error(s)" >&2
  exit 1
fi
echo "manifest-cross-check: OK"
