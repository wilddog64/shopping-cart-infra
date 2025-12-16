#!/usr/bin/env bash
#
# Test Vault-RabbitMQ Integration
# Validates dynamic credential generation and RabbitMQ connectivity
#

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Vault-RabbitMQ Integration Test${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Step 1: Get Vault root token
echo -e "${YELLOW}Step 1: Retrieving Vault root token...${NC}"
VAULT_TOKEN=$(kubectl get secret -n vault vault-root -o jsonpath='{.data.root_token}' | base64 -d)
echo -e "${GREEN}✓ Vault token retrieved${NC}"
echo ""

# Step 2: Generate RabbitMQ credentials from Vault
echo -e "${YELLOW}Step 2: Generating RabbitMQ credentials from Vault...${NC}"
CREDS=$(kubectl exec -n vault vault-0 -- env VAULT_TOKEN="${VAULT_TOKEN}" VAULT_ADDR=http://127.0.0.1:8200 vault read -format=json rabbitmq/creds/full-access)

RABBITMQ_USER=$(echo "$CREDS" | grep -o '"username":"[^"]*' | cut -d'"' -f4)
RABBITMQ_PASS=$(echo "$CREDS" | grep -o '"password":"[^"]*' | cut -d'"' -f4)
LEASE_ID=$(echo "$CREDS" | grep -o '"lease_id":"[^"]*' | cut -d'"' -f4)
LEASE_DURATION=$(echo "$CREDS" | grep -o '"lease_duration":[0-9]*' | cut -d':' -f2)

echo -e "${GREEN}✓ Credentials generated:${NC}"
echo "  Username: ${RABBITMQ_USER}"
echo "  Password: ${RABBITMQ_PASS:0:8}..."
echo "  Lease ID: ${LEASE_ID}"
echo "  Lease Duration: ${LEASE_DURATION} seconds ($(($LEASE_DURATION / 60)) minutes)"
echo ""

# Step 3: Get RabbitMQ Management UI IP
echo -e "${YELLOW}Step 3: Getting RabbitMQ connection details...${NC}"
RABBITMQ_IP=$(kubectl get svc -n shopping-cart-data rabbitmq-management -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
if [ -z "${RABBITMQ_IP}" ]; then
    RABBITMQ_IP=$(kubectl get svc -n shopping-cart-data rabbitmq -o jsonpath='{.spec.clusterIP}')
fi
echo -e "${GREEN}✓ RabbitMQ IP: ${RABBITMQ_IP}${NC}"
echo ""

# Step 4: Test RabbitMQ Management API with Vault credentials
echo -e "${YELLOW}Step 4: Testing RabbitMQ Management API access...${NC}"
kubectl exec -n shopping-cart-data rabbitmq-0 -- curl -s -u "${RABBITMQ_USER}:${RABBITMQ_PASS}" \
    http://localhost:15672/api/overview > /tmp/rabbitmq-overview.json

if [ -s /tmp/rabbitmq-overview.json ]; then
    RABBITMQ_VERSION=$(grep -o '"rabbitmq_version":"[^"]*' /tmp/rabbitmq-overview.json | cut -d'"' -f4)
    echo -e "${GREEN}✓ Successfully authenticated to RabbitMQ Management API${NC}"
    echo "  RabbitMQ Version: ${RABBITMQ_VERSION}"
else
    echo -e "${RED}✗ Failed to authenticate to RabbitMQ Management API${NC}"
    exit 1
fi
echo ""

# Step 5: Create a test queue using Vault credentials
echo -e "${YELLOW}Step 5: Creating test queue with dynamic credentials...${NC}"
QUEUE_NAME="vault-test-queue-$$"

kubectl exec -n shopping-cart-data rabbitmq-0 -- \
    rabbitmqadmin -u "${RABBITMQ_USER}" -p "${RABBITMQ_PASS}" \
    declare queue name="${QUEUE_NAME}" durable=true

echo -e "${GREEN}✓ Queue '${QUEUE_NAME}' created${NC}"
echo ""

# Step 6: Publish a message
echo -e "${YELLOW}Step 6: Publishing test message...${NC}"
TEST_MESSAGE="Hello from Vault-generated credentials at $(date)"

kubectl exec -n shopping-cart-data rabbitmq-0 -- \
    rabbitmqadmin -u "${RABBITMQ_USER}" -p "${RABBITMQ_PASS}" \
    publish routing_key="${QUEUE_NAME}" payload="${TEST_MESSAGE}"

echo -e "${GREEN}✓ Message published: ${TEST_MESSAGE}${NC}"
echo ""

# Step 7: Consume the message
echo -e "${YELLOW}Step 7: Consuming test message...${NC}"
MESSAGE=$(kubectl exec -n shopping-cart-data rabbitmq-0 -- \
    rabbitmqadmin -u "${RABBITMQ_USER}" -p "${RABBITMQ_PASS}" \
    get queue="${QUEUE_NAME}" ackmode=ack_requeue_false | grep payload | awk -F'|' '{print $3}' | xargs)

if [ "${MESSAGE}" == "${TEST_MESSAGE}" ]; then
    echo -e "${GREEN}✓ Message consumed successfully: ${MESSAGE}${NC}"
else
    echo -e "${RED}✗ Message mismatch!${NC}"
    echo "  Expected: ${TEST_MESSAGE}"
    echo "  Got: ${MESSAGE}"
    exit 1
fi
echo ""

# Step 8: List RabbitMQ users (verify our user exists)
echo -e "${YELLOW}Step 8: Verifying Vault-created user in RabbitMQ...${NC}"
USER_EXISTS=$(kubectl exec -n shopping-cart-data rabbitmq-0 -- \
    rabbitmqctl list_users | grep "${RABBITMQ_USER}" || echo "")

if [ -n "${USER_EXISTS}" ]; then
    echo -e "${GREEN}✓ User '${RABBITMQ_USER}' found in RabbitMQ${NC}"
    echo "  ${USER_EXISTS}"
else
    echo -e "${RED}✗ User not found in RabbitMQ${NC}"
    exit 1
fi
echo ""

# Step 9: Cleanup test queue
echo -e "${YELLOW}Step 9: Cleaning up test queue...${NC}"
kubectl exec -n shopping-cart-data rabbitmq-0 -- \
    rabbitmqadmin -u "${RABBITMQ_USER}" -p "${RABBITMQ_PASS}" \
    delete queue name="${QUEUE_NAME}"

echo -e "${GREEN}✓ Test queue deleted${NC}"
echo ""

# Step 10: Verify lease information
echo -e "${YELLOW}Step 10: Verifying Vault lease details...${NC}"
kubectl exec -n vault vault-0 -- env VAULT_TOKEN="${VAULT_TOKEN}" VAULT_ADDR=http://127.0.0.1:8200 \
    vault lease lookup "${LEASE_ID}" > /tmp/lease-info.txt

LEASE_RENEWABLE=$(grep "renewable" /tmp/lease-info.txt | awk '{print $2}')
LEASE_TTL=$(grep "ttl" /tmp/lease-info.txt | head -1 | awk '{print $2}')

echo -e "${GREEN}✓ Lease information:${NC}"
echo "  Renewable: ${LEASE_RENEWABLE}"
echo "  Remaining TTL: ${LEASE_TTL}"
echo ""

# Final Summary
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✅ ALL TESTS PASSED!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Vault-RabbitMQ integration is working correctly:"
echo "  ✓ Dynamic credentials generated from Vault"
echo "  ✓ Credentials work for RabbitMQ authentication"
echo "  ✓ Queue creation successful"
echo "  ✓ Message publish/consume working"
echo "  ✓ User created in RabbitMQ with appropriate permissions"
echo "  ✓ Lease management functioning"
echo ""
echo "Credential Details:"
echo "  Lease ID: ${LEASE_ID}"
echo "  Duration: $(($LEASE_DURATION / 60)) minutes"
echo "  Renewable: ${LEASE_RENEWABLE}"
echo ""
echo "The credential will automatically expire in $(($LEASE_DURATION / 60)) minutes."
echo "RabbitMQ will automatically remove the user: ${RABBITMQ_USER}"
