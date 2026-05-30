# StartTech Application

Full-stack todo application consisting of a React frontend and a Golang REST API backend, with CI/CD pipelines for automated deployment to AWS.

## Repository Structure

```
starttech-application/
├── .github/workflows/
│   ├── frontend-ci-cd.yml      # React: build, audit, test → S3 + CloudFront
│   └── backend-ci-cd.yml       # Go: test, scan, Docker build → ECR → EC2 ASG
├── Client/                     # React + Vite + TypeScript frontend
├── Server/MuchToDo/            # Golang REST API
│   └── Dockerfile              # Multi-stage build (distroless runtime)
├── scripts/
│   ├── deploy-frontend.sh      # Syncs Client/dist to S3, invalidates CloudFront
│   ├── deploy-backend.sh       # Rolling deploy via SSM to ASG instances
│   ├── health-check.sh         # Polls ALB /health endpoint
│   └── rollback.sh             # Re-deploys a previous image tag
└── README.md
```

## Prerequisites

- Node.js 20+ (frontend)
- Go 1.25+ (backend)
- Docker (backend container builds)
- AWS CLI v2, configured with credentials that can reach the deployed infrastructure

## Running Locally

### Backend

```bash
cd Server/MuchToDo
cp .env.example .env
# Edit .env — set MONGO_URI and JWT_SECRET_KEY at minimum

# Start MongoDB + Redis via Docker Compose
docker-compose up -d

# Run the API
go run ./cmd/api/main.go
# API available at http://localhost:8080
# Swagger docs at http://localhost:8080/swagger/index.html
```

### Frontend

```bash
cd Client
cp .env.example .env
# Edit .env — set VITE_API_BASE_URL=http://localhost:8080

npm install
npm run dev
# App available at http://localhost:5173
```

## Running Tests

### Backend unit tests

```bash
cd Server/MuchToDo
go test ./...
```

### Backend integration tests (requires Docker)

```bash
cd Server/MuchToDo
INTEGRATION=true go test -tags=integration -v ./...
```

### Frontend lint

```bash
cd Client
npm run lint
```

## CI/CD Pipelines

### Frontend pipeline (`.github/workflows/frontend-ci-cd.yml`)

Triggers on pushes and PRs to `feature/full-stack` that touch `Client/`.

| Stage | What runs |
|-------|-----------|
| Build & Test | `npm ci`, `npm audit` (fails on HIGH/CRITICAL), `npm test`, `npm run build` |
| Upload artifact | `Client/dist` uploaded so the deploy job uses the exact same build |
| Deploy (push only) | Syncs dist to S3, invalidates CloudFront, posts commit status |

Required GitHub Secrets:

| Secret | Description |
|--------|-------------|
| `AWS_ACCESS_KEY_ID` | IAM credentials with S3 write + CloudFront invalidation |
| `AWS_SECRET_ACCESS_KEY` | Corresponding secret |
| `S3_BUCKET_NAME` | Frontend S3 bucket name (from `terraform output s3_bucket_name`) |
| `CLOUDFRONT_DISTRIBUTION_ID` | (from `terraform output cloudfront_distribution_id`) |
| `VITE_API_BASE_URL` | Backend ALB URL injected at build time (e.g. `http://<alb-dns>`) |

### Backend pipeline (`.github/workflows/backend-ci-cd.yml`)

Triggers on pushes and PRs to `main` that touch `Server/MuchToDo/`.

| Stage | What runs |
|-------|-----------|
| Test | `go test`, `go vet`, `govulncheck` |
| Build & Scan | Docker build, Trivy scan (fails on HIGH/CRITICAL), push to ECR |
| Deploy (push only) | Rolling deploy via SSM, smoke test against ALB `/health` |

Required GitHub Secrets (in addition to `AWS_*` above):

| Secret | Description |
|--------|-------------|
| `ASG_NAME` | Auto Scaling Group name (from `terraform output` in starttech-infra) |
| `ALB_NAME` | ALB name, used for smoke test DNS lookup |

## Deployment Scripts

All scripts are in `scripts/` and can be run locally given the right environment variables.

```bash
# Deploy frontend (expects Client/dist to already exist)
S3_BUCKET=my-bucket CLOUDFRONT_DISTRIBUTION_ID=EXXX bash scripts/deploy-frontend.sh

# Deploy a specific backend image tag
ECR_REGISTRY=123.dkr.ecr.us-east-1.amazonaws.com \
ECR_REPOSITORY=starttech-backend \
IMAGE_TAG=abc1234 \
ASG_NAME=production-backend-asg \
bash scripts/deploy-backend.sh

# Roll back to a previous tag
bash scripts/rollback.sh <previous-image-tag>

# Health check
ALB_DNS=my-alb.us-east-1.elb.amazonaws.com bash scripts/health-check.sh
```

See [RUNBOOK.md](RUNBOOK.md) for full operational procedures.
