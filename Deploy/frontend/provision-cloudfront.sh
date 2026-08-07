#!/usr/bin/env bash
# Create private S3 + CloudFront (OAC) for lts-map.personalwork.tw
# Prereq: ACM cert in us-east-1 already ISSUED for the domain.
#
# Usage:
#   export ACM_CERT_ARN=arn:aws:acm:us-east-1:...:certificate/...
#   export DOMAIN=lts-map.personalwork.tw
#   export AWS_REGION=ap-northeast-1
#   ./provision-cloudfront.sh

set -euo pipefail

need() { command -v "$1" >/dev/null || { echo "Missing: $1" >&2; exit 1; }; }
need aws
need jq
need python3

DOMAIN="${DOMAIN:-lts-map.personalwork.tw}"
AWS_REGION="${AWS_REGION:-ap-northeast-1}"
ACM_CERT_ARN="${ACM_CERT_ARN:?Set ACM_CERT_ARN (us-east-1 issued cert)}"
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
BUCKET="${S3_BUCKET:-lts-map-${ACCOUNT}}"

echo "DOMAIN=$DOMAIN BUCKET=$BUCKET REGION=$AWS_REGION"

# Create bucket if missing
if ! aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
  aws s3api create-bucket --bucket "$BUCKET" --region "$AWS_REGION" \
    --create-bucket-configuration LocationConstraint="$AWS_REGION"
  aws s3api put-public-access-block --bucket "$BUCKET" \
    --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
  aws s3api put-bucket-ownership-controls --bucket "$BUCKET" \
    --ownership-controls 'Rules=[{ObjectOwnership=BucketOwnerEnforced}]'
fi

OAC_ID=$(aws cloudfront create-origin-access-control \
  --origin-access-control-config "{
    \"Name\": \"${DOMAIN}-oac\",
    \"Description\": \"OAC for ${DOMAIN}\",
    \"SigningProtocol\": \"sigv4\",
    \"SigningBehavior\": \"always\",
    \"OriginAccessControlOriginType\": \"s3\"
  }" --query 'OriginAccessControl.Id' --output text 2>/dev/null || true)

if [[ -z "$OAC_ID" || "$OAC_ID" == "None" ]]; then
  OAC_ID=$(aws cloudfront list-origin-access-controls \
    --query "OriginAccessControlList.Items[?Name=='${DOMAIN}-oac'].Id | [0]" --output text)
fi
echo "OAC_ID=$OAC_ID"

CALLER_REF="lts-map-$(date +%s)"
DIST_CONFIG=$(mktemp)
trap 'rm -f "$DIST_CONFIG" "$DIST_CONFIG.out" "$POLICY" 2>/dev/null' EXIT

cat >"$DIST_CONFIG" <<EOF
{
  "CallerReference": "$CALLER_REF",
  "Comment": "$DOMAIN",
  "Enabled": true,
  "Aliases": { "Quantity": 1, "Items": ["$DOMAIN"] },
  "DefaultRootObject": "index.html",
  "Origins": {
    "Quantity": 1,
    "Items": [{
      "Id": "s3-$BUCKET",
      "DomainName": "$BUCKET.s3.$AWS_REGION.amazonaws.com",
      "S3OriginConfig": { "OriginAccessIdentity": "" },
      "OriginAccessControlId": "$OAC_ID"
    }]
  },
  "DefaultCacheBehavior": {
    "TargetOriginId": "s3-$BUCKET",
    "ViewerProtocolPolicy": "redirect-to-https",
    "AllowedMethods": {
      "Quantity": 2,
      "Items": ["GET", "HEAD"],
      "CachedMethods": { "Quantity": 2, "Items": ["GET", "HEAD"] }
    },
    "Compress": true,
    "CachePolicyId": "658327ea-f89d-4fab-a63d-7e88639e58f6",
    "OriginRequestPolicyId": "88a5eaf4-2fd4-4709-b370-b4c650ea3fcf"
  },
  "CustomErrorResponses": {
    "Quantity": 2,
    "Items": [
      {
        "ErrorCode": 403,
        "ResponsePagePath": "/index.html",
        "ResponseCode": "200",
        "ErrorCachingMinTTL": 0
      },
      {
        "ErrorCode": 404,
        "ResponsePagePath": "/index.html",
        "ResponseCode": "200",
        "ErrorCachingMinTTL": 0
      }
    ]
  },
  "ViewerCertificate": {
    "ACMCertificateArn": "$ACM_CERT_ARN",
    "SSLSupportMethod": "sni-only",
    "MinimumProtocolVersion": "TLSv1.2_2021"
  },
  "HttpVersion": "http2and3",
  "PriceClass": "PriceClass_200"
}
EOF

aws cloudfront create-distribution --distribution-config "file://$DIST_CONFIG" >"$DIST_CONFIG.out"
DIST_ID=$(jq -r '.Distribution.Id' "$DIST_CONFIG.out")
CF_DOMAIN=$(jq -r '.Distribution.DomainName' "$DIST_CONFIG.out")
echo "CF_DISTRIBUTION_ID=$DIST_ID"
echo "CF_DOMAIN=$CF_DOMAIN"

# Bucket policy for OAC
POLICY=$(mktemp)
cat >"$POLICY" <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "AllowCloudFrontServicePrincipalRead",
    "Effect": "Allow",
    "Principal": { "Service": "cloudfront.amazonaws.com" },
    "Action": "s3:GetObject",
    "Resource": "arn:aws:s3:::$BUCKET/*",
    "Condition": {
      "StringEquals": {
        "AWS:SourceArn": "arn:aws:cloudfront::$ACCOUNT:distribution/$DIST_ID"
      }
    }
  }]
}
EOF
aws s3api put-bucket-policy --bucket "$BUCKET" --policy "file://$POLICY"

echo
echo "=== CloudFront created ==="
echo "S3_BUCKET=$BUCKET"
echo "CF_DISTRIBUTION_ID=$DIST_ID"
echo "DNS CNAME: $DOMAIN -> $CF_DOMAIN"
echo
echo "Deploy:"
echo "  S3_BUCKET=$BUCKET CF_DISTRIBUTION_ID=$DIST_ID bash Deploy/frontend/deploy.sh"
