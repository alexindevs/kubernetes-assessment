#!/bin/bash
set -e

echo "Deleting Kubernetes resources..."
kubectl delete namespace muchtodo --ignore-not-found=true

echo "Deleting Kind cluster..."
kind delete cluster --name muchtodo

echo "Cleanup complete!"
