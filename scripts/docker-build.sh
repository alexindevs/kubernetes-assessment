#!/bin/bash
set -e

echo "Building Docker image..."
docker build -t muchtodo-backend:latest .

echo "Docker image built successfully!"
docker images | grep muchtodo-backend
