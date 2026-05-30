# System Architecture

## Overview

StartTech is a full-stack todo application. The frontend is a React SPA served from S3 via CloudFront. The backend is a Golang REST API running in Docker containers on EC2 instances behind an Application Load Balancer, with MongoDB Atlas as the database and ElastiCache Redis as an optional caching layer.

```
Browser
  │
  └─── HTTPS ──► CloudFront ──► S3 (React SPA, static files)
                     │
                     └─── API calls ──► ALB (HTTP, public)
                                          │
                                       EC2 ASG (private subnets, port 8080)
                                          │
                                 ┌────────┴────────┐
                                 │                 │
                           MongoDB Atlas      ElastiCache Redis
                           (external, TLS)   (private subnet, optional)
```

## Frontend: React SPA (`Client/`)

Built with Vite, TypeScript, TanStack Router, TanStack Query, and Radix UI components.

- **Routing**: Client-side via TanStack Router. CloudFront rewrites 403/404 responses to `index.html` so deep links work correctly.
- **API communication**: Axios client in `src/lib/apiClient.ts`, base URL set at build time via `VITE_API_BASE_URL`.
- **Auth**: JWT tokens stored in `httpOnly` cookies. The `AuthContext` (`src/context/AuthContext.tsx`) exposes auth state app-wide.
- **Build output**: `Client/dist/` — hashed asset filenames for long-term caching, `index.html` served with `no-cache`.

## Backend: Golang API (`Server/MuchToDo/`)

Gin web framework, structured JSON logging via `log/slog`, Swagger docs auto-generated with swaggo.

### Package layout

```
cmd/api/main.go          Entry point — wires all components, starts server
internal/
  config/                Viper-based config from .env / environment variables
  auth/                  JWT generation and validation (golang-jwt/jwt)
  cache/                 Redis client wrapper (go-redis); no-op when disabled
  database/              MongoDB connection (mongo-driver)
  handlers/              HTTP handlers: health, todo, user
  middleware/            CORS, auth JWT validation, request logging
  models/                BSON/JSON structs: User, Todo
  routes/                Route registration
  logger/                slog initialisation (JSON in prod, text in dev)
  utils/                 Cookie helpers
```

### Key design decisions

**Health endpoint** (`GET /health`): Checks MongoDB ping and Redis ping (if enabled) with 2-second timeouts each. Returns 200 only if all enabled dependencies are reachable. Used by the ALB target group for instance health tracking.

**Cache is optional**: `ENABLE_CACHE=false` (the default) disables Redis entirely — the app runs without it. When enabled, Redis caches username uniqueness checks and is preloaded with all existing usernames on startup.

**Auth**: JWTs issued as `httpOnly` cookies for browser clients, or read from the `Authorization: Bearer` header for API clients. Both paths go through the same `AuthMiddleware`.

**Graceful shutdown**: The server listens for `SIGINT`/`SIGTERM` and gives in-flight requests 5 seconds to complete before exiting.

### Container

Multi-stage Docker build:

1. **Builder** — `golang:1.25-alpine`. Compiles a statically linked binary (`CGO_ENABLED=0`) with debug info stripped.
2. **Runtime** — `gcr.io/distroless/static-debian12`. No shell, no package manager. Runs as `nonroot` (uid 65532).

The result is a small image with a minimal CVE surface.

## Data Layer

### MongoDB Atlas

- Hosts the `users` and `todos` collections.
- Connection string supplied via `MONGO_URI` environment variable.
- The `docker-compose.yaml` runs a local replica-set MongoDB for development.

### ElastiCache Redis

- Single-node `cache.t3.micro`, Redis 7, in private subnets.
- Only reachable from EC2 instances (security group restricts to port 6379 from `ec2-sg`).
- Connection address supplied via `REDIS_ADDR` environment variable.

## CI/CD Flow

```
git push
    │
    ├─► Frontend pipeline
    │     build-and-test ──► deploy (S3 sync + CF invalidation)
    │
    └─► Backend pipeline
          test ──► build-and-push (Docker build → Trivy scan → ECR push)
                       └──► deploy (SSM rolling update → smoke test)
```

Both pipelines gate deploys on `push` events only (not PRs). PRs run the build and test stages for validation but do not deploy.

## Infrastructure

All AWS resources are managed by Terraform in the [starttech-infra](../starttech-infra) repository. See that repo's [ARCHITECTURE.md](../starttech-infra/ARCHITECTURE.md) for the full infrastructure design including networking, security groups, IAM, and CloudWatch configuration.

Key infrastructure outputs consumed by this repo's pipelines:

| Terraform output | Used as |
|------------------|---------|
| `alb_dns_name` | Smoke test target, `VITE_API_BASE_URL` value |
| `s3_bucket_name` | `S3_BUCKET` in deploy-frontend.sh |
| `cloudfront_distribution_id` | Cache invalidation in deploy-frontend.sh |
| `ecr_repository_url` | Docker image registry |
| `asg_name` (via `terraform output`) | `ASG_NAME` secret for rolling deploy |
