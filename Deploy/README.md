# Deploy — 正式網域落地（S3／CloudFront + EC2 NetBird + 本機 API）

## 架構

```text
瀏覽器
  ├─ https://lts-map.personalwork.tw  → CloudFront → S3 (Vue dist)
  └─ https://lts-api.personalwork.tw  → EC2 Caddy (TLS)
                                          └─ NetBird → tazs-m1pro.netbird.cloud:8000
                                                └─ Docker FastAPI (+ ROS Publisher)
```

本機 NetBird FQDN 以 `netbird status` 為準（目前為 **`tazs-m1pro.netbird.cloud`**，非字面上的 `m1pro`）。

| 網域 | 資源 |
|------|------|
| `lts-map.personalwork.tw` | S3 + CloudFront + ACM（`us-east-1`） |
| `lts-api.personalwork.tw` | EC2 EIP + Caddy → NetBird → 本機 `:8000` |
| Swagger / WS | `https://lts-api.personalwork.tw/docs`、`wss://lts-api.personalwork.tw/ws` |

### 現行環境清冊（2026-08-07 驗收通過）

| 項目 | 值 |
|------|-----|
| EC2 | `i-035c3bc8c5a6a9c58`（`ap-northeast-1`） |
| EIP | `54.65.196.154` |
| Edge peer | `lts-api-edge.netbird.cloud` |
| Upstream peer | `tazs-m1pro.netbird.cloud:8000` |
| S3 | `lts-map-382334304827` |
| CloudFront | `E1DJ75OE6J486A` → `d3t9mbpb99roaq.cloudfront.net` |
| SSH | `ssh -i Deploy/ec2/.secrets/lts-api-edge.pem ubuntu@54.65.196.154` |

驗收：`/healthz`、`/docs`、`wss://…/ws`、地圖 HTTPS 皆 200／有 GNSS JSON。  
Mac 需保持 Docker compose 與 NetBird 連線；睡眠會導致 API 502。

---

## Phase 1 — 本機 API（已可重跑）

於專案根目錄：

```bash
docker compose -f docker/docker-compose.yml up --build -d
curl -fsS http://127.0.0.1:8000/healthz
# → {"status":"ok","host":"lts-api.personalwork.tw"}
```

- Swagger：http://localhost:8000/docs  
- WebSocket：`ws://127.0.0.1:8000/ws`（約 5Hz GNSS JSON）  
- CORS 已含 `https://lts-map.personalwork.tw`（見 compose）

> 在本機 curl **自己的** NetBird IP 可能因 userspace hairpin 逾時；請從其他 peer（如 EC2）驗證 `http://tazs-m1pro.netbird.cloud:8000/healthz`。

---

## Phase 2 — EC2 公網入口

目錄：[`ec2/`](./ec2/)

1. AWS SSO 登入後：
   ```bash
   export AWS_REGION=ap-northeast-1
   export KEY_NAME=<你的 EC2 key pair 名稱>
   bash Deploy/ec2/provision-ec2.sh
   ```
2. DNS **A 記錄**：`lts-api.personalwork.tw` → 腳本印出的 **EIP**
3. SSH 上去後複製 `Caddyfile` + `bootstrap.sh`：
   ```bash
   export NETBIRD_SETUP_KEY=<NetBird setup key>
   sudo bash bootstrap.sh
   ```
4. 確認：
   ```bash
   curl -fsS http://tazs-m1pro.netbird.cloud:8000/healthz   # 從 EC2
   curl -fsS https://lts-api.personalwork.tw/healthz
   curl -fsS -o /dev/null -w '%{http_code}\n' https://lts-api.personalwork.tw/docs
   ```

Security Group：入站 TCP 80／443（與可選 UDP 51820）；NetBird ACL 允許 EC2 → Mac `:8000`。

---

## Phase 3 — 前端 S3 + CloudFront

目錄：[`frontend/`](./frontend/)

```bash
# 1) ACM（us-east-1）+ 依提示加 DNS 驗證 CNAME
bash Deploy/frontend/request-acm.sh
aws acm wait certificate-validated --region us-east-1 --certificate-arn "$ACM_CERT_ARN"

# 2) S3 + CloudFront OAC + SPA fallback
export ACM_CERT_ARN=...
bash Deploy/frontend/provision-cloudfront.sh

# 3) DNS CNAME：lts-map.personalwork.tw → dxxxx.cloudfront.net

# 4) 建置並上傳
export S3_BUCKET=...
export CF_DISTRIBUTION_ID=...
bash Deploy/frontend/deploy.sh
```

詳細說明見 [`frontend/cloudfront-s3.md`](./frontend/cloudfront-s3.md)。

---

## Phase 4 — 驗收清單

| 檢查 | 預期 |
|------|------|
| `https://lts-map.personalwork.tw` | 地圖載入 |
| `https://lts-api.personalwork.tw/docs` | Swagger |
| `https://lts-api.personalwork.tw/healthz` | 200 |
| 地圖 → `wss://lts-api…/ws` | 路徑即時繪製 |
| Mac 睡眠 | API 中斷（預期）；醒來後恢復 |

---

## 檔案一覽

| 路徑 | 用途 |
|------|------|
| `ec2/Caddyfile` | TLS 反代到 NetBird peer |
| `ec2/bootstrap.sh` | EC2 安裝 Caddy + NetBird |
| `ec2/provision-ec2.sh` | 建立 EC2／SG／EIP |
| `frontend/request-acm.sh` | 申請 CloudFront 用 ACM |
| `frontend/provision-cloudfront.sh` | S3 + CloudFront |
| `frontend/deploy.sh` | `npm run build` → S3 sync → invalidate |
| `frontend/cloudfront-s3.md` | 手冊 |
