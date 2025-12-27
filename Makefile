# Shopping Cart Infrastructure Makefile
# Simplifies common operations for RabbitMQ, Vault, and Monitoring

.PHONY: help status deploy clean
.PHONY: rabbitmq-status rabbitmq-deploy rabbitmq-logs rabbitmq-shell rabbitmq-ui
.PHONY: load-test load-test-quick load-test-burst load-test-stress purge purge-all
.PHONY: vault-status vault-ui vault-rabbitmq-creds
.PHONY: monitoring-status grafana prometheus alerts
.PHONY: k8s-status k8s-pods k8s-services

# Default namespace
NAMESPACE ?= shopping-cart-data
MONITORING_NS ?= monitoring

# RabbitMQ configuration
RABBITMQ_HOST ?= localhost
RABBITMQ_PORT ?= 30672
RABBITMQ_USERNAME ?= demo
RABBITMQ_PASSWORD ?= demo

export RABBITMQ_HOST RABBITMQ_PORT RABBITMQ_USERNAME RABBITMQ_PASSWORD

# Colors
GREEN  := $(shell tput -Txterm setaf 2)
YELLOW := $(shell tput -Txterm setaf 3)
BLUE   := $(shell tput -Txterm setaf 4)
RESET  := $(shell tput -Txterm sgr0)

##@ General

help: ## Show this help message
	@echo '${BLUE}Shopping Cart Infrastructure${RESET}'
	@echo ''
	@echo 'Usage: make ${GREEN}<target>${RESET}'
	@echo ''
	@awk 'BEGIN {FS = ":.*##"; printf ""} /^[a-zA-Z_-]+:.*?##/ { printf "  ${GREEN}%-20s${RESET} %s\n", $$1, $$2 } /^##@/ { printf "\n${YELLOW}%s${RESET}\n", substr($$0, 5) }' $(MAKEFILE_LIST)

status: k8s-status rabbitmq-status ## Show overall infrastructure status

##@ Kubernetes

k8s-status: ## Show K8s cluster status
	@echo "${BLUE}=== Kubernetes Cluster Status ===${RESET}"
	@kubectl cluster-info 2>/dev/null | head -2 || echo "Cluster not accessible"

k8s-pods: ## List all shopping-cart pods
	@echo "${BLUE}=== Shopping Cart Pods ===${RESET}"
	@kubectl get pods -n $(NAMESPACE) 2>/dev/null || echo "Namespace not found"
	@echo ""
	@kubectl get pods -n $(MONITORING_NS) 2>/dev/null | head -10 || true

k8s-services: ## List all shopping-cart services
	@echo "${BLUE}=== Shopping Cart Services ===${RESET}"
	@kubectl get svc -n $(NAMESPACE) 2>/dev/null || echo "Namespace not found"

##@ RabbitMQ

rabbitmq-status: ## Show RabbitMQ cluster status
	@echo "${BLUE}=== RabbitMQ Status ===${RESET}"
	@kubectl exec -n $(NAMESPACE) rabbitmq-0 -- rabbitmqctl cluster_status 2>/dev/null | head -20 || echo "RabbitMQ not accessible"

rabbitmq-queues: ## List all RabbitMQ queues
	@echo "${BLUE}=== RabbitMQ Queues ===${RESET}"
	@kubectl exec -n $(NAMESPACE) rabbitmq-0 -- rabbitmqctl list_queues name messages consumers 2>/dev/null || echo "RabbitMQ not accessible"

rabbitmq-deploy: ## Deploy RabbitMQ to cluster
	@echo "${BLUE}Deploying RabbitMQ...${RESET}"
	kubectl apply -f data-layer/rabbitmq/
	@echo "${GREEN}✓ RabbitMQ deployed${RESET}"

rabbitmq-logs: ## Show RabbitMQ logs
	kubectl logs -n $(NAMESPACE) rabbitmq-0 --tail=50 -f

rabbitmq-shell: ## Open shell in RabbitMQ pod
	kubectl exec -it -n $(NAMESPACE) rabbitmq-0 -- bash

rabbitmq-ui: ## Port-forward to RabbitMQ Management UI
	@echo "${BLUE}Opening RabbitMQ Management UI...${RESET}"
	@echo "URL: http://localhost:15672"
	@echo "Credentials: $(RABBITMQ_USERNAME)/$(RABBITMQ_PASSWORD)"
	@echo ""
	kubectl port-forward -n $(NAMESPACE) svc/rabbitmq-management 15672:15672

##@ Load Testing

load-test: load-test-quick ## Run quick load test (alias)

load-test-quick: ## Run quick load test (50 msgs/sec for 5s)
	@./bin/test-rabbitmq-load.sh quick

load-test-burst: ## Run burst load test (1000 msgs/sec for 30s)
	@./bin/test-rabbitmq-load.sh burst

load-test-sustained: ## Run sustained load test (100 msgs/sec for 10min)
	@./bin/test-rabbitmq-load.sh sustained

load-test-stress: ## Run stress test with ramp-up
	@./bin/test-rabbitmq-load.sh stress

load-test-alert: ## Run load test to trigger alerts
	@./bin/test-rabbitmq-load.sh trigger-alert

purge: ## Purge messages from load-test queue
	@./bin/test-rabbitmq-load.sh purge

purge-queue: ## Purge specific queue (usage: make purge-queue QUEUE=myqueue)
	@./bin/test-rabbitmq-load.sh purge $(QUEUE)

purge-all: ## Purge ALL queues (requires confirmation)
	@./bin/test-rabbitmq-load.sh purge-all

cleanup: ## Clean up test queues and exchanges
	@./bin/test-rabbitmq-load.sh cleanup

##@ Vault

vault-status: ## Show Vault status
	@echo "${BLUE}=== Vault Status ===${RESET}"
	@kubectl exec -n vault vault-0 -- vault status 2>/dev/null || echo "Vault not accessible"

vault-ui: ## Port-forward to Vault UI
	@echo "${BLUE}Opening Vault UI...${RESET}"
	@echo "URL: http://localhost:8200"
	kubectl port-forward -n vault svc/vault 8200:8200

vault-rabbitmq-creds: ## Get RabbitMQ credentials from Vault
	@echo "${BLUE}=== Vault RabbitMQ Credentials ===${RESET}"
	@kubectl exec -n vault vault-0 -- vault read rabbitmq/creds/order-publisher 2>/dev/null || echo "Vault not configured or not accessible"

##@ Monitoring

monitoring-status: ## Show monitoring stack status
	@echo "${BLUE}=== Monitoring Status ===${RESET}"
	@kubectl get pods -n $(MONITORING_NS) 2>/dev/null || echo "Monitoring namespace not found"

grafana: ## Port-forward to Grafana
	@echo "${BLUE}Opening Grafana...${RESET}"
	@echo "URL: http://localhost:3000"
	@echo "Dashboard: RabbitMQ Overview"
	kubectl port-forward -n $(MONITORING_NS) svc/grafana 3000:3000

prometheus: ## Port-forward to Prometheus
	@echo "${BLUE}Opening Prometheus...${RESET}"
	@echo "URL: http://localhost:9090/alerts"
	kubectl port-forward -n $(MONITORING_NS) svc/prometheus-operated 9090:9090

alerts: ## Show Prometheus RabbitMQ alerts
	@./bin/test-rabbitmq-load.sh alerts

##@ Deployment

deploy-rabbitmq: rabbitmq-deploy ## Deploy RabbitMQ (alias)

deploy-monitoring: ## Deploy monitoring stack
	@echo "${BLUE}Deploying monitoring...${RESET}"
	kubectl apply -f ../observability-stack/manifests/
	@echo "${GREEN}✓ Monitoring deployed${RESET}"

deploy-all: deploy-rabbitmq deploy-monitoring ## Deploy all infrastructure
	@echo "${GREEN}✓ All infrastructure deployed${RESET}"

##@ Cleanup

clean-test-data: purge-all cleanup ## Clean all test data

clean-rabbitmq: ## Delete RabbitMQ deployment
	@echo "${YELLOW}Deleting RabbitMQ...${RESET}"
	kubectl delete -f data-layer/rabbitmq/ --ignore-not-found
	@echo "${GREEN}✓ RabbitMQ deleted${RESET}"

##@ Development

info: ## Show environment info
	@echo "${BLUE}=== Environment Info ===${RESET}"
	@echo "NAMESPACE:         $(NAMESPACE)"
	@echo "MONITORING_NS:     $(MONITORING_NS)"
	@echo "RABBITMQ_HOST:     $(RABBITMQ_HOST)"
	@echo "RABBITMQ_PORT:     $(RABBITMQ_PORT)"
	@echo "RABBITMQ_USERNAME: $(RABBITMQ_USERNAME)"
	@echo ""
	@echo "${BLUE}=== Kubernetes Context ===${RESET}"
	@kubectl config current-context 2>/dev/null || echo "Not configured"

docs: ## Open documentation
	@echo "${BLUE}=== Documentation ===${RESET}"
	@echo "Message Queue Plan:    docs/plans/message-queue-implementation.md"
	@echo "RabbitMQ Operations:   docs/rabbitmq-operations.md"
	@echo "Vault Integration:     docs/vault-usage-guide.md"
