#!/bin/bash
set -euo pipefail
: "${ALB_DNS:?required}"
ENDPOINT="${ENDPOINT:-/health}"
MAX="${MAX_RETRIES:-10}"
WAIT="${WAIT_SECS:-15}"
echo "==> Health check: http://$ALB_DNS$ENDPOINT"
for i in $(seq 1 "$MAX"); do
  STATUS=$(curl -sf -o /dev/null -w "%{http_code}" --max-time 10 \
    "http://$ALB_DNS$ENDPOINT" || echo 000)
  [ "$STATUS" = "200" ] && echo "PASS on attempt $i" && exit 0
  echo "Attempt $i: HTTP $STATUS, retrying in ${WAIT}s..."
  sleep "$WAIT"
done
echo "FAILED after $MAX attempts" && exit 1
