# Operations Runbook

Day-to-day procedures for operating the StartTech application.

---

## First-Time Secret Setup (SSM Parameter Store)

EC2 instances fetch application secrets from SSM Parameter Store at boot and on every deploy. These parameters must exist before any instance starts or any deploy runs.

All parameters live under the path `/starttech/<environment>/`. Each parameter name becomes the environment variable key inside the container.

### Parameters to create

Run these commands once after `terraform apply` has completed. Replace the values in `<angle brackets>` with your actual secrets.

```bash
ENV=production
REGION=us-east-1

# MongoDB connection string (from MongoDB Atlas: Connect → Drivers → copy the URI)
aws ssm put-parameter \
  --name "/starttech/$ENV/MONGO_URI" \
  --value "mongodb+srv://<username>:<password>@<cluster>.mongodb.net/<dbname>?retryWrites=true&w=majority" \
  --type SecureString \
  --region $REGION

# MongoDB database name
aws ssm put-parameter \
  --name "/starttech/$ENV/DB_NAME" \
  --value "much_todo_db" \
  --type SecureString \
  --region $REGION

# JWT signing secret — generate a strong random value
aws ssm put-parameter \
  --name "/starttech/$ENV/JWT_SECRET_KEY" \
  --value "$(openssl rand -base64 48)" \
  --type SecureString \
  --region $REGION

# JWT expiry in hours
aws ssm put-parameter \
  --name "/starttech/$ENV/JWT_EXPIRATION_HOURS" \
  --value "72" \
  --type SecureString \
  --region $REGION

# Redis endpoint (from: terraform output redis_endpoint in starttech-infra)
aws ssm put-parameter \
  --name "/starttech/$ENV/REDIS_ADDR" \
  --value "<redis-endpoint>:6379" \
  --type SecureString \
  --region $REGION

# Enable Redis caching
aws ssm put-parameter \
  --name "/starttech/$ENV/ENABLE_CACHE" \
  --value "true" \
  --type SecureString \
  --region $REGION

# CORS — comma-separated list of allowed origins (your CloudFront domain)
# From: terraform output cloudfront_domain in starttech-infra
aws ssm put-parameter \
  --name "/starttech/$ENV/ALLOWED_ORIGINS" \
  --value "https://<distribution>.cloudfront.net" \
  --type SecureString \
  --region $REGION

# Cookie domain (your CloudFront domain without https://)
aws ssm put-parameter \
  --name "/starttech/$ENV/COOKIE_DOMAINS" \
  --value "<distribution>.cloudfront.net" \
  --type SecureString \
  --region $REGION

# Secure cookies (true in production — requires HTTPS)
aws ssm put-parameter \
  --name "/starttech/$ENV/SECURE_COOKIE" \
  --value "true" \
  --type SecureString \
  --region $REGION
```

### Verifying the parameters exist

```bash
aws ssm get-parameters-by-path \
  --path "/starttech/production" \
  --with-decryption \
  --region us-east-1 \
  --query "Parameters[*].{Name:Name,Value:Value}" \
  --output table
```

### Updating a secret

```bash
aws ssm put-parameter \
  --name "/starttech/production/JWT_SECRET_KEY" \
  --value "<new-value>" \
  --type SecureString \
  --overwrite \
  --region us-east-1
```

After updating a secret, run a deploy to push the new value to running instances:

```bash
bash scripts/deploy-backend.sh
```

---

## Deploying the Frontend

### Automatic (normal path)

Push to `feature/full-stack` with changes under `Client/`. The pipeline builds, audits, and deploys automatically.

### Manual

```bash
cd Client
npm ci
VITE_API_BASE_URL=http://<alb-dns> npm run build

export S3_BUCKET=<bucket-name>
export CLOUDFRONT_DISTRIBUTION_ID=<distribution-id>
bash ../scripts/deploy-frontend.sh
```

---

## Deploying the Backend

### Automatic (normal path)

Push to `main` with changes under `Server/MuchToDo/`. The pipeline tests, builds, scans, and deploys automatically.

### Manual

```bash
# Build and push
ECR_REGISTRY=<account>.dkr.ecr.us-east-1.amazonaws.com
IMAGE_TAG=$(git rev-parse --short HEAD)

aws ecr get-login-password --region us-east-1 \
  | docker login --username AWS --password-stdin $ECR_REGISTRY

docker build -t $ECR_REGISTRY/starttech-backend:$IMAGE_TAG ./Server/MuchToDo
docker push $ECR_REGISTRY/starttech-backend:$IMAGE_TAG

# Deploy
export ECR_REGISTRY
export ECR_REPOSITORY=starttech-backend
export IMAGE_TAG
export ASG_NAME=production-backend-asg
export AWS_REGION=us-east-1
bash scripts/deploy-backend.sh
```

---

## Rolling Back the Backend

```bash
bash scripts/rollback.sh <previous-image-tag>
```

To list available image tags in ECR:

```bash
aws ecr list-images --repository-name starttech-backend \
  --query 'imageIds[*].imageTag' --output table
```

To find the tag deployed before the current one, cross-reference with git log:

```bash
git log --oneline -10
```

Each tag is the full commit SHA. Pass any previous SHA as the rollback argument.

---

## Health Checks

### Quick check via ALB

```bash
ALB_DNS=$(aws elbv2 describe-load-balancers \
  --names production-alb \
  --query 'LoadBalancers[0].DNSName' --output text)
curl -s "http://$ALB_DNS/health" | jq .
# Healthy: {"database":"ok","cache":"ok"} or {"database":"ok","cache":"disabled"}
# Unhealthy: {"database":"down","cache":"..."} with HTTP 503
```

### Using the health-check script

```bash
ALB_DNS=<alb-dns> bash scripts/health-check.sh

# Customise retries and wait:
ALB_DNS=<alb-dns> MAX_RETRIES=5 WAIT_SECS=10 bash scripts/health-check.sh
```

### Check CloudFront

```bash
CF_DOMAIN=<distribution>.cloudfront.net
curl -sI "https://$CF_DOMAIN" | grep -E "HTTP|x-cache|x-amz"
```

---

## Accessing EC2 Instances

There is no SSH access. Use AWS SSM Session Manager:

```bash
# List running instances
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names production-backend-asg \
  --query 'AutoScalingGroups[0].Instances[?LifecycleState==`InService`].[InstanceId]' \
  --output text

# Open a session
aws ssm start-session --target <instance-id>
```

Once inside:

```bash
# Check container status
docker ps
docker logs starttech-backend --tail 50 -f

# Check app config
cat /etc/starttech/app.env

# Check CloudWatch agent
systemctl status amazon-cloudwatch-agent
```

---

## Viewing Logs

### Live tail from CloudWatch

```bash
aws logs tail /starttech/production/app --follow --region us-east-1
```

### Filter errors from the last hour

```bash
aws logs filter-log-events \
  --log-group-name /starttech/production/app \
  --filter-pattern "ERROR" \
  --start-time $(date -d '1 hour ago' +%s)000 \
  --region us-east-1 \
  --query 'events[*].message' --output text
```

### Logs Insights

Open CloudWatch → Logs Insights → select `/starttech/production/app`.
Pre-written queries are in `starttech-infra/monitoring/log-insights-queries.txt`.

---

## Scaling

### Manual scale-out (before a known traffic spike)

```bash
aws autoscaling set-desired-capacity \
  --auto-scaling-group-name production-backend-asg \
  --desired-capacity 3 \
  --region us-east-1
```

### Check current ASG state

```bash
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names production-backend-asg \
  --query 'AutoScalingGroups[0].{Min:MinSize,Desired:DesiredCapacity,Max:MaxSize,Instances:Instances[*].{ID:InstanceId,State:LifecycleState,Health:HealthStatus}}' \
  --output json
```

CPU-based auto-scaling is configured in Terraform — scale-out at >70% CPU for 10 minutes, scale-in at <30% for 20 minutes.

---

## Incident Response

### Backend health checks failing

1. Check CloudWatch alarm `production-alb-unhealthy-hosts`
2. Check target health: `aws elbv2 describe-target-health --target-group-arn <arn>`
3. SSM into the failing instance, run `docker logs starttech-backend --tail 100`
4. If container exited: `docker inspect starttech-backend` — look at `State.ExitCode` and `State.Error`
5. If caused by a bad deploy: `bash scripts/rollback.sh <previous-tag>`

### High 5xx error rate

1. Check CloudWatch alarm `production-alb-5xx-high`
2. Correlate with recent deploys: `git log --oneline -5` in this repo
3. Filter CloudWatch Logs for `ERROR` lines (see Logs section above)
4. Roll back if the error rate spiked after a deploy

### Frontend not updating after deploy

1. Confirm the pipeline completed: check the Actions tab in GitHub
2. Check whether the CloudFront invalidation completed:
   ```bash
   aws cloudfront list-invalidations \
     --distribution-id <distribution-id> \
     --query 'InvalidationList.Items[0].{Status:Status,CreateTime:CreateTime}'
   ```
3. If invalidation is still `InProgress`, wait — it typically completes in under 60 seconds
4. Hard-refresh the browser (`Ctrl+Shift+R`) to bypass local browser cache

### Cannot reach the API from the frontend

1. Check the `VITE_API_BASE_URL` secret in GitHub — it must match the current ALB DNS name
2. Verify CORS config: `ALLOWED_ORIGINS` in the backend env file must include the CloudFront domain
3. Check the ALB listener is on port 80: `aws elbv2 describe-listeners --load-balancer-arn <arn>`

### Redis connectivity errors in logs

1. Confirm `ENABLE_CACHE=true` in `/etc/starttech/app.env` on the instance
2. Test from the instance: `nc -zv <redis-endpoint> 6379`
3. Check the Redis cluster status:
   ```bash
   aws elasticache describe-cache-clusters \
     --cache-cluster-id production-redis \
     --query 'CacheClusters[0].CacheClusterStatus'
   ```
4. If Redis is down and blocking the app, set `ENABLE_CACHE=false` in the env file and restart the container as a temporary mitigation
