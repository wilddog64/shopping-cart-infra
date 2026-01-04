#!/usr/bin/env bash
# Build and deploy all shopping cart services to k3s
# Usage: ./bin/build-and-deploy.sh [all|order|product-catalog|basket]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

# Java settings
export JAVA_HOME="${JAVA_HOME:-/home/linuxbrew/.linuxbrew/opt/openjdk@21}"
export PATH="$JAVA_HOME/bin:/home/linuxbrew/.linuxbrew/bin:$PATH"
export MAVEN_OPTS="-Xmx1024m"

# Container CLI
CONTAINER_CLI="${CONTAINER_CLI:-podman}"

echo "==> Build Configuration"
echo "    REPO_ROOT: $REPO_ROOT"
echo "    JAVA_HOME: $JAVA_HOME"
echo "    Container CLI: $CONTAINER_CLI"
echo ""

build_rabbitmq_client_java() {
    echo "==> Building rabbitmq-client-java..."
    cd "$REPO_ROOT/rabbitmq-client-java"

    /home/linuxbrew/.linuxbrew/bin/mvn clean install -DskipTests -q
    echo "    ✓ rabbitmq-client-java installed to local Maven repo"
}

build_order_service() {
    echo "==> Building order-service..."
    cd "$REPO_ROOT/shopping-cart-order"

    # Build JAR
    /home/linuxbrew/.linuxbrew/bin/mvn clean package -DskipTests -q
    echo "    ✓ JAR built"

    # Build container image
    $CONTAINER_CLI build -t shopping-cart-order:latest \
        --build-arg MAVEN_SKIP=true \
        -f Dockerfile.prebuilt . 2>/dev/null || \
    $CONTAINER_CLI build -t shopping-cart-order:latest .
    echo "    ✓ Container image built"
}

build_product_catalog() {
    echo "==> Building product-catalog..."
    cd "$REPO_ROOT/shopping-cart-product-catalog"

    # Build container image
    $CONTAINER_CLI build -t shopping-cart-product-catalog:latest .
    echo "    ✓ Container image built"
}

build_basket_service() {
    echo "==> Building basket-service..."
    cd "$REPO_ROOT/shopping-cart-basket"

    # Build container image
    $CONTAINER_CLI build -t shopping-cart-basket:latest .
    echo "    ✓ Container image built"
}

import_to_k3s() {
    local image="$1"
    echo "==> Importing $image to k3s..."

    # Save image to tar
    $CONTAINER_CLI save "$image" -o "/tmp/${image//[:\/]/_}.tar"

    # Import to k3s
    sudo k3s ctr images import "/tmp/${image//[:\/]/_}.tar"

    # Cleanup
    rm -f "/tmp/${image//[:\/]/_}.tar"
    echo "    ✓ Imported to k3s"
}

deploy_to_k3s() {
    local service="$1"
    local path="$REPO_ROOT/shopping-cart-${service}/k8s/base"

    echo "==> Deploying $service to k3s..."
    kubectl apply -k "$path"
    echo "    ✓ Deployed"
}

case "${1:-all}" in
    rabbitmq-client)
        build_rabbitmq_client_java
        ;;
    order)
        build_rabbitmq_client_java
        build_order_service
        import_to_k3s "shopping-cart-order:latest"
        deploy_to_k3s "order"
        ;;
    product-catalog)
        build_product_catalog
        import_to_k3s "shopping-cart-product-catalog:latest"
        deploy_to_k3s "product-catalog"
        ;;
    basket)
        build_basket_service
        import_to_k3s "shopping-cart-basket:latest"
        deploy_to_k3s "basket"
        ;;
    all)
        echo "==> Building all services..."
        echo ""

        # Build dependencies first
        build_rabbitmq_client_java

        # Build all services
        build_order_service
        build_product_catalog
        build_basket_service

        # Import all images to k3s
        import_to_k3s "shopping-cart-order:latest"
        import_to_k3s "shopping-cart-product-catalog:latest"
        import_to_k3s "shopping-cart-basket:latest"

        # Deploy all services
        deploy_to_k3s "order"
        deploy_to_k3s "product-catalog"
        deploy_to_k3s "basket"

        echo ""
        echo "==> All services deployed!"
        echo ""
        echo "Check status with:"
        echo "  kubectl get pods -n shopping-cart-apps"
        ;;
    *)
        echo "Usage: $0 [all|rabbitmq-client|order|product-catalog|basket]"
        exit 1
        ;;
esac
