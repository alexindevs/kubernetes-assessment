#!/bin/bash
set -e

print_debug_info() {
  local namespace="$1"

  echo ""
  echo "Deployment diagnostics for namespace: $namespace"
  kubectl get all -n "$namespace" || true
  echo ""
  kubectl get events -n "$namespace" --sort-by=.lastTimestamp || true
}

# Build Docker image
echo "Building Docker image..."
docker build -t muchtodo-backend:latest .

# Create Kind cluster with custom config
echo "Creating Kind cluster..."
if kind get clusters | grep -qx muchtodo; then
  echo "Existing Kind cluster found. Recreating muchtodo cluster..."
  kind delete cluster --name muchtodo
fi
kind create cluster --name muchtodo --config kind-config.yaml

# Load image into Kind cluster
echo "Loading backend image into Kind cluster..."
kind load docker-image muchtodo-backend:latest --name muchtodo

# Install NGINX Ingress Controller
echo "Installing NGINX Ingress Controller..."
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml

# Wait for ingress controller to be ready
echo "Waiting for ingress controller..."
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=300s

# Apply Kubernetes manifests in dependency order so the backend does not start
# until MongoDB is actually available.
echo "Deploying MongoDB resources..."
kubectl apply -f kubernetes/namespace.yaml
kubectl apply -f kubernetes/mongodb/

echo "Waiting for MongoDB deployment..."
if ! kubectl rollout status deployment/mongodb -n muchtodo --timeout=500s; then
  print_debug_info muchtodo
  exit 1
fi

echo "Deploying backend resources..."
kubectl apply -f kubernetes/backend/
kubectl apply -f kubernetes/ingress.yaml

echo "Waiting for backend deployment..."
if ! kubectl rollout status deployment/backend -n muchtodo --timeout=300s; then
  print_debug_info muchtodo
  exit 1
fi

echo ""
echo "Deployment complete!"
echo ""
echo "Check status:"
kubectl get all -n muchtodo
echo ""
echo "Access the application at http://localhost/"
echo "Health check: http://localhost/health"
