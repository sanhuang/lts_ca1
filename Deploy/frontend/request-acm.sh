#!/usr/bin/env bash
# Request ACM cert in us-east-1 for CloudFront custom domain and print DNS validation CNAME.

set -euo pipefail

DOMAIN="${DOMAIN:-lts-map.personalwork.tw}"

CERT_ARN=$(aws acm request-certificate --region us-east-1 \
  --domain-name "$DOMAIN" \
  --validation-method DNS \
  --query CertificateArn --output text)
echo "ACM_CERT_ARN=$CERT_ARN"

echo "Waiting briefly for validation record..."
sleep 5
aws acm describe-certificate --region us-east-1 --certificate-arn "$CERT_ARN" \
  --query 'Certificate.DomainValidationOptions[0].ResourceRecord' --output json

echo
echo "Add the CNAME above at your DNS provider, then:"
echo "  aws acm wait certificate-validated --region us-east-1 --certificate-arn $CERT_ARN"
echo "  export ACM_CERT_ARN=$CERT_ARN"
echo "  bash Deploy/frontend/provision-cloudfront.sh"
