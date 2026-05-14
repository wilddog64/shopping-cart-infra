#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: keycloak-reconcile.sh [--namespace NAMESPACE] [--pod POD] [--realm REALM]

Reconcile the live Keycloak realm from the rendered shopping-cart realm JSON
without rebuilding the cluster.
EOF
}

namespace="identity"
pod=""
realm="${KC_REALM:-shopping-cart}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --namespace)
      namespace="${2:?missing namespace}"
      shift 2
      ;;
    --pod)
      pod="${2:?missing pod}"
      shift 2
      ;;
    --realm)
      realm="${2:?missing realm}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "$pod" ]]; then
  pod="$(kubectl get pod -n "$namespace" -l app.kubernetes.io/name=keycloak -o jsonpath='{.items[0].metadata.name}')"
fi

if [[ -z "$pod" ]]; then
  echo "ERROR: no Keycloak pod found in namespace $namespace" >&2
  exit 1
fi

kubectl wait -n "$namespace" --for=condition=Ready "pod/$pod" --timeout=300s >/dev/null

kubectl exec -n "$namespace" "$pod" -- bash -s -- "$realm" <<'EOF'
set -euo pipefail

realm="${1:?missing realm}"
rendered_file="/tmp/${realm}.rendered.json"

escape_sed() {
  printf '%s' "$1" | sed -e 's/[\/&]/\\&/g'
}

render_realm() {
  local input_file="/realm/realm-shopping-cart.json"
  local argocd_client_secret order_service_client_secret product_catalog_client_secret grafana_client_secret

  argocd_client_secret="$(escape_sed "${ARGOCD_CLIENT_SECRET}")"
  order_service_client_secret="$(escape_sed "${ORDER_SERVICE_CLIENT_SECRET}")"
  product_catalog_client_secret="$(escape_sed "${PRODUCT_CATALOG_CLIENT_SECRET}")"
  grafana_client_secret="$(escape_sed "${GRAFANA_CLIENT_SECRET}")"

  sed \
    -e "s/\${ARGOCD_CLIENT_SECRET}/${argocd_client_secret}/g" \
    -e "s/\${ORDER_SERVICE_CLIENT_SECRET}/${order_service_client_secret}/g" \
    -e "s/\${PRODUCT_CATALOG_CLIENT_SECRET}/${product_catalog_client_secret}/g" \
    -e "s/\${GRAFANA_CLIENT_SECRET}/${grafana_client_secret}/g" \
    "${input_file}" > "${rendered_file}"
}

render_realm

/opt/keycloak/bin/kcadm.sh config credentials \
  --server http://localhost:8080 \
  --realm master \
  --user "${KEYCLOAK_ADMIN}" \
  --password "${KEYCLOAK_ADMIN_PASSWORD}" >/dev/null

if /opt/keycloak/bin/kcadm.sh get "realms/${realm}" >/dev/null 2>&1; then
  echo "Realm ${realm} exists; applying partial import"
else
  echo "Realm ${realm} is missing; creating realm shell first"
  /opt/keycloak/bin/kcadm.sh create realms -s "realm=${realm}" -s "enabled=true" >/dev/null
fi

/opt/keycloak/bin/kcadm.sh create partialImport \
  -r "${realm}" \
  -s ifResourceExists=OVERWRITE \
  -f "${rendered_file}"
EOF
