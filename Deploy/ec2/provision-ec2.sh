#!/usr/bin/env bash
# Provision minimal EC2 edge (Ubuntu) + EIP + SG for lts-api.personalwork.tw
# Prerequisites: aws CLI configured (SSO/login), jq
#
# Usage:
#   export AWS_REGION=ap-northeast-1
#   export KEY_NAME=your-ec2-keypair          # existing key pair name
#   ./provision-ec2.sh
#
# Outputs instance id, public/EIP, and next DNS steps.

set -euo pipefail

AWS_REGION="${AWS_REGION:-ap-northeast-1}"
NAME_TAG="${NAME_TAG:-lts-api-edge}"
INSTANCE_TYPE="${INSTANCE_TYPE:-t3.micro}"
KEY_NAME="${KEY_NAME:?Set KEY_NAME to an existing EC2 key pair}"

need() { command -v "$1" >/dev/null || { echo "Missing: $1" >&2; exit 1; }; }
need aws
need jq

echo "Region=$AWS_REGION instance_type=$INSTANCE_TYPE key=$KEY_NAME"

# Default VPC + subnet
VPC_ID=$(aws ec2 describe-vpcs --region "$AWS_REGION" --filters Name=isDefault,Values=true \
  --query 'Vpcs[0].VpcId' --output text)
if [[ -z "$VPC_ID" || "$VPC_ID" == "None" ]]; then
  echo "No default VPC in $AWS_REGION. Create VPC or set VPC_ID/SUBNET_ID." >&2
  exit 1
fi
SUBNET_ID=$(aws ec2 describe-subnets --region "$AWS_REGION" \
  --filters Name=vpc-id,Values="$VPC_ID" Name=default-for-az,Values=true \
  --query 'Subnets[0].SubnetId' --output text)
echo "VPC=$VPC_ID SUBNET=$SUBNET_ID"

SG_ID=$(aws ec2 create-security-group --region "$AWS_REGION" \
  --group-name "${NAME_TAG}-sg" \
  --description "lts-api edge HTTP/HTTPS" \
  --vpc-id "$VPC_ID" \
  --query GroupId --output text 2>/dev/null || true)

if [[ -z "${SG_ID}" || "$SG_ID" == "None" ]]; then
  SG_ID=$(aws ec2 describe-security-groups --region "$AWS_REGION" \
    --filters Name=group-name,Values="${NAME_TAG}-sg" Name=vpc-id,Values="$VPC_ID" \
    --query 'SecurityGroups[0].GroupId' --output text)
fi
echo "SG=$SG_ID"

authorize() {
  local proto=$1 port=$2
  aws ec2 authorize-security-group-ingress --region "$AWS_REGION" \
    --group-id "$SG_ID" --protocol "$proto" --port "$port" --cidr 0.0.0.0/0 >/dev/null 2>&1 || true
}
authorize tcp 22
authorize tcp 80
authorize tcp 443
# NetBird WireGuard / management often uses UDP; keep egress open (default)
authorize udp 51820

# Ubuntu 24.04 LTS AMI (canonical)
AMI_ID=$(aws ec2 describe-images --region "$AWS_REGION" --owners 099720109477 \
  --filters \
    Name=name,Values='ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*' \
    Name=state,Values=available \
  --query 'sort_by(Images,&CreationDate)[-1].ImageId' --output text)
echo "AMI=$AMI_ID"

USER_DATA=$(mktemp)
trap 'rm -f "$USER_DATA"' EXIT
cat >"$USER_DATA" <<'EOF'
#!/bin/bash
set -euo pipefail
apt-get update -y
apt-get install -y curl ca-certificates
# Leave Caddy/NetBird to Deploy/ec2/bootstrap.sh after first SSH
hostnamectl set-hostname lts-api-edge || true
EOF

INSTANCE_ID=$(aws ec2 run-instances --region "$AWS_REGION" \
  --image-id "$AMI_ID" \
  --instance-type "$INSTANCE_TYPE" \
  --key-name "$KEY_NAME" \
  --security-group-ids "$SG_ID" \
  --subnet-id "$SUBNET_ID" \
  --associate-public-ip-address \
  --user-data "file://$USER_DATA" \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$NAME_TAG}]" \
  --query 'Instances[0].InstanceId' --output text)
echo "INSTANCE_ID=$INSTANCE_ID"

aws ec2 wait instance-running --region "$AWS_REGION" --instance-ids "$INSTANCE_ID"

ALLOC=$(aws ec2 allocate-address --region "$AWS_REGION" --domain vpc --query AllocationId --output text)
aws ec2 associate-address --region "$AWS_REGION" --instance-id "$INSTANCE_ID" --allocation-id "$ALLOC" >/dev/null
EIP=$(aws ec2 describe-addresses --region "$AWS_REGION" --allocation-ids "$ALLOC" --query 'Addresses[0].PublicIp' --output text)

PUBLIC_DNS=$(aws ec2 describe-instances --region "$AWS_REGION" --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].PublicDnsName' --output text)

echo
echo "=== EC2 ready ==="
echo "Instance: $INSTANCE_ID"
echo "EIP:      $EIP"
echo "DNS:      $PUBLIC_DNS"
echo
echo "Next:"
echo "1) DNS A: lts-api.personalwork.tw -> $EIP"
echo "2) SSH:   ssh -i <key.pem> ubuntu@$EIP"
echo "3) Copy Deploy/ec2/{Caddyfile,bootstrap.sh} and run:"
echo "     export NETBIRD_SETUP_KEY=..."
echo "     sudo bash bootstrap.sh"
echo "4) From EC2: curl -fsS http://tazs-m1pro.netbird.cloud:8000/healthz"
