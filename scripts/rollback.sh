#!/bin/bash
set -euo pipefail
[ -z "${1:-}" ] && echo "Usage: $0 <image-tag>" && exit 1
echo "==> Rolling back to tag: $1"
export IMAGE_TAG="$1"
export ECR_REPOSITORY="${ECR_REPOSITORY:-starttech-backend}"
export ECR_REGISTRY="${ECR_REGISTRY:-927656030834.dkr.ecr.us-east-1.amazonaws.com}"
export ASG_NAME="${ASG_NAME:-production-backend-asg}"
export AWS_REGION="${AWS_REGION:-us-east-1}"
bash "$(dirname "$0")/deploy-backend.sh"
