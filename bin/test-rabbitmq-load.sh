#!/usr/bin/env bash
# RabbitMQ Load Test Helper
# Wrapper script with pre-configured environment for K8s cluster
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default configuration for K8s NodePort access
export RABBITMQ_HOST="${RABBITMQ_HOST:-localhost}"
export RABBITMQ_PORT="${RABBITMQ_PORT:-30672}"
export RABBITMQ_USERNAME="${RABBITMQ_USERNAME:-demo}"
export RABBITMQ_PASSWORD="${RABBITMQ_PASSWORD:-demo}"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

usage() {
    echo -e "${BLUE}RabbitMQ Load Test Helper${NC}"
    echo ""
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  quick         Quick test (50 msgs/sec for 5s)"
    echo "  burst         Burst test (1000 msgs/sec for 30s)"
    echo "  sustained     Sustained load (100 msgs/sec for 10 min)"
    echo "  stress        Stress test with ramp-up"
    echo "  trigger-alert Build queue to trigger alert (500 msgs/sec for 60s)"
    echo "  cleanup       Clean up test queues"
    echo "  status        Show RabbitMQ queue status"
    echo "  alerts        Show active Prometheus alerts"
    echo "  dashboard     Open Grafana dashboard (port-forward)"
    echo "  prometheus    Open Prometheus UI (port-forward)"
    echo ""
    echo "Options:"
    echo "  -d, --duration   Duration in seconds"
    echo "  -r, --rate       Messages per second"
    echo ""
    echo "Environment (auto-configured for K8s):"
    echo "  RABBITMQ_HOST=$RABBITMQ_HOST"
    echo "  RABBITMQ_PORT=$RABBITMQ_PORT"
    echo "  RABBITMQ_USERNAME=$RABBITMQ_USERNAME"
    echo ""
    echo "Examples:"
    echo "  $0 quick              # Quick sanity test"
    echo "  $0 burst              # Full burst test"
    echo "  $0 trigger-alert      # Build queue depth to trigger alert"
    echo "  $0 status             # Check queue status"
}

check_rabbitmq() {
    echo -e "${GREEN}Checking RabbitMQ connection...${NC}"
    if curl -s -u "${RABBITMQ_USERNAME}:${RABBITMQ_PASSWORD}" \
        "http://${RABBITMQ_HOST}:15672/api/overview" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ RabbitMQ is accessible${NC}"
        return 0
    else
        echo -e "${YELLOW}⚠ Cannot reach RabbitMQ Management API at ${RABBITMQ_HOST}:15672${NC}"
        echo "  Trying AMQP port ${RABBITMQ_PORT}..."
        return 0
    fi
}

show_status() {
    echo -e "${BLUE}=== RabbitMQ Queue Status ===${NC}"
    echo ""

    # Try kubectl first
    if kubectl get pods -n shopping-cart-data 2>/dev/null | grep -q rabbitmq; then
        kubectl exec -n shopping-cart-data rabbitmq-0 -- \
            rabbitmqctl list_queues name messages consumers --formatter=pretty_table 2>/dev/null || \
        kubectl exec -n shopping-cart-data rabbitmq-0 -- \
            rabbitmqctl list_queues name messages consumers
    else
        # Fall back to management API
        curl -s -u "${RABBITMQ_USERNAME}:${RABBITMQ_PASSWORD}" \
            "http://${RABBITMQ_HOST}:15672/api/queues" 2>/dev/null | \
            python3 -c "
import sys, json
try:
    queues = json.load(sys.stdin)
    print(f\"{'Queue':<40} {'Messages':>10} {'Consumers':>10}\")
    print('-' * 62)
    for q in queues:
        print(f\"{q['name']:<40} {q.get('messages',0):>10} {q.get('consumers',0):>10}\")
except:
    print('Unable to fetch queue status')
" 2>/dev/null || echo "Unable to connect to RabbitMQ"
    fi
}

show_alerts() {
    echo -e "${BLUE}=== Prometheus RabbitMQ Alerts ===${NC}"
    echo ""

    # Check if we can reach Prometheus
    local prom_url="http://localhost:9090"

    if ! curl -s "${prom_url}/api/v1/rules" > /dev/null 2>&1; then
        echo -e "${YELLOW}Prometheus not accessible at ${prom_url}${NC}"
        echo ""
        echo "To access Prometheus, run:"
        echo "  kubectl port-forward -n monitoring svc/prometheus-operated 9090:9090"
        echo ""
        echo "Then run this command again."
        return 1
    fi

    # Fetch and display RabbitMQ alerts
    curl -s "${prom_url}/api/v1/rules" 2>/dev/null | \
        python3 -c "
import sys, json
data = json.load(sys.stdin)
print(f\"{'Alert Name':<35} {'State':>10} {'Severity':>10}\")
print('-' * 57)
for group in data.get('data', {}).get('groups', []):
    if 'rabbitmq' in group.get('name', '').lower():
        for rule in group.get('rules', []):
            if rule.get('type') == 'alerting':
                name = rule.get('name', '')[:34]
                state = rule.get('state', 'unknown')
                severity = rule.get('labels', {}).get('severity', '-')
                print(f\"{name:<35} {state:>10} {severity:>10}\")
"
}

open_dashboard() {
    echo -e "${BLUE}Opening Grafana Dashboard...${NC}"
    echo ""
    echo "Starting port-forward to Grafana..."
    echo "Open in browser: http://localhost:3000"
    echo "Dashboard: RabbitMQ Overview"
    echo ""
    echo "Press Ctrl+C to stop"
    kubectl port-forward -n monitoring svc/grafana 3000:3000
}

open_prometheus() {
    echo -e "${BLUE}Opening Prometheus UI...${NC}"
    echo ""
    echo "Starting port-forward to Prometheus..."
    echo "Open in browser: http://localhost:9090/alerts"
    echo ""
    echo "Press Ctrl+C to stop"
    kubectl port-forward -n monitoring svc/prometheus-operated 9090:9090
}

# Parse command
COMMAND="${1:-}"
shift || true

case "$COMMAND" in
    quick)
        check_rabbitmq
        echo ""
        exec "$SCRIPT_DIR/load-test-rabbitmq.sh" burst -d 5 -r 50 "$@"
        ;;
    burst)
        check_rabbitmq
        echo ""
        exec "$SCRIPT_DIR/load-test-rabbitmq.sh" burst "$@"
        ;;
    sustained)
        check_rabbitmq
        echo ""
        exec "$SCRIPT_DIR/load-test-rabbitmq.sh" sustained "$@"
        ;;
    stress)
        check_rabbitmq
        echo ""
        exec "$SCRIPT_DIR/load-test-rabbitmq.sh" stress "$@"
        ;;
    trigger-alert)
        check_rabbitmq
        echo ""
        echo -e "${YELLOW}Building queue depth to trigger RabbitMQQueueDepthHigh alert...${NC}"
        echo "This will publish ~30,000 messages without consumers."
        echo ""
        exec "$SCRIPT_DIR/load-test-rabbitmq.sh" burst -d 60 -r 500 "$@"
        ;;
    cleanup)
        exec "$SCRIPT_DIR/load-test-rabbitmq.sh" cleanup
        ;;
    status)
        show_status
        ;;
    alerts)
        show_alerts
        ;;
    dashboard)
        open_dashboard
        ;;
    prometheus)
        open_prometheus
        ;;
    -h|--help|help|"")
        usage
        ;;
    *)
        echo "Unknown command: $COMMAND"
        echo ""
        usage
        exit 1
        ;;
esac
