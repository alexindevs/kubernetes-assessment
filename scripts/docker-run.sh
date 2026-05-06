#!/bin/bash
set -e

echo "Starting services with docker-compose..."
docker compose up -d --build

echo "Waiting for services to be healthy..."
for i in {1..30}; do
  backend_status=$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' muchtodo-backend 2>/dev/null || true)
  mongodb_status=$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' muchtodo-mongodb 2>/dev/null || true)

  if [ "$backend_status" = "healthy" ] && [ "$mongodb_status" = "healthy" ]; then
    break
  fi

  sleep 2
done

if [ "$backend_status" != "healthy" ] || [ "$mongodb_status" != "healthy" ]; then
  echo "Services did not become healthy in time."
  docker compose ps
  exit 1
fi

echo "Services running:"
docker compose ps

echo ""
echo "Backend is accessible at http://localhost:8080"
echo "Health check: http://localhost:8080/health"
