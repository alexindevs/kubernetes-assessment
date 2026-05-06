# MuchToDo Kubernetes Setup

This repository includes a local Kubernetes setup for the MuchToDo backend using `kind` and the NGINX Ingress Controller.

The deployment is designed for local development and assessment runs:

- the backend image is built locally from the repository `Dockerfile`
- a single-node `kind` cluster is created with host ports `80` and `443` mapped into the cluster
- MongoDB is deployed inside Kubernetes with a PVC for storage
- the backend is exposed internally through a `ClusterIP` service
- ingress routes `http://localhost/` traffic to the backend service

## Architecture

The Kubernetes resources live under `kubernetes/`:

- `kubernetes/namespace.yaml`: creates the `muchtodo` namespace
- `kubernetes/mongodb/`: MongoDB deployment, service, PVC, config map, and secret
- `kubernetes/backend/`: backend deployment, service, config map, and secret
- `kubernetes/ingress.yaml`: routes traffic from the NGINX ingress controller to the backend service

The `kind` cluster configuration is in `kind-config.yaml`. It labels the control-plane node as ingress-ready and forwards host ports `80` and `443` to the cluster so the application is reachable on `localhost`.

## Prerequisites

Install the following tools before running the setup:

- `docker`
- `kubectl`
- `kind`

You also need network access to pull public images such as:

- `mongo:7.0`
- `registry.k8s.io/ingress-nginx/*`

## How Deployment Works

The Kubernetes deployment flow is automated by `scripts/k8s-deploy.sh`.

It performs these steps:

1. Builds the backend image as `muchtodo-backend:latest`
2. Recreates the `kind` cluster named `muchtodo`
3. Loads the backend image into the cluster
4. Installs the NGINX ingress controller
5. Waits for ingress to become ready
6. Applies namespace and MongoDB resources first
7. Waits for MongoDB rollout to complete
8. Applies backend and ingress resources
9. Waits for backend rollout to complete

MongoDB is deployed before the backend on purpose so the backend does not crash-loop while the database is still provisioning or pulling its image.

## Run the Kubernetes Setup

From the repository root:

```bash
./scripts/k8s-deploy.sh
```

The script may take several minutes on a fresh run because it needs to:

- create the cluster
- install ingress
- provision storage
- pull Kubernetes and MongoDB images

## Verify the Deployment

Check all resources in the namespace:

```bash
kubectl get all -n muchtodo
```

Check the ingress resource:

```bash
kubectl get ingress -n muchtodo
```

Test the application locally through ingress:

```bash
curl http://localhost/health
```

You can also hit the root route:

```bash
curl http://localhost/
```

## Access Pattern

Traffic flow looks like this:

`localhost` -> NGINX ingress controller -> `backend` service -> backend pods

MongoDB is only exposed inside the cluster:

`backend` pods -> `mongodb` service -> MongoDB pod

## Cleanup

To remove the namespace and delete the `kind` cluster:

```bash
./scripts/k8s-cleanup.sh
```

## Troubleshooting

If the deploy script exits early, it prints namespace diagnostics automatically. You can also inspect the cluster manually with:

```bash
kubectl get all -n muchtodo
kubectl get events -n muchtodo --sort-by=.lastTimestamp
kubectl logs -n muchtodo deployment/backend
kubectl logs -n muchtodo deployment/mongodb
```

Common causes of slow or failed startup:

- slow image pulls from Docker Hub or `registry.k8s.io`
- delayed PVC provisioning for MongoDB
- backend waiting for MongoDB to become reachable

If ingress is healthy and the `backend` deployment is available, `http://localhost/health` should return a successful response.
