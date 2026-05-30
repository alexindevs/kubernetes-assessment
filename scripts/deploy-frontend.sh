#!/bin/bash
set -euo pipefail
: "${S3_BUCKET:?required}"
: "${CLOUDFRONT_DISTRIBUTION_ID:?required}"
AWS_REGION="${AWS_REGION:-us-east-1}"
DIST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../Client/dist"

[ -d "$DIST_DIR" ] || { echo "ERROR: dist directory not found at $DIST_DIR"; exit 1; }

echo "==> Uploading to s3://$S3_BUCKET"
aws s3 sync "$DIST_DIR" "s3://$S3_BUCKET" --delete --region "$AWS_REGION" \
  --cache-control "public,max-age=31536000,immutable" --exclude "*.html"
aws s3 cp "$DIST_DIR/index.html" "s3://$S3_BUCKET/index.html" \
  --cache-control "no-cache,no-store,must-revalidate" --region "$AWS_REGION"

echo "==> Invalidating CloudFront distribution $CLOUDFRONT_DISTRIBUTION_ID..."
aws cloudfront create-invalidation \
  --distribution-id "$CLOUDFRONT_DISTRIBUTION_ID" --paths "/*"

echo "==> Done."
