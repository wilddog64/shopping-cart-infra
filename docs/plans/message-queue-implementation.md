# Message Queue Implementation Plan

## Executive Summary

Add RabbitMQ message queue infrastructure to enable asynchronous order processing, event-driven architecture, and improved service decoupling for the shopping cart platform.

**Timeline**: 4 stages
**Namespace**: `shopping-cart-data` (infrastructure component)
**Technology**: RabbitMQ 3.12+ with management plugin
**Integration**: Vault for credential management, Istio for service mesh

## Architecture Overview

### Current State

```
User Request → API Gateway → Service (sync) → Database
                                  ↓
                            Response (wait for all operations)
```

**Issues:**
- Slow response times (waiting for email, payment, etc.)
- Tight coupling between services
- No retry mechanism for failures
- Difficult to scale individual operations

### Target State

```
User Request → API Gateway → Service → Queue → Response (immediate)
                                         ↓
                          [Async Workers] → Database
                          ├─ Payment Service
                          ├─ Email Service
                          ├─ Inventory Service
                          └─ Analytics Service
```

**Benefits:**
- Fast user responses (sub-100ms)
- Automatic retry on failures
- Independent service scaling
- Better fault isolation
- Event-driven architecture

## Technology Selection

### RabbitMQ (Recommended)

**Pros:**
- Battle-tested for e-commerce workloads
- AMQP protocol (standardized messaging)
- Dead letter queues (DLQ) for failed messages
- Priority queues (rush orders, VIP customers)
- Message persistence and durability
- Excellent Kubernetes support
- Management UI for debugging
- Plugin ecosystem (Vault integration)

**Cons:**
- Heavier than NATS (still lightweight)
- Requires more configuration than Redis Streams

**Why RabbitMQ over alternatives:**
- **vs Redis Streams**: More robust, better failure handling, proper message queue semantics
- **vs NATS**: Better for guaranteed delivery, established patterns
- **vs Kafka**: Simpler operations, lower resource usage, sufficient for e-commerce scale

## Infrastructure Design

### Deployment Architecture

```
shopping-cart-data namespace:
├─ PostgreSQL StatefulSet (existing)
├─ Redis StatefulSet (existing)
└─ RabbitMQ StatefulSet (new)
   ├─ rabbitmq-0 (primary)
   ├─ rabbitmq-1 (replica)
   └─ rabbitmq-2 (replica)

Vault Integration:
├─ RabbitMQ secrets engine enabled
├─ Dynamic credential generation
└─ Role-based access control

Istio Integration:
├─ Service mesh for mTLS
├─ Traffic management
└─ Observability (metrics, tracing)
```

### Message Flow Patterns

#### 1. Order Processing (Work Queue Pattern)

```
Order Service → [orders.created] → RabbitMQ Queue
                                      ↓ (round-robin)
                          ┌───────────┼───────────┐
                          ↓           ↓           ↓
                    Payment-1   Payment-2   Payment-3
                          ↓
                    [payment.completed]
                          ↓
                    Email Service
```

#### 2. Event Broadcasting (Pub/Sub Pattern)

```
Inventory Service → [stock.updated] → RabbitMQ Exchange
                                            ↓
                        ┌──────────────┬────┴────┬──────────────┐
                        ↓              ↓         ↓              ↓
                  Cache Service  Search Index  Analytics  Notification
```

#### 3. Dead Letter Queue (Error Handling)

```
Order Queue → Processing Fails (3x retry) → DLQ
                                             ↓
                                    [Manual Review]
                                    [Alert Operator]
```

### Resource Requirements

**RabbitMQ StatefulSet:**
- **CPU**: 500m per replica (1.5 CPU total for 3 replicas)
- **Memory**: 1Gi per replica (3Gi total)
- **Storage**: 10Gi per replica (persistent volumes)
- **Network**: 5672 (AMQP), 15672 (Management UI)

**Scaling Considerations:**
- Start with 3 replicas for HA
- Scale to 5+ replicas for high traffic
- Monitor queue depth and consumer lag

## Implementation Stages

### Stage 1: Infrastructure Setup

**Goal**: Deploy RabbitMQ cluster with basic configuration

**Tasks:**
1. Create RabbitMQ deployment manifests
   - StatefulSet with 3 replicas
   - Headless service for clustering
   - LoadBalancer service for external access
   - PersistentVolumeClaims for data
   - ConfigMap for RabbitMQ configuration

2. Deploy RabbitMQ to shopping-cart-data namespace
   ```bash
   kubectl apply -f data-layer/rabbitmq/
   ```

3. Verify cluster formation
   ```bash
   kubectl exec -n shopping-cart-data rabbitmq-0 -- rabbitmqctl cluster_status
   ```

4. Access management UI
   ```bash
   kubectl port-forward -n shopping-cart-data svc/rabbitmq-management 15672:15672
   # Open http://localhost:15672 (guest/guest)
   ```

**Deliverables:**
- `data-layer/rabbitmq/statefulset.yaml`
- `data-layer/rabbitmq/service.yaml`
- `data-layer/rabbitmq/configmap.yaml`
- `data-layer/rabbitmq/pvc.yaml`

**Success Criteria:**
- ✅ 3 RabbitMQ pods running
- ✅ Cluster formed successfully
- ✅ Management UI accessible
- ✅ Basic queue creation works

**Estimated Time**: 2-3 hours

---

### Stage 2: Vault Integration

**Goal**: Secure credential management with dynamic RabbitMQ users

**Tasks:**
1. Enable RabbitMQ secrets engine in Vault
   ```bash
   vault secrets enable rabbitmq
   ```

2. Configure Vault-RabbitMQ connection
   ```bash
   vault write rabbitmq/config/connection \
     connection_uri="http://rabbitmq.shopping-cart-data.svc.cluster.local:15672" \
     username="admin" \
     password="<from-secret>"
   ```

3. Create Vault roles for different access patterns
   - `order-publisher`: Write to order queues
   - `order-consumer`: Read from order queues
   - `event-publisher`: Publish to exchange
   - `admin`: Full access for operations

4. Test dynamic credential generation
   ```bash
   vault read rabbitmq/creds/order-publisher
   ```

5. Update RabbitMQ StatefulSet to use Vault credentials
   - Add init container to fetch admin credentials
   - Configure Vault agent sidecar (optional)

6. Create test script to verify Vault integration
   ```bash
   bin/test-rabbitmq-vault.sh
   ```

**Deliverables:**
- `bin/configure-vault-rabbitmq.sh`
- `bin/test-rabbitmq-vault.sh`
- `docs/rabbitmq-vault-integration.md`
- Updated `bin/deploy-infra.sh` with RabbitMQ + Vault

**Success Criteria:**
- ✅ Vault generates RabbitMQ credentials
- ✅ Credentials work for publishing/consuming
- ✅ Credentials expire after TTL (1 hour default)
- ✅ Old credentials revoked properly

**Estimated Time**: 3-4 hours

---

### Stage 3: Application Integration

**Goal**: Enable services to publish and consume messages

**Tasks:**
1. Create message schemas and event definitions
   ```typescript
   // events/order-events.ts
   interface OrderCreatedEvent {
     orderId: string;
     userId: string;
     items: CartItem[];
     totalAmount: number;
     timestamp: string;
   }
   ```

2. Implement publisher library/wrapper
   ```typescript
   // lib/rabbitmq-publisher.ts
   class OrderEventPublisher {
     async publishOrderCreated(order: Order): Promise<void>
   }
   ```

3. Implement consumer library/wrapper
   ```typescript
   // lib/rabbitmq-consumer.ts
   class OrderEventConsumer {
     async consumeOrderCreated(handler: (event: OrderCreatedEvent) => Promise<void>)
   }
   ```

4. Create example integrations:
   - Order service: Publish `order.created` event
   - Payment service: Consume `order.created`, publish `payment.completed`
   - Email service: Consume `order.created`, send confirmation email
   - Inventory service: Consume `order.created`, reserve stock

5. Add health checks for RabbitMQ connectivity
   ```yaml
   livenessProbe:
     exec:
       command: ["rabbitmq-diagnostics", "ping"]
   ```

6. Configure retry policies and DLQ
   - Max retries: 3
   - Backoff: exponential (1s, 2s, 4s)
   - DLQ after max retries

**Deliverables:**
- `examples/order-service/rabbitmq-integration.ts`
- `examples/payment-service/rabbitmq-integration.ts`
- `examples/email-service/rabbitmq-integration.ts`
- Event schema definitions
- Client libraries (publisher/consumer)

**Success Criteria:**
- ✅ Order service publishes events successfully
- ✅ Multiple consumers receive events
- ✅ Failed messages route to DLQ
- ✅ Retry logic works as expected

**Estimated Time**: 6-8 hours (depends on application complexity)

---

### Stage 4: Monitoring & Production Readiness

**Goal**: Observability, alerting, and operational excellence

**Tasks:**
1. Deploy RabbitMQ Prometheus exporter
   ```yaml
   - name: prometheus-rabbitmq-exporter
     image: kbudde/rabbitmq-exporter:latest
   ```

2. Create Grafana dashboards
   - Queue depth over time
   - Message rate (publish/consume)
   - Consumer lag
   - Memory/CPU usage
   - Connection count

3. Set up alerts
   - Queue depth > 10000 messages
   - Consumer lag > 5 minutes
   - Node down
   - Disk space < 20%

4. Document operational procedures
   - Adding/removing nodes
   - Backup and restore
   - Disaster recovery
   - Scaling guidelines

5. Create load testing scenarios
   - Burst traffic: 1000 orders/second
   - Sustained load: 100 orders/second
   - Consumer failure scenarios

6. Performance tuning
   - Prefetch count optimization
   - Connection pooling
   - Memory high watermark
   - Disk space management

**Deliverables:**
- `monitoring/rabbitmq-dashboard.json` (Grafana)
- `monitoring/rabbitmq-alerts.yaml` (Prometheus)
- `docs/rabbitmq-operations.md`
- Load test scripts
- Performance tuning guide

**Success Criteria:**
- ✅ All metrics visible in Grafana
- ✅ Alerts firing correctly
- ✅ Load tests pass at target throughput
- ✅ Documented runbooks for common issues

**Estimated Time**: 4-6 hours

---

## Directory Structure

```
shopping-cart-infra/
├─ data-layer/
│  ├─ postgresql/          (existing)
│  ├─ redis/               (existing)
│  └─ rabbitmq/            (new)
│     ├─ statefulset.yaml
│     ├─ service.yaml
│     ├─ configmap.yaml
│     ├─ pvc.yaml
│     └─ README.md
│
├─ bin/
│  ├─ deploy-infra.sh                    (update)
│  ├─ configure-vault-rabbitmq.sh        (new)
│  ├─ test-rabbitmq-integration.sh       (new)
│  └─ test-rabbitmq-vault.sh             (new)
│
├─ docs/
│  ├─ plans/
│  │  └─ message-queue-implementation.md (this file)
│  ├─ rabbitmq-vault-integration.md      (new)
│  ├─ rabbitmq-operations.md             (new)
│  └─ rabbitmq-usage-guide.md            (new)
│
├─ monitoring/
│  ├─ rabbitmq-dashboard.json            (new)
│  └─ rabbitmq-alerts.yaml               (new)
│
└─ examples/
   ├─ order-service/
   │  └─ rabbitmq-integration.ts         (new)
   ├─ payment-service/
   │  └─ rabbitmq-integration.ts         (new)
   └─ events/
      └─ schemas.ts                      (new)
```

## Queue Design

### Queues and Exchanges

```
Exchange: orders.events (topic)
├─ Routing Key: order.created
│  └─ Queue: orders.created
│     ├─ Consumer: payment-service
│     ├─ Consumer: email-service
│     └─ Consumer: inventory-service
│
├─ Routing Key: order.completed
│  └─ Queue: orders.completed
│     ├─ Consumer: analytics-service
│     └─ Consumer: notification-service
│
└─ Routing Key: order.cancelled
   └─ Queue: orders.cancelled
      ├─ Consumer: refund-service
      └─ Consumer: inventory-service

Exchange: inventory.events (topic)
├─ Routing Key: stock.updated
│  └─ Queue: stock.updates
│     ├─ Consumer: cache-invalidator
│     ├─ Consumer: search-indexer
│     └─ Consumer: notification-service
│
└─ Routing Key: stock.low
   └─ Queue: stock.alerts
      └─ Consumer: procurement-service

Dead Letter Exchange: dlx
└─ Queue: dead-letters
   └─ Consumer: error-handler
```

### Naming Conventions

**Exchanges:**
- Format: `<domain>.events`
- Examples: `orders.events`, `inventory.events`, `users.events`

**Queues:**
- Format: `<domain>.<action>`
- Examples: `orders.created`, `stock.updated`, `users.registered`

**Routing Keys:**
- Format: `<domain>.<event>`
- Examples: `order.created`, `stock.low`, `user.registered`

## Security Considerations

### Authentication & Authorization

1. **Vault-managed credentials**
   - Dynamic user generation
   - Time-limited access (1-hour TTL)
   - Automatic credential rotation

2. **TLS/mTLS**
   - Enable TLS for AMQP connections
   - Use Istio service mesh for mTLS
   - Certificate rotation via Vault PKI

3. **Access Control**
   - Virtual hosts for tenant isolation
   - Tag-based permissions
   - Read/Write separation

### Network Security

```
Istio Service Mesh:
├─ mTLS between services
├─ AuthorizationPolicy for RabbitMQ
└─ Traffic encryption in transit

NetworkPolicy:
├─ Allow: shopping-cart-apps → rabbitmq:5672
├─ Allow: monitoring → rabbitmq:15672
└─ Deny: all other traffic
```

## Cost Estimation

### Resource Costs

**Development/Testing:**
- 3 RabbitMQ pods × (500m CPU + 1Gi RAM) = 1.5 CPU, 3Gi RAM
- Storage: 3 × 10Gi = 30Gi
- **Monthly cost**: ~$50-70 (cloud provider dependent)

**Production:**
- 5 RabbitMQ pods × (1 CPU + 2Gi RAM) = 5 CPU, 10Gi RAM
- Storage: 5 × 50Gi = 250Gi
- **Monthly cost**: ~$200-300 (cloud provider dependent)

## Testing Strategy

### Unit Tests
- Message serialization/deserialization
- Event schema validation
- Publisher error handling
- Consumer retry logic

### Integration Tests
1. **End-to-end message flow**
   ```bash
   bin/test-rabbitmq-integration.sh
   ```
   - Publish message → Verify consumption
   - DLQ routing on failure
   - Credential rotation during operation

2. **Vault integration**
   ```bash
   bin/test-rabbitmq-vault.sh
   ```
   - Dynamic credential generation
   - Permission validation
   - Credential expiration

3. **High availability**
   - Node failure scenarios
   - Network partition recovery
   - Queue mirroring

### Load Tests
```bash
# Scenario 1: Burst traffic
wrk -t4 -c100 -d30s --script=order-burst.lua http://api/orders

# Scenario 2: Sustained load
wrk -t2 -c50 -d600s --script=order-sustained.lua http://api/orders

# Monitor queue depth
watch -n1 'rabbitmqadmin list queues name messages'
```

## Migration Strategy

### Phased Rollout

**Phase 1: Non-critical workflows (Week 1)**
- Email notifications
- Analytics events
- Log aggregation

**Phase 2: Order processing (Week 2-3)**
- Order confirmation emails
- Inventory reservations (with fallback to sync)
- Payment processing (shadow mode)

**Phase 3: Full migration (Week 4+)**
- All async operations through queue
- Remove sync fallbacks
- Decommission old integration points

### Rollback Plan

If issues arise:
1. Switch services back to synchronous calls
2. Drain queues gracefully
3. Preserve messages in DLQ
4. Investigate root cause
5. Fix and redeploy

## Success Metrics

### Performance Metrics
- **Response time**: Order creation < 100ms (vs 500ms+ synchronous)
- **Throughput**: Handle 1000 orders/second
- **Message latency**: 95th percentile < 50ms

### Reliability Metrics
- **Availability**: 99.9% uptime
- **Message loss**: 0% (durability enabled)
- **Consumer success rate**: > 99.5%

### Business Metrics
- **User satisfaction**: Faster checkout experience
- **Order completion rate**: Increased by 5-10%
- **Error recovery**: Automatic retry reduces support tickets

## References

### External Documentation
- [RabbitMQ Official Docs](https://www.rabbitmq.com/documentation.html)
- [RabbitMQ Kubernetes Operator](https://www.rabbitmq.com/kubernetes/operator/operator-overview.html)
- [Vault RabbitMQ Secrets Engine](https://developer.hashicorp.com/vault/docs/secrets/rabbitmq)
- [AMQP 0-9-1 Protocol](https://www.rabbitmq.com/tutorials/amqp-concepts.html)

### Internal Documentation
- [Vault Usage Guide](../vault-usage-guide.md)
- [Vault Password Rotation](../vault-password-rotation.md)
- [Infrastructure Deployment](../../README.md)

## Next Steps

1. **Review this plan** with team
2. **Start Stage 1**: Infrastructure setup (2-3 hours)
3. **Validate** with simple pub/sub test
4. **Proceed to Stage 2**: Vault integration
5. **Iterate** based on learnings

---

**Document Status**: Draft
**Last Updated**: 2025-01-08
**Owner**: Platform Team
**Reviewers**: TBD
