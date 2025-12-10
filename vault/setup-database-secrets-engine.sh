#!/usr/bin/env bash
# Vault Database Secrets Engine Setup
# Configures Vault to generate dynamic PostgreSQL credentials and store Redis passwords

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

function print_success() { echo -e "${GREEN}✓ $1${NC}"; }
function print_error() { echo -e "${RED}✗ $1${NC}"; }
function print_info() { echo -e "${YELLOW}ℹ $1${NC}"; }

# Configuration
VAULT_ADDR="${VAULT_ADDR:-http://vault.vault.svc.cluster.local:8200}"
NAMESPACE_DATA="shopping-cart-data"

# PostgreSQL configuration
PG_PRODUCTS_HOST="postgresql-products.${NAMESPACE_DATA}.svc.cluster.local"
PG_PRODUCTS_PORT="5432"
PG_PRODUCTS_DB="products"
PG_PRODUCTS_ADMIN_USER="postgres"
PG_PRODUCTS_ADMIN_PASSWORD="${POSTGRES_PRODUCTS_PASSWORD:-changeme123}"

PG_ORDERS_HOST="postgresql-orders.${NAMESPACE_DATA}.svc.cluster.local"
PG_ORDERS_PORT="5432"
PG_ORDERS_DB="orders"
PG_ORDERS_ADMIN_USER="postgres"
PG_ORDERS_ADMIN_PASSWORD="${POSTGRES_ORDERS_PASSWORD:-changeme456}"

# Redis configuration
REDIS_CART_PASSWORD="${REDIS_CART_PASSWORD:-cartredis123}"
REDIS_ORDERS_CACHE_PASSWORD="${REDIS_ORDERS_CACHE_PASSWORD:-orderscache789}"

# TTL configuration
DEFAULT_TTL="${VAULT_DB_DEFAULT_TTL:-1h}"
MAX_TTL="${VAULT_DB_MAX_TTL:-24h}"

echo "========================================="
echo "Vault Database Secrets Engine Setup"
echo "========================================="
echo ""

# Check if running in Kubernetes
if [ -z "${KUBERNETES_SERVICE_HOST:-}" ]; then
    print_info "Not running in Kubernetes, using local Vault configuration"
    VAULT_ADDR="${VAULT_ADDR:-http://127.0.0.1:8200}"
fi

print_info "Vault Address: $VAULT_ADDR"
print_info "Namespace: $NAMESPACE_DATA"
echo ""

# Verify Vault is accessible
print_info "Verifying Vault connectivity..."
if ! vault status &> /dev/null; then
    print_error "Cannot connect to Vault at $VAULT_ADDR"
    print_info "Make sure VAULT_ADDR and VAULT_TOKEN are set correctly"
    exit 1
fi
print_success "Vault is accessible"

# Enable database secrets engine
print_info "Enabling database secrets engine..."
if vault secrets list | grep -q "^database/"; then
    print_info "Database secrets engine already enabled"
else
    vault secrets enable database
    print_success "Database secrets engine enabled"
fi

echo ""
echo "========================================="
echo "PostgreSQL Products Database Configuration"
echo "========================================="
echo ""

# Configure PostgreSQL products database
print_info "Configuring PostgreSQL products connection..."
vault write database/config/postgresql-products \
    plugin_name=postgresql-database-plugin \
    allowed_roles="products-readonly,products-readwrite" \
    connection_url="postgresql://{{username}}:{{password}}@${PG_PRODUCTS_HOST}:${PG_PRODUCTS_PORT}/${PG_PRODUCTS_DB}?sslmode=disable" \
    username="${PG_PRODUCTS_ADMIN_USER}" \
    password="${PG_PRODUCTS_ADMIN_PASSWORD}" \
    password_authentication=scram-sha-256
print_success "PostgreSQL products connection configured"

# Create readonly role
print_info "Creating products-readonly role..."
vault write database/roles/products-readonly \
    db_name=postgresql-products \
    creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}' INHERIT; \
GRANT CONNECT ON DATABASE ${PG_PRODUCTS_DB} TO \"{{name}}\"; \
GRANT USAGE ON SCHEMA public TO \"{{name}}\"; \
GRANT SELECT ON ALL TABLES IN SCHEMA public TO \"{{name}}\"; \
GRANT SELECT ON ALL SEQUENCES IN SCHEMA public TO \"{{name}}\"; \
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO \"{{name}}\";" \
    default_ttl="${DEFAULT_TTL}" \
    max_ttl="${MAX_TTL}"
print_success "products-readonly role created"

# Create readwrite role
print_info "Creating products-readwrite role..."
vault write database/roles/products-readwrite \
    db_name=postgresql-products \
    creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}' INHERIT; \
GRANT CONNECT ON DATABASE ${PG_PRODUCTS_DB} TO \"{{name}}\"; \
GRANT USAGE ON SCHEMA public TO \"{{name}}\"; \
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO \"{{name}}\"; \
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO \"{{name}}\"; \
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO \"{{name}}\"; \
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO \"{{name}}\";" \
    default_ttl="${DEFAULT_TTL}" \
    max_ttl="${MAX_TTL}"
print_success "products-readwrite role created"

echo ""
echo "========================================="
echo "PostgreSQL Orders Database Configuration"
echo "========================================="
echo ""

# Configure PostgreSQL orders database
print_info "Configuring PostgreSQL orders connection..."
vault write database/config/postgresql-orders \
    plugin_name=postgresql-database-plugin \
    allowed_roles="orders-readwrite" \
    connection_url="postgresql://{{username}}:{{password}}@${PG_ORDERS_HOST}:${PG_ORDERS_PORT}/${PG_ORDERS_DB}?sslmode=disable" \
    username="${PG_ORDERS_ADMIN_USER}" \
    password="${PG_ORDERS_ADMIN_PASSWORD}" \
    password_authentication=scram-sha-256
print_success "PostgreSQL orders connection configured"

# Create readwrite role for orders (orders service needs write access)
print_info "Creating orders-readwrite role..."
vault write database/roles/orders-readwrite \
    db_name=postgresql-orders \
    creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}' INHERIT; \
GRANT CONNECT ON DATABASE ${PG_ORDERS_DB} TO \"{{name}}\"; \
GRANT USAGE ON SCHEMA public TO \"{{name}}\"; \
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO \"{{name}}\"; \
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO \"{{name}}\"; \
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO \"{{name}}\"; \
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO \"{{name}}\";" \
    default_ttl="${DEFAULT_TTL}" \
    max_ttl="${MAX_TTL}"
print_success "orders-readwrite role created"

echo ""
echo "========================================="
echo "Redis Static Secrets Configuration"
echo "========================================="
echo ""

# Enable KV secrets engine if not already enabled
print_info "Ensuring KV secrets engine is enabled..."
if vault secrets list | grep -q "^secret/"; then
    print_info "KV secrets engine already enabled"
else
    vault secrets enable -path=secret kv-v2
    print_success "KV secrets engine enabled"
fi

# Store Redis cart password
print_info "Storing Redis cart password..."
vault kv put secret/redis/cart password="${REDIS_CART_PASSWORD}"
print_success "Redis cart password stored"

# Store Redis orders cache password
print_info "Storing Redis orders-cache password..."
vault kv put secret/redis/orders-cache password="${REDIS_ORDERS_CACHE_PASSWORD}"
print_success "Redis orders-cache password stored"

echo ""
echo "========================================="
echo "Verification"
echo "========================================="
echo ""

# Test credential generation for products
print_info "Testing credential generation for products-readonly..."
CREDS=$(vault read -format=json database/creds/products-readonly)
if [ $? -eq 0 ]; then
    USERNAME=$(echo "$CREDS" | jq -r '.data.username')
    print_success "Generated credentials: $USERNAME"

    # Revoke test credentials
    LEASE_ID=$(echo "$CREDS" | jq -r '.lease_id')
    vault lease revoke "$LEASE_ID" &> /dev/null
    print_info "Test credentials revoked"
else
    print_error "Failed to generate test credentials"
fi

# Test reading Redis password
print_info "Testing Redis cart password retrieval..."
REDIS_PASS=$(vault kv get -field=password secret/redis/cart)
if [ $? -eq 0 ]; then
    print_success "Redis cart password retrieved successfully"
else
    print_error "Failed to retrieve Redis cart password"
fi

echo ""
echo "========================================="
echo "Summary"
echo "========================================="
echo ""
echo "PostgreSQL Database Roles:"
echo "  - postgresql-products/products-readonly (SELECT only)"
echo "  - postgresql-products/products-readwrite (CRUD operations)"
echo "  - postgresql-orders/orders-readwrite (CRUD operations)"
echo ""
echo "Redis Static Secrets:"
echo "  - secret/redis/cart"
echo "  - secret/redis/orders-cache"
echo ""
echo "Credential TTLs:"
echo "  - Default: ${DEFAULT_TTL}"
echo "  - Maximum: ${MAX_TTL}"
echo ""
print_success "Vault database secrets engine configuration complete!"
echo ""
echo "Next steps:"
echo "  1. Verify ExternalSecrets can sync credentials:"
echo "     kubectl get externalsecrets -n ${NAMESPACE_DATA}"
echo "  2. Check generated Kubernetes secrets:"
echo "     kubectl get secrets -n ${NAMESPACE_DATA}"
echo "  3. Test database connectivity with dynamic credentials"
echo ""
