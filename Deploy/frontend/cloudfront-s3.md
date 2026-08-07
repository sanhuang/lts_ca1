# CloudFront + S3 建置手冊（`lts-map.personalwork.tw`）

假設：AWS CLI 已登入；靜態站區域 `ap-northeast-1`；**ACM 憑證在 `us-east-1`**。

## 1. 變數

```bash
export AWS_REGION=ap-northeast-1
export BUCKET=lts-map-personalwork-tw-$(aws sts get-caller-identity --query Account --output text)
export DOMAIN=lts-map.personalwork.tw
```

## 2. S3 bucket（私有）

```bash
aws s3api create-bucket \
  --bucket "$BUCKET" \
  --region "$AWS_REGION" \
  --create-bucket-configuration LocationConstraint="$AWS_REGION"

aws s3api put-public-access-block --bucket "$BUCKET" \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

aws s3api put-bucket-ownership-controls --bucket "$BUCKET" \
  --ownership-controls 'Rules=[{ObjectOwnership=BucketOwnerEnforced}]'
```

## 3. ACM 憑證（必須 us-east-1）

```bash
CERT_ARN=$(aws acm request-certificate --region us-east-1 \
  --domain-name "$DOMAIN" \
  --validation-method DNS \
  --query CertificateArn --output text)
echo "CERT_ARN=$CERT_ARN"

aws acm describe-certificate --region us-east-1 --certificate-arn "$CERT_ARN" \
  --query 'Certificate.DomainValidationOptions[0].ResourceRecord'
```

在 DNS 供應商新增輸出的 CNAME（驗證用）。等到：

```bash
aws acm wait certificate-validated --region us-east-1 --certificate-arn "$CERT_ARN"
```

## 4. 一鍵建立 OAC + CloudFront（腳本）

見同目錄 [`provision-cloudfront.sh`](./provision-cloudfront.sh)。成功後會印出：

- `CF_DOMAIN`（`dxxxx.cloudfront.net`）→ DNS **CNAME** `lts-map.personalwork.tw`
- `CF_DISTRIBUTION_ID`、`S3_BUCKET` → 給 [`deploy.sh`](./deploy.sh)

## 5. 部署 dist

```bash
export S3_BUCKET=...
export CF_DISTRIBUTION_ID=...
bash Deploy/frontend/deploy.sh
```

## 6. SPA fallback

腳本會設定 Custom Error Response：`403`／`404` → `/index.html`（HTTP 200）。
