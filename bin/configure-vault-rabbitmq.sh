#!/usr/bin/env bash
#
# configure-vault-rabbitmq.sh
# Configure Vault RabbitMQ secrets engine for dynamic credential generation
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Configuration
VAULT_NAMESPACE="${VAULT_NAMESPACE:-vault}"
RABBITMQ_NAMESPACE="${RABBITMQ_NAMESPACE:-shopping-cart-data}"
RABBITMQ_SERVICE="${RABBITMQ_SERVICE:-rabbitmq-management}"
RABBITMQ_PORT="${RABBITMQ_PORT:-15672}"
RABBITMQ_ADMIN_USER="${RABBITMQ_ADMIN_USER:-guest}"
RABBITMQ_ADMIN_PASS="${RABBITMQ_ADMIN_PASS:-guest}"

# Vault RabbitMQ mount path
RABBITMQ_MOUNT_PATH="${RABBITMQ_MOUNT_PATH:-rabbitmq}"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl not found. Please install kubectl."
        exit 1
    fi

    # Check Vault pod
    if ! kubectl get pod -n "${VAULT_NAMESPACE}" vault-0 &> /dev/null; then
        log_error "Vault pod not found in namespace ${VAULT_NAMESPACE}"
        exit 1
    fi

    # Check RabbitMQ service
    if ! kubectl get svc -n "${RABBITMQ_NAMESPACE}" "${RABBITMQ_SERVICE}" &> /dev/null; then
        log_error "RabbitMQ service ${RABBITMQ_SERVICE} not found in namespace ${RABBITMQ_NAMESPACE}"
        exit 1
    fi

    log_info "Prerequisites check passed"
}

# Get Vault root token
get_vault_token() {
    log_info "Retrieving Vault root token..."
    VAULT_TOKEN=$(kubectl get secret -n "${VAULT_NAMESPACE}" vault-root -o jsonpath='{.data.root_token}' | base64 -d)
    if [ -z "${VAULT_TOKEN}" ]; then
        log_error "Failed to retrieve Vault root token"
        exit 1
    fi
    log_info "Vault token retrieved successfully"
}

# Execute Vault command
vault_exec() {
    kubectl exec -n "${VAULT_NAMESPACE}" vault-0 -- env VAULT_TOKEN="${VAULT_TOKEN}" VAULT_ADDR=http://127.0.0.1:8200 vault "$@"
}

# Enable RabbitMQ secrets engine
enable_rabbitmq_engine() {
    log_info "Enabling RabbitMQ secrets engine at path '${RABBITMQ_MOUNT_PATH}'..."

    if vault_exec secrets list | grep -q "^${RABBITMQ_MOUNT_PATH}/"; then
        log_warn "RabbitMQ secrets engine already enabled at ${RABBITMQ_MOUNT_PATH}/"
    else
        vault_exec secrets enable -path="${RABBITMQ_MOUNT_PATH}" rabbitmq
        log_info "RabbitMQ secrets engine enabled successfully"
    fi
}

# Configure RabbitMQ connection
configure_connection() {
    log_info "Configuring Vault-RabbitMQ connection..."

    local connection_uri="http://${RABBITMQ_SERVICE}.${RABBITMQ_NAMESPACE}.svc.cluster.local:${RABBITMQ_PORT}"

    vault_exec write "${RABBITMQ_MOUNT_PATH}/config/connection" \
        connection_uri="${connection_uri}" \
        username="${RABBITMQ_ADMIN_USER}" \
        password="${RABBITMQ_ADMIN_PASS}"

    log_info "Connection configured: ${connection_uri}"
}

# Create Vault role for order publisher
create_order_publisher_role() {
    log_info "Creating 'order-publisher' role..."

    vault_exec write "${RABBITMQ_MOUNT_PATH}/roles/order-publisher" \
        vhosts='{"/": {"write": "orders\\..*", "read": ""}}' \
        tags="management"

    log_info "Role 'order-publisher' created (write access to orders.* queues/exchanges)"
}

# Create Vault role for order consumer
create_order_consumer_role() {
    log_info "Creating 'order-consumer' role..."

    vault_exec write "${RABBITMQ_MOUNT_PATH}/roles/order-consumer" \
        vhosts='{"/": {"write": "", "read": "orders\\..*", "configure": "orders\\..*"}}' \
        tags="management"

    log_info "Role 'order-consumer' created (read/configure access to orders.* queues)"
}

# Create Vault role for event publisher
create_event_publisher_role() {
    log_info "Creating 'event-publisher' role..."

    vault_exec write "${RABBITMQ_MOUNT_PATH}/roles/event-publisher" \
        vhosts='{"/": {"write": ".*\\.events", "read": ""}}' \
        tags="management"

    log_info "Role 'event-publisher' created (write access to *.events exchanges)"
}

# Create Vault role for admin access
create_admin_role() {
    log_info "Creating 'admin' role..."

    vault_exec write "${RABBITMQ_MOUNT_PATH}/roles/admin" \
        vhosts='{"/": {"configure": ".*", "write": ".*", "read": ".*"}}' \
        tags="administrator"

    log_info "Role 'admin' created (full access to all resources)"
}

# Create Vault role for full-access (used by applications)
create_full_access_role() {
    log_info "Creating 'full-access' role for application use..."

    vault_exec write "${RABBITMQ_MOUNT_PATH}/roles/full-access" \
        vhosts='{"/": {"configure": ".*", "write": ".*", "read": ".*"}}' \
        tags="management"

    log_info "Role 'full-access' created (full access for applications)"
}

# Set default lease TTL
configure_lease_ttl() {
    log_info "Configuring lease TTL (1 hour)..."

    vault_exec write "${RABBITMQ_MOUNT_PATH}/config/lease" \
        ttl="1h" \
        max_ttl="24h"

    log_info "Lease TTL configured (default: 1h, max: 24h)"
}

# Test credential generation
test_credential_generation() {
    log_info "Testing dynamic credential generation..."

    log_info "Generating credentials for 'full-access' role..."
    if vault_exec read "${RABBITMQ_MOUNT_PATH}/creds/full-access"; then
        log_info "Credential generation test PASSED"
    else
        log_error "Credential generation test FAILED"
        return 1
    fi
}

# Display configuration summary
display_summary() {
    echo ""
    log_info "=========================================="
    log_info "Vault-RabbitMQ Integration Summary"
    log_info "=========================================="
    echo ""
    echo "  Mount Path: ${RABBITMQ_MOUNT_PATH}"
    echo "  Connection: http://${RABBITMQ_SERVICE}.${RABBITMQ_NAMESPACE}.svc.cluster.local:${RABBITMQ_PORT}"
    echo "  Lease TTL: 1 hour (max: 24 hours)"
    echo ""
    echo "  Available Roles:"
    echo "    - order-publisher   : Write to orders.* queues/exchanges"
    echo "    - order-consumer    : Read/configure orders.* queues"
    echo "    - event-publisher   : Write to *.events exchanges"
    echo "    - admin             : Full administrative access"
    echo "    - full-access       : Full access for applications"
    echo ""
    echo "  To generate credentials:"
    echo "    vault read ${RABBITMQ_MOUNT_PATH}/creds/<role-name>"
    echo ""
    echo "  Example:"
    echo "    vault read ${RABBITMQ_MOUNT_PATH}/creds/full-access"
    echo ""
    log_info "=========================================="
}

# Main execution
main() {
    log_info "Starting Vault-RabbitMQ configuration..."
    echo ""

    check_prerequisites
    get_vault_token

    enable_rabbitmq_engine
    configure_connection

    create_order_publisher_role
    create_order_consumer_role
    create_event_publisher_role
    create_admin_role
    create_full_access_role

    configure_lease_ttl

    echo ""
    test_credential_generation

    echo ""
    display_summary

    log_info "Vault-RabbitMQ configuration complete!"
}

# Run main function
main "$@"
