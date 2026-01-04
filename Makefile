# Shopping Cart Infrastructure Makefile
# Simplifies common operations for RabbitMQ, Vault, and Monitoring

.PHONY: help status deploy clean docs info
.PHONY: rabbitmq-status rabbitmq-deploy rabbitmq-logs rabbitmq-shell rabbitmq-ui rabbitmq-queues
.PHONY: rabbitmq-backup rabbitmq-restore rabbitmq-backup-list
.PHONY: load-test load-test-quick load-test-burst load-test-stress load-test-sustained load-test-alert
.PHONY: purge purge-queue purge-count purge-all cleanup
.PHONY: vault-status vault-ui vault-rabbitmq-creds
.PHONY: monitoring-status grafana prometheus alertmanager alerts
.PHONY: k8s-status k8s-pods k8s-services
.PHONY: argocd-status argocd-ui argocd-apps argocd-sync argocd-deploy argocd-project argocd-delete
.PHONY: identity-status identity-deploy identity-delete keycloak-ui keycloak-logs ldap-status ldap-shell

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

##@ Backup & Recovery

rabbitmq-backup: ## Backup RabbitMQ definitions (queues, exchanges, bindings)
	@./bin/rabbitmq-backup.sh

rabbitmq-backup-list: ## List available RabbitMQ backups
	@./bin/rabbitmq-restore.sh --list

rabbitmq-restore: ## Restore RabbitMQ from backup (usage: make rabbitmq-restore BACKUP=path)
	@if [ -z "$(BACKUP)" ]; then \
		echo "Usage: make rabbitmq-restore BACKUP=backups/rabbitmq/20241227-120000"; \
		echo ""; \
		./bin/rabbitmq-restore.sh --list; \
	else \
		./bin/rabbitmq-restore.sh $(BACKUP); \
	fi

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

purge-count: ## Purge N messages (usage: make purge-count COUNT=100 QUEUE=myqueue)
	@./bin/test-rabbitmq-load.sh purge-count $(COUNT) $(QUEUE)

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

alertmanager: ## Port-forward to Alertmanager
	@echo "${BLUE}Opening Alertmanager...${RESET}"
	@echo "URL: http://localhost:9093"
	kubectl port-forward -n $(MONITORING_NS) svc/alertmanager-operated 9093:9093

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

##@ ArgoCD

argocd-status: ## Show ArgoCD status
	@echo "${BLUE}=== ArgoCD Status ===${RESET}"
	@kubectl get pods -n argocd 2>/dev/null || echo "ArgoCD namespace not found"

argocd-ui: ## Port-forward to ArgoCD UI
	@echo "${BLUE}Opening ArgoCD UI...${RESET}"
	@echo "URL: https://localhost:8080"
	@echo "Username: admin"
	@echo "Password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
	kubectl port-forward -n argocd svc/argocd-server 8080:443

argocd-apps: ## List all ArgoCD applications
	@echo "${BLUE}=== ArgoCD Applications ===${RESET}"
	@kubectl get applications -n argocd 2>/dev/null || echo "No applications found"

argocd-project: ## Deploy ArgoCD project for shopping-cart
	@echo "${BLUE}Deploying ArgoCD project...${RESET}"
	kubectl apply -f argocd/projects/
	@echo "${GREEN}✓ ArgoCD project deployed${RESET}"

argocd-deploy: argocd-project ## Deploy all applications via ArgoCD
	@echo "${BLUE}Deploying ArgoCD applications...${RESET}"
	kubectl apply -f argocd/applications/
	@echo "${GREEN}✓ ArgoCD applications deployed${RESET}"

argocd-sync: ## Sync all shopping-cart applications
	@echo "${BLUE}Syncing shopping-cart applications...${RESET}"
	@argocd app sync order-service 2>/dev/null || kubectl patch application order-service -n argocd --type merge -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"syncStrategy":{"apply":{"force":true}}}}}' 2>/dev/null || echo "order-service not found"
	@argocd app sync product-catalog 2>/dev/null || kubectl patch application product-catalog -n argocd --type merge -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"syncStrategy":{"apply":{"force":true}}}}}' 2>/dev/null || echo "product-catalog not found"
	@echo "${GREEN}✓ Sync triggered${RESET}"

argocd-delete: ## Delete ArgoCD applications (keeps project)
	@echo "${YELLOW}Deleting ArgoCD applications...${RESET}"
	kubectl delete -f argocd/applications/order-service.yaml --ignore-not-found
	kubectl delete -f argocd/applications/product-catalog.yaml --ignore-not-found
	@echo "${GREEN}✓ ArgoCD applications deleted${RESET}"

##@ Identity (Keycloak + LDAP)

identity-status: ## Show identity stack status
	@echo "${BLUE}=== Identity Stack Status ===${RESET}"
	@kubectl get pods -n identity 2>/dev/null || echo "Identity namespace not found"

identity-deploy: ## Deploy identity stack (LDAP + Keycloak)
	@echo "${BLUE}Deploying LDAP...${RESET}"
	kubectl apply -k identity/ldap/
	@echo "${BLUE}Deploying Keycloak...${RESET}"
	kubectl apply -k identity/keycloak/
	@echo "${GREEN}✓ Identity stack deployed${RESET}"

identity-delete: ## Delete identity stack
	@echo "${YELLOW}Deleting identity stack...${RESET}"
	kubectl delete -k identity/keycloak/ --ignore-not-found
	kubectl delete -k identity/ldap/ --ignore-not-found
	@echo "${GREEN}✓ Identity stack deleted${RESET}"

keycloak-ui: ## Port-forward to Keycloak UI
	@echo "${BLUE}Opening Keycloak UI...${RESET}"
	@echo "URL: http://localhost:8080"
	@echo "Admin: admin / (check keycloak-secrets)"
	kubectl port-forward -n identity svc/keycloak 8080:80

keycloak-logs: ## Show Keycloak logs
	kubectl logs -n identity -l app.kubernetes.io/name=keycloak --tail=100 -f

ldap-status: ## Show LDAP status
	@echo "${BLUE}=== LDAP Status ===${RESET}"
	@kubectl exec -n identity -it $$(kubectl get pods -n identity -l app.kubernetes.io/name=ldap -o jsonpath='{.items[0].metadata.name}') -- ldapsearch -x -H ldap://localhost -b "dc=shopping-cart,dc=local" -D "cn=admin,dc=shopping-cart,dc=local" -w changeme "(objectClass=organizationalUnit)" dn 2>/dev/null || echo "LDAP not accessible"

ldap-shell: ## Open shell in LDAP pod
	kubectl exec -n identity -it $$(kubectl get pods -n identity -l app.kubernetes.io/name=ldap -o jsonpath='{.items[0].metadata.name}') -- bash

##@ Application Services

APPS_NS ?= shopping-cart-apps

apps-status: ## Show application services status
	@echo "${BLUE}=== Application Services ===${RESET}"
	@kubectl get pods -n $(APPS_NS) 2>/dev/null || echo "Apps namespace not found"
	@echo ""
	@kubectl get svc -n $(APPS_NS) 2>/dev/null || true

apps-logs-order: ## Show order-service logs
	kubectl logs -n $(APPS_NS) -l app.kubernetes.io/name=order-service --tail=100 -f

apps-logs-catalog: ## Show product-catalog logs
	kubectl logs -n $(APPS_NS) -l app.kubernetes.io/name=product-catalog --tail=100 -f

apps-logs-basket: ## Show basket-service logs
	kubectl logs -n $(APPS_NS) -l app.kubernetes.io/name=basket-service --tail=100 -f

apps-restart-order: ## Restart order-service
	kubectl rollout restart deployment -n $(APPS_NS) order-service

apps-restart-catalog: ## Restart product-catalog
	kubectl rollout restart deployment -n $(APPS_NS) product-catalog

apps-restart-basket: ## Restart basket-service
	kubectl rollout restart deployment -n $(APPS_NS) basket-service

apps-restart-all: ## Restart all application services
	kubectl rollout restart deployment -n $(APPS_NS) order-service product-catalog basket-service

apps-deploy: ## Deploy all application services
	@echo "${BLUE}Deploying application services...${RESET}"
	kubectl apply -k ../shopping-cart-order/k8s/base/ 2>/dev/null || echo "order-service not found"
	kubectl apply -k ../shopping-cart-product-catalog/k8s/base/ 2>/dev/null || echo "product-catalog not found"
	kubectl apply -k ../shopping-cart-basket/k8s/base/ 2>/dev/null || echo "basket-service not found"
	@echo "${GREEN}✓ Application services deployed${RESET}"

apps-test: ## Test application endpoints
	@echo "${BLUE}=== Testing Application Endpoints ===${RESET}"
	@echo -n "product-catalog: " && curl -s http://localhost:30082/health 2>/dev/null || echo "FAIL"
	@echo -n "order-service:   " && curl -s http://localhost:30081/actuator/health 2>/dev/null | head -c 50 || echo "FAIL"
	@echo -n "basket-service:  " && kubectl exec -n $(APPS_NS) -l app.kubernetes.io/name=basket-service -- wget -qO- http://localhost:8083/health 2>/dev/null || echo "FAIL"

##@ Container Images

images-build: ## Build all container images with podman
	@echo "${BLUE}Building container images...${RESET}"
	cd ../shopping-cart-order && podman build -f Dockerfile.local -t shopping-cart-order:latest .
	cd ../shopping-cart-product-catalog && podman build -f Dockerfile.local -t shopping-cart-product-catalog:latest .
	cd ../shopping-cart-basket && podman build -f Dockerfile.local -t shopping-cart-basket:latest .
	@echo "${GREEN}✓ Images built${RESET}"

images-save: ## Save images to /tmp for k3s import
	@echo "${BLUE}Saving images to /tmp...${RESET}"
	podman save localhost/shopping-cart-order:latest -o /tmp/shopping-cart-order.tar
	podman save localhost/shopping-cart-product-catalog:latest -o /tmp/shopping-cart-product-catalog.tar
	podman save localhost/shopping-cart-basket:latest -o /tmp/shopping-cart-basket.tar
	@echo "${GREEN}✓ Images saved${RESET}"

images-import: ## Import images to k3s (requires sudo)
	@echo "${BLUE}Importing images to k3s...${RESET}"
	@echo "Run: sudo ./bin/import-images.sh"

images-list: ## List shopping-cart images in k3s
	@echo "${BLUE}=== k3s Images ===${RESET}"
	@sudo k3s crictl images 2>/dev/null | grep shopping-cart || echo "No images found"

images-clean: ## Clean up podman images
	podman rmi localhost/shopping-cart-order:latest localhost/shopping-cart-product-catalog:latest localhost/shopping-cart-basket:latest 2>/dev/null || true
	podman system prune -f

##@ Database Management

db-orders-shell: ## Open psql shell to orders database
	kubectl exec -it -n $(NAMESPACE) postgresql-orders-0 -- psql -U postgres -d orders

db-products-shell: ## Open psql shell to products database
	kubectl exec -it -n $(NAMESPACE) postgresql-products-0 -- psql -U postgres -d products

db-orders-tables: ## List orders database tables
	kubectl exec -n $(NAMESPACE) postgresql-orders-0 -- psql -U postgres -d orders -c "\dt"

db-products-tables: ## List products database tables
	kubectl exec -n $(NAMESPACE) postgresql-products-0 -- psql -U postgres -d products -c "\dt"

db-orders-reset: ## Reset orders database (DROP ALL TABLES)
	@echo "${YELLOW}WARNING: This will delete all order data!${RESET}"
	@read -p "Are you sure? [y/N] " confirm && [ "$$confirm" = "y" ] && \
		kubectl exec -n $(NAMESPACE) postgresql-orders-0 -- psql -U postgres -d orders -c "DROP TABLE IF EXISTS order_items, payment_transactions, shipping_events, orders CASCADE;"

db-products-reset: ## Reset products database (DROP ALL TABLES)
	@echo "${YELLOW}WARNING: This will delete all product data!${RESET}"
	@read -p "Are you sure? [y/N] " confirm && [ "$$confirm" = "y" ] && \
		kubectl exec -n $(NAMESPACE) postgresql-products-0 -- psql -U postgres -d products -c "DROP TABLE IF EXISTS products CASCADE;"

##@ Troubleshooting

debug-cpu: ## Show CPU allocation
	@echo "${BLUE}=== CPU Allocation ===${RESET}"
	@kubectl describe node | grep -A 10 "Allocated resources:"

debug-disk: ## Show disk usage
	@echo "${BLUE}=== Disk Usage ===${RESET}"
	@df -h /
	@echo ""
	@sudo du -sh /var/lib/rancher/k3s/agent/containerd/ 2>/dev/null || true

debug-events: ## Show recent k8s events
	@echo "${BLUE}=== Recent Events ===${RESET}"
	@kubectl get events -A --sort-by='.lastTimestamp' | tail -20

debug-scale-down: ## Scale down non-essential services to free CPU
	@echo "${BLUE}Scaling down non-essential services...${RESET}"
	kubectl scale deployment -n directory openldap-openldap-bitnami --replicas=1 2>/dev/null || true
	kubectl scale deployment -n istio-system istio-ingressgateway --replicas=1 2>/dev/null || true
	kubectl scale deployment -n istio-system istiod --replicas=1 2>/dev/null || true
	kubectl scale deployment -n monitoring prometheus-grafana --replicas=1 2>/dev/null || true
	kubectl scale deployment -n monitoring prometheus-kube-prometheus-operator --replicas=1 2>/dev/null || true
	kubectl scale deployment -n monitoring prometheus-kube-state-metrics --replicas=1 2>/dev/null || true
	@echo "${GREEN}✓ Services scaled down${RESET}"

debug-cleanup-stuck: ## Force delete stuck pods
	@echo "${BLUE}Cleaning up stuck pods...${RESET}"
	kubectl delete pods -A --field-selector=status.phase=Failed --force --grace-period=0 2>/dev/null || true
	kubectl delete pods -A --field-selector=status.phase=Unknown --force --grace-period=0 2>/dev/null || true
	@echo "${GREEN}✓ Cleanup complete${RESET}"

debug-journal-clean: ## Clean systemd journal (requires sudo)
	@echo "Run: sudo journalctl --vacuum-size=100M"

debug-vault-unseal: ## Unseal Vault using stored key
	@echo "${BLUE}Unsealing Vault...${RESET}"
	@UNSEAL_KEY=$$(kubectl get secret -n vault vault-unseal -o jsonpath='{.data.unseal-key}' 2>/dev/null | base64 -d) && \
		kubectl exec -n vault vault-0 -- vault operator unseal "$$UNSEAL_KEY" || echo "Failed to unseal"

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
	@echo "Load Testing Guide:    docs/rabbitmq-load-testing.md"
	@echo "Vault Integration:     docs/vault-usage-guide.md"
