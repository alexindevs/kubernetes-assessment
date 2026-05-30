#!/bin/bash
set -euo pipefail
[ -z "${1:-}" ] && echo "Usage: $0 <image-tag>" && exit 1
echo "==> Rolling back to tag: $1"
export IMAGE_TAG="$1"
bash "$(dirname "$0")/deploy-backend.sh"
