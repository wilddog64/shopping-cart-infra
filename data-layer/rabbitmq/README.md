# RabbitMQ Message Queue

## Overview

This directory contains the Kubernetes manifests for deploying RabbitMQ to the `shopping-cart-data` namespace.

**Current configuration**: 1 replica (reduced from 3 for resource-constrained single-node clusters such as `t3.medium`). Scale to 3 for HA in multi-node environments.

**Status**: Stage 1 Complete - Basic Infrastructure
**Next**: Stage 2 - Vault Integration for Dynamic Credentials

## Architecture

- **Replicas**: 1 (dev/single-node); scale to 3 for HA in multi-node environments
- **Image**: `rabbitmq:3.12-management-alpine`
- **Clustering**: Automatic via Kubernetes peer discovery plugin
- **Storage**: 10Gi per node (PersistentVolumeClaim)
- **Resources**: 500m CPU / 1Gi RAM (request), 1000m CPU / 2Gi RAM (limit)

## Components

### 1. configmap.yaml
RabbitMQ configuration including:
- Kubernetes peer discovery settings
- Cluster partition handling (autoheal)
- Memory and disk thresholds
- Management plugin enablement

### 2. service.yaml
Three services:
- **rabbitmq-headless**: Headless service for StatefulSet clustering
- **rabbitmq**: ClusterIP service for AMQP connections (port 5672)
- **rabbitmq-management**: LoadBalancer service for Management UI (port 15672)

### 3. statefulset.yaml
StatefulSet with:
- 1 replica (dev/single-node); set to 3 for HA
- Init container for permission setup
- Liveness and readiness probes
- Volume claim templates for persistent storage

### 4. rbac.yaml
RBAC resources for Kubernetes peer discovery:
- **ServiceAccount**: `rabbitmq` for pod identity
- **Role**: Permissions to list/get/watch pods and endpoints
- **RoleBinding**: Connects ServiceAccount to Role

## Deployment

### Prerequisites

1. **Namespace must exist**:
   ```bash
   kubectl create namespace shopping-cart-data
   ```

2. **k3d cluster with local-path StorageClass** (default in k3d)

3. **Cluster Resources**:
   - **Single-node (default)**: 500m CPU / 1Gi RAM / 10Gi storage
   - **3-node HA**: 1.5 cores CPU / 3Gi RAM / 30Gi storage (set `replicas: 3` in statefulset.yaml)

### Deploy RabbitMQ

```bash
# Apply all manifests
kubectl apply -f data-layer/rabbitmq/

# Or apply individually
kubectl apply -f data-layer/rabbitmq/configmap.yaml
kubectl apply -f data-layer/rabbitmq/service.yaml
kubectl apply -f data-layer/rabbitmq/statefulset.yaml
```

### Verify Deployment

```bash
# Check pods
kubectl get pods -n shopping-cart-data -l app=rabbitmq

# Expected output (single-replica):
# NAME         READY   STATUS    RESTARTS   AGE
# rabbitmq-0   1/1     Running   0          2m

# Check services
kubectl get svc -n shopping-cart-data

# Check PVCs
kubectl get pvc -n shopping-cart-data
```

## Accessing RabbitMQ

### Management UI

The Management UI is exposed via LoadBalancer on port 15672.

**k3d users:**
```bash
# Get LoadBalancer IP
kubectl get svc rabbitmq-management -n shopping-cart-data

# Port forward for local access
kubectl port-forward -n shopping-cart-data svc/rabbitmq-management 15672:15672

# Open browser
open http://localhost:15672
```

**Default Credentials** (Stage 1 only):
- Username: `guest`
- Password: `guest`

**Note**: These will be replaced with Vault-generated credentials in Stage 2.

### AMQP Connections

From within the cluster:
```
amqp://rabbitmq.shopping-cart-data.svc.cluster.local:5672
```

From application pods:
```yaml
env:
  - name: RABBITMQ_HOST
    value: "rabbitmq.shopping-cart-data.svc.cluster.local"
  - name: RABBITMQ_PORT
    value: "5672"
```

## Cluster Verification

### Check Cluster Status

```bash
# From any RabbitMQ pod
kubectl exec -n shopping-cart-data rabbitmq-0 -- rabbitmqctl cluster_status

# Expected output shows 1 node (rabbitmq@rabbitmq-0) in single-replica config
```

### Test Publishing

```bash
# Create a test queue
kubectl exec -n shopping-cart-data rabbitmq-0 -- rabbitmqadmin declare queue name=test-queue durable=true

# Publish a message
kubectl exec -n shopping-cart-data rabbitmq-0 -- rabbitmqadmin publish routing_key=test-queue payload="Hello RabbitMQ"

# Consume the message
kubectl exec -n shopping-cart-data rabbitmq-0 -- rabbitmqadmin get queue=test-queue ackmode=ack_requeue_false
```

## Troubleshooting

### Pods Not Starting

```bash
# Check pod events
kubectl describe pod rabbitmq-0 -n shopping-cart-data

# Check logs
kubectl logs rabbitmq-0 -n shopping-cart-data

# Common issues:
# 1. PVC pending: Check StorageClass availability
# 2. Erlang cookie mismatch: Delete pods to regenerate
# 3. Memory limits: Adjust resources in statefulset.yaml
```

### Cluster Not Forming

```bash
# Check network connectivity between pods
kubectl exec -n shopping-cart-data rabbitmq-0 -- ping rabbitmq-1.rabbitmq-headless.shopping-cart-data.svc.cluster.local

# Check Kubernetes peer discovery
kubectl logs rabbitmq-0 -n shopping-cart-data | grep "peer_discovery"

# Force cluster formation
kubectl exec -n shopping-cart-data rabbitmq-1 -- rabbitmqctl stop_app
kubectl exec -n shopping-cart-data rabbitmq-1 -- rabbitmqctl join_cluster rabbit@rabbitmq-0.rabbitmq-headless.shopping-cart-data.svc.cluster.local
kubectl exec -n shopping-cart-data rabbitmq-1 -- rabbitmqctl start_app
```

### Management UI Not Accessible

```bash
# Check service
kubectl get svc rabbitmq-management -n shopping-cart-data

# Verify LoadBalancer IP assigned
kubectl describe svc rabbitmq-management -n shopping-cart-data

# Check plugin enabled
kubectl exec -n shopping-cart-data rabbitmq-0 -- rabbitmq-plugins list
```

## Scaling

To scale the cluster:

```bash
# Scale to 5 nodes
kubectl scale statefulset rabbitmq -n shopping-cart-data --replicas=5

# Scale down to 3 nodes
kubectl scale statefulset rabbitmq -n shopping-cart-data --replicas=3
```

**Note**: Always scale down one node at a time and verify cluster health between operations.

## Cleanup

```bash
# Delete RabbitMQ resources
kubectl delete -f data-layer/rabbitmq/

# Or delete individually
kubectl delete statefulset rabbitmq -n shopping-cart-data
kubectl delete svc rabbitmq rabbitmq-headless rabbitmq-management -n shopping-cart-data
kubectl delete configmap rabbitmq-config -n shopping-cart-data

# Delete PVCs (WARNING: This deletes all data)
kubectl delete pvc -l app=rabbitmq -n shopping-cart-data
```

## Stage 2 Preview: Vault Integration

In Stage 2, we will:
1. Enable RabbitMQ secrets engine in Vault
2. Configure dynamic user generation
3. Replace hardcoded guest credentials
4. Update StatefulSet to use Vault-generated credentials
5. Implement automatic credential rotation

See [Message Queue Implementation Plan](../../docs/plans/message-queue-implementation.md) for details.

## Monitoring

**Metrics to Monitor:**
- Queue depth
- Message rate (publish/consume)
- Consumer lag
- Memory usage
- Disk space
- Connection count

**Prometheus metrics endpoint:**
```
http://rabbitmq-management.shopping-cart-data.svc.cluster.local:15672/api/metrics
```

This will be fully configured in Stage 4 (Monitoring & Production Readiness).

## References

- [RabbitMQ Official Documentation](https://www.rabbitmq.com/documentation.html)
- [RabbitMQ Kubernetes Peer Discovery](https://www.rabbitmq.com/cluster-formation.html#peer-discovery-k8s)
- [RabbitMQ Clustering Guide](https://www.rabbitmq.com/clustering.html)
- [Message Queue Implementation Plan](../../docs/plans/message-queue-implementation.md)
- [Client Library Design](../../docs/rabbitmq-client-library-design.md)
