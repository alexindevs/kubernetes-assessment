#!/bin/bash
set -euo pipefail
: "${ECR_REPOSITORY:?required}"
: "${IMAGE_TAG:?required}"
ASG_NAME="${ASG_NAME:-production-backend-asg}"
AWS_REGION="${AWS_REGION:-us-east-1}"
SSM_PATH="${SSM_PATH:-/starttech/production}"

if [ -n "${ECR_REGISTRY:-}" ]; then
  FULL_IMAGE="$ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG"
  LOGIN_REGISTRY="$ECR_REGISTRY"
else
  FULL_IMAGE="$ECR_REPOSITORY:$IMAGE_TAG"
  LOGIN_REGISTRY="$ECR_REPOSITORY"
fi

INSTANCES=$(aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "$ASG_NAME" --region "$AWS_REGION" \
  --query "AutoScalingGroups[0].Instances[?LifecycleState==\`InService\`].InstanceId" \
  --output text)
[ -z "$INSTANCES" ] && echo "No instances found" && exit 1

for INSTANCE_ID in $INSTANCES; do
  echo "  -> $INSTANCE_ID"
  CMD_ID=$(aws ssm send-command \
    --instance-ids "$INSTANCE_ID" \
    --document-name "AWS-RunShellScript" \
    --parameters commands="[
      \"aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $LOGIN_REGISTRY\",
      \"docker pull $FULL_IMAGE\",
      \"# Refresh secrets from SSM\",
      \"grep -v '^#' /etc/starttech/app.env | grep -v '^$' | grep -E '^(ENVIRONMENT|LOG_FILE|LOG_FORMAT|PORT|AWS_REGION)=' > /tmp/app.env.base\",
      \"aws ssm get-parameters-by-path --path '$SSM_PATH' --with-decryption --region $AWS_REGION --query 'Parameters[*].[Name,Value]' --output text | while IFS=\\$'\\t' read -r name value; do key=\\$(basename \\\"\\$name\\\"); echo \\\"\\$key=\\$value\\\"; done >> /tmp/app.env.base\",
      \"chmod 600 /tmp/app.env.base && mv /tmp/app.env.base /etc/starttech/app.env\",
      \"docker stop starttech-backend 2>/dev/null || true\",
      \"docker rm   starttech-backend 2>/dev/null || true\",
      \"docker run -d --name starttech-backend --restart always -p 8080:8080 -v /var/log/starttech:/var/log/starttech -v /etc/starttech/app.env:/.env:ro $FULL_IMAGE\"
    ]" \
    --region "$AWS_REGION" \
    --query "Command.CommandId" \
    --output text)
  aws ssm wait command-executed \
    --command-id "$CMD_ID" \
    --instance-id "$INSTANCE_ID" \
    --region "$AWS_REGION"
done
echo "==> Deployed $FULL_IMAGE"
