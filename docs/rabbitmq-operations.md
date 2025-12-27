# RabbitMQ Operations Guide

This guide covers operational procedures for the RabbitMQ cluster in the shopping-cart platform.

## Table of Contents

1. [Cluster Overview](#cluster-overview)
2. [Common Operations](#common-operations)
3. [Monitoring & Alerting](#monitoring--alerting)
4. [Troubleshooting](#troubleshooting)
5. [Scaling](#scaling)
6. [Backup & Recovery](#backup--recovery)
7. [Performance Tuning](#performance-tuning)

---

## Cluster Overview

### Architecture

```
┌─────────────────────────────────────────────────────┐
│              RabbitMQ Cluster (3 nodes)             │
├─────────────────────────────────────────────────────┤
│  rabbitmq-0    rabbitmq-1    rabbitmq-2            │
│  (primary)     (replica)     (replica)             │
│                                                     │
│  Port 5672  - AMQP                                 │
│  Port 15672 - Management UI                        │
│  Port 15692 - Prometheus metrics                   │
│  Port 25672 - Clustering                           │
└─────────────────────────────────────────────────────┘
```

### Access Points

| Service | Port | Purpose |
|---------|------|---------|
| `rabbitmq.shopping-cart-data` | 5672 | AMQP connections |
| `rabbitmq-management.shopping-cart-data` | 15672 | Management UI |
| `rabbitmq-headless.shopping-cart-data` | 15692 | Prometheus metrics |

### Credentials

All credentials are managed through HashiCorp Vault:

```bash
# Get dynamic credentials
vault read rabbitmq/creds/order-publisher

# Available roles:
# - order-publisher: Write to order queues
# - order-consumer: Read from order queues
# - event-publisher: Publish to exchanges
# - admin: Full access
```

---

## Common Operations

### Check Cluster Status

```bash
# View cluster status
kubectl exec -n shopping-cart-data rabbitmq-0 -- rabbitmqctl cluster_status

# Check node health
kubectl exec -n shopping-cart-data rabbitmq-0 -- rabbitmqctl node_health_check

# List all nodes
kubectl exec -n shopping-cart-data rabbitmq-0 -- rabbitmqctl cluster_status --formatter json | jq '.running_nodes'
```

### Queue Management

```bash
# List all queues
kubectl exec -n shopping-cart-data rabbitmq-0 -- rabbitmqctl list_queues name messages consumers

# Get queue details
kubectl exec -n shopping-cart-data rabbitmq-0 -- rabbitmqctl list_queues name messages_ready messages_unacknowledged consumers memory

# Purge a queue (WARNING: deletes all messages)
kubectl exec -n shopping-cart-data rabbitmq-0 -- rabbitmqctl purge_queue <queue_name>

# Delete a queue
kubectl exec -n shopping-cart-data rabbitmq-0 -- rabbitmqctl delete_queue <queue_name>
```

### Exchange Management

```bash
# List exchanges
kubectl exec -n shopping-cart-data rabbitmq-0 -- rabbitmqctl list_exchanges name type

# List bindings
kubectl exec -n shopping-cart-data rabbitmq-0 -- rabbitmqctl list_bindings source_name destination_name routing_key
```

### Connection Management

```bash
# List connections
kubectl exec -n shopping-cart-data rabbitmq-0 -- rabbitmqctl list_connections user peer_host state

# Close a specific connection
kubectl exec -n shopping-cart-data rabbitmq-0 -- rabbitmqctl close_connection "<connection_pid>" "Closing for maintenance"

# Close all connections from a specific user
kubectl exec -n shopping-cart-data rabbitmq-0 -- rabbitmqctl close_all_connections "Maintenance window"
```

### User Management

```bash
# List users (Vault-managed users will appear here)
kubectl exec -n shopping-cart-data rabbitmq-0 -- rabbitmqctl list_users

# List user permissions
kubectl exec -n shopping-cart-data rabbitmq-0 -- rabbitmqctl list_user_permissions <username>
```

### Access Management UI

```bash
# Port-forward to access locally
kubectl port-forward -n shopping-cart-data svc/rabbitmq-management 15672:15672

# Open in browser: http://localhost:15672
# Credentials: Get from Vault (admin role)
```

---

## Monitoring & Alerting

### Key Metrics to Watch

| Metric | Warning Threshold | Critical Threshold |
|--------|-------------------|-------------------|
| Queue depth | > 10,000 | > 50,000 |
| Memory usage | > 80% | > 95% |
| Disk space | < 2x limit | < 1x limit |
| File descriptors | > 80% | > 95% |
| Unacked messages | > 1,000 | > 5,000 |

### Grafana Dashboard

Access the RabbitMQ dashboard:
1. Open Grafana: `kubectl port-forward -n monitoring svc/grafana 3000:3000`
2. Navigate to Dashboards → RabbitMQ Overview

### Prometheus Queries

```promql
# Message publish rate
rate(rabbitmq_channel_messages_published_total[5m])

# Queue depth across all queues
sum(rabbitmq_queue_messages_ready)

# Consumer count by queue
rabbitmq_queue_consumers

# Memory usage percentage
rabbitmq_process_resident_memory_bytes / rabbitmq_resident_memory_limit_bytes

# Connection count
rabbitmq_connections
```

### Alert Response

| Alert | Immediate Actions |
|-------|-------------------|
| RabbitMQDown | Check pod status, node health, restart if needed |
| RabbitMQQueueDepthHigh | Scale consumers, check consumer health |
| RabbitMQMemoryHigh | Purge unused queues, increase memory limit |
| RabbitMQNoConsumers | Deploy/restart consumer pods |
| RabbitMQDLQNotEmpty | Investigate failed messages, reprocess or discard |

---

## Troubleshooting

### Node Won't Start

```bash
# Check pod events
kubectl describe pod -n shopping-cart-data rabbitmq-0

# Check logs
kubectl logs -n shopping-cart-data rabbitmq-0

# Force reset (CAUTION: data loss possible)
kubectl exec -n shopping-cart-data rabbitmq-0 -- rabbitmqctl force_reset
kubectl exec -n shopping-cart-data rabbitmq-0 -- rabbitmqctl start_app
```

### Cluster Partition

```bash
# Check for partitions
kubectl exec -n shopping-cart-data rabbitmq-0 -- rabbitmqctl cluster_status | grep partitions

# If partitions exist, restart minority partition nodes
kubectl delete pod -n shopping-cart-data rabbitmq-2

# Force sync if needed (on minority node after restart)
kubectl exec -n shopping-cart-data rabbitmq-2 -- rabbitmqctl stop_app
kubectl exec -n shopping-cart-data rabbitmq-2 -- rabbitmqctl reset
kubectl exec -n shopping-cart-data rabbitmq-2 -- rabbitmqctl join_cluster rabbit@rabbitmq-0.rabbitmq-headless.shopping-cart-data.svc.cluster.local
kubectl exec -n shopping-cart-data rabbitmq-2 -- rabbitmqctl start_app
```

### High Memory Usage

```bash
# Check memory breakdown
kubectl exec -n shopping-cart-data rabbitmq-0 -- rabbitmqctl status | grep -A20 "Memory"

# Find large queues
kubectl exec -n shopping-cart-data rabbitmq-0 -- rabbitmqctl list_queues name memory --sort memory --descending | head -10

# Force GC (temporary relief)
kubectl exec -n shopping-cart-data rabbitmq-0 -- rabbitmqctl eval "garbage_collect()."
```

### Messages Stuck in Queue

```bash
# Check consumer status
kubectl exec -n shopping-cart-data rabbitmq-0 -- rabbitmqctl list_consumers queue_name channel_pid consumer_tag ack_required

# Check for blocked connections
kubectl exec -n shopping-cart-data rabbitmq-0 -- rabbitmqctl list_connections state | grep -c blocked

# Check prefetch count
kubectl exec -n shopping-cart-data rabbitmq-0 -- rabbitmqctl list_channels prefetch_count
```

### Slow Publishing

```bash
# Check for flow control
kubectl exec -n shopping-cart-data rabbitmq-0 -- rabbitmqctl list_connections state | grep -c flow

# Check disk I/O
kubectl exec -n shopping-cart-data rabbitmq-0 -- rabbitmqctl status | grep disk

# Verify confirms are being processed
kubectl exec -n shopping-cart-data rabbitmq-0 -- rabbitmqctl list_channels confirm
```

---

## Scaling

### Adding Nodes

```bash
# Update StatefulSet replicas
kubectl scale statefulset -n shopping-cart-data rabbitmq --replicas=5

# Verify new nodes joined cluster
kubectl exec -n shopping-cart-data rabbitmq-0 -- rabbitmqctl cluster_status
```

### Removing Nodes

```bash
# Gracefully remove node
kubectl exec -n shopping-cart-data rabbitmq-4 -- rabbitmqctl stop_app
kubectl exec -n shopping-cart-data rabbitmq-0 -- rabbitmqctl forget_cluster_node rabbit@rabbitmq-4.rabbitmq-headless.shopping-cart-data.svc.cluster.local

# Scale down
kubectl scale statefulset -n shopping-cart-data rabbitmq --replicas=3
```

### Scaling Consumers

Consumer scaling is handled by application deployments, not RabbitMQ:

```bash
# Scale consumer deployment
kubectl scale deployment -n shopping-cart-apps order-consumer --replicas=5
```

---

## Backup & Recovery

### Definitions Export (Recommended)

```bash
# Export definitions (exchanges, queues, bindings, users)
kubectl exec -n shopping-cart-data rabbitmq-0 -- \
  rabbitmqctl export_definitions /tmp/definitions.json

# Copy to local machine
kubectl cp shopping-cart-data/rabbitmq-0:/tmp/definitions.json ./rabbitmq-definitions.json
```

### Definitions Import

```bash
# Copy definitions to pod
kubectl cp ./rabbitmq-definitions.json shopping-cart-data/rabbitmq-0:/tmp/definitions.json

# Import definitions
kubectl exec -n shopping-cart-data rabbitmq-0 -- \
  rabbitmqctl import_definitions /tmp/definitions.json
```

### Message Backup

For critical messages, use the Shovel plugin or application-level backup:

```bash
# Enable shovel plugin if needed
kubectl exec -n shopping-cart-data rabbitmq-0 -- rabbitmq-plugins enable rabbitmq_shovel

# Configure shovel to backup queue (via management API)
```

### Disaster Recovery

1. **Full cluster loss**: Restore from definitions export, messages are lost
2. **Single node loss**: Automatic recovery if quorum maintained
3. **Minority partition**: Reset minority nodes, rejoin cluster

---

## Performance Tuning

### Recommended Settings

```ini
# rabbitmq.conf optimizations
# Memory
vm_memory_high_watermark.relative = 0.6
vm_memory_high_watermark_paging_ratio = 0.75

# Disk
disk_free_limit.absolute = 2GB

# Networking
tcp_listen_options.backlog = 128
tcp_listen_options.nodelay = true
tcp_listen_options.linger.on = true
tcp_listen_options.linger.timeout = 0

# Queues
queue_index_embed_msgs_below = 4096
```

### Consumer Tuning

| Setting | Recommended | Description |
|---------|-------------|-------------|
| Prefetch count | 10-50 | Messages buffered per consumer |
| Consumer concurrency | 1-5 per pod | Parallel message processing |
| Ack mode | Manual | Ensure message durability |

### Publisher Tuning

| Setting | Recommended | Description |
|---------|-------------|-------------|
| Publisher confirms | Enabled | Ensure message delivery |
| Batch size | 100-500 | Messages per batch publish |
| Connection pooling | 5-10 | Connections per publisher |

### Queue Design

- Use lazy queues for large backlogs (lower memory, disk-based)
- Use quorum queues for high availability
- Set appropriate TTL for transient messages
- Configure dead-letter exchanges for failed messages

```bash
# Check queue type
kubectl exec -n shopping-cart-data rabbitmq-0 -- rabbitmqctl list_queues name type arguments

# Convert to lazy queue (via policy)
kubectl exec -n shopping-cart-data rabbitmq-0 -- rabbitmqctl set_policy lazy-queues \
  "^(orders|events)\." '{"queue-mode":"lazy"}' --apply-to queues
```

---

## Emergency Procedures

### Stop All Traffic

```bash
# Block new connections
kubectl exec -n shopping-cart-data rabbitmq-0 -- rabbitmqctl close_all_connections "Emergency maintenance"

# Pause publishing (application-level)
# Scale down publisher deployments
```

### Force Cluster Reset

**WARNING: This will lose all messages**

```bash
# Stop all nodes
kubectl scale statefulset -n shopping-cart-data rabbitmq --replicas=0

# Delete PVCs (optional, for complete reset)
kubectl delete pvc -n shopping-cart-data -l app=rabbitmq

# Restart cluster
kubectl scale statefulset -n shopping-cart-data rabbitmq --replicas=3
```

### Rollback Deployment

```bash
# Check rollout history
kubectl rollout history statefulset -n shopping-cart-data rabbitmq

# Rollback to previous version
kubectl rollout undo statefulset -n shopping-cart-data rabbitmq

# Rollback to specific revision
kubectl rollout undo statefulset -n shopping-cart-data rabbitmq --to-revision=2
```

---

## Contact & Escalation

| Level | Contact | When |
|-------|---------|------|
| L1 | On-call engineer | Initial response |
| L2 | Platform team | Cluster issues, scaling |
| L3 | Vendor support | Critical bugs, data recovery |

---

**Last Updated**: 2025-12-26
**Owner**: Platform Team
