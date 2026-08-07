#!/usr/bin/env bash
# Build Vue dist (production WS) and sync to S3 + invalidate CloudFront.
#
# Required env:
#   S3_BUCKET=lts-map-personalwork-tw
#   CF_DISTRIBUTION_ID=E123...
# Optional:
#   AWS_REGION=ap-northeast-1
#   FRONTEND_DIR=Frontend  (relative to repo root)

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FRONTEND_DIR="${FRONTEND_DIR:-$ROOT/Frontend}"
S3_BUCKET="${S3_BUCKET:?Set S3_BUCKET}"
CF_DISTRIBUTION_ID="${CF_DISTRIBUTION_ID:?Set CF_DISTRIBUTION_ID}"
AWS_REGION="${AWS_REGION:-ap-northeast-1}"

export VITE_WS_URL="${VITE_WS_URL:-wss://lts-api.personalwork.tw/ws}"
export VITE_APP_ORIGIN="${VITE_APP_ORIGIN:-https://lts-map.personalwork.tw}"

echo "Building Frontend with VITE_WS_URL=$VITE_WS_URL"
cd "$FRONTEND_DIR"
if [[ -f package-lock.json ]]; then
  npm ci
else
  npm install
fi
npm run build

echo "Syncing dist/ -> s3://$S3_BUCKET/"
aws s3 sync "$FRONTEND_DIR/dist/" "s3://$S3_BUCKET/" --region "$AWS_REGION" --delete \
  --cache-control "public,max-age=31536000,immutable" --exclude "index.html"
aws s3 cp "$FRONTEND_DIR/dist/index.html" "s3://$S3_BUCKET/index.html" --region "$AWS_REGION" \
  --cache-control "public,max-age=60,must-revalidate" --content-type "text/html"

echo "Invalidating CloudFront $CF_DISTRIBUTION_ID"
aws cloudfront create-invalidation --distribution-id "$CF_DISTRIBUTION_ID" --paths "/*" >/dev/null

echo "Done. Open https://lts-map.personalwork.tw"
