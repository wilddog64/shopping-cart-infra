#!/bin/bash
set -e

echo "=== RabbitMQ Test Suite ==="
echo

# Test 1: Create a test queue
echo "1. Creating test queue 'hello'..."
kubectl exec -n shopping-cart-data rabbitmq-0 -- rabbitmqadmin declare queue name=hello durable=true
echo "✓ Queue created"
echo

# Test 2: Publish a message
echo "2. Publishing test message..."
kubectl exec -n shopping-cart-data rabbitmq-0 -- rabbitmqadmin publish routing_key=hello payload="Hello from RabbitMQ test!"
echo "✓ Message published"
echo

# Test 3: Check queue stats
echo "3. Checking queue statistics..."
kubectl exec -n shopping-cart-data rabbitmq-0 -- rabbitmqadmin list queues name messages
echo

# Test 4: Consume the message
echo "4. Consuming message from queue..."
kubectl exec -n shopping-cart-data rabbitmq-0 -- rabbitmqadmin get queue=hello ackmode=ack_requeue_false
echo "✓ Message consumed"
echo

# Test 5: List exchanges
echo "5. Listing exchanges..."
kubectl exec -n shopping-cart-data rabbitmq-0 -- rabbitmqadmin list exchanges name type
echo

# Test 6: Check connections
echo "6. Checking active connections..."
kubectl exec -n shopping-cart-data rabbitmq-0 -- rabbitmqctl list_connections
echo

# Test 7: Memory and disk usage
echo "7. Checking resource usage..."
kubectl exec -n shopping-cart-data rabbitmq-0 -- rabbitmqctl status | grep -A 5 "Memory"
echo

echo "=== All tests passed! ==="
