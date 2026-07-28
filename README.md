# ROS 2 + Web 實時路徑監控系統

---

## Items
1. 任務目標
   - 開發一個端到端的監控系統，將 ROS 2 模擬產生的 GNSS 數據，透過後端橋接器即時推送到前端網頁儀表板，並在地圖上繪製路徑。
2. 自行產出 GPS 檔案
   - path_data.csv: 包含一系列的 GPS 座標點（Latitude, Longitude）。
3. 詳細需求
    3.1. GNSS Publisher (ROS 2)
        - 功能： 撰寫一個 ROS 2 Node (C++ or **Python**)。
        - 讀取： 讀取提供的 GPS 路徑檔案。
        - 發佈： 以固定頻率（5Hz）循環發佈 sensor_msgs/msg/NavSatFix 訊息至 Topic /gps/fix。
    3.2. Backend Bridge (FastAPI)
        - 功能： 建立一個 FastAPI 應用程式作為 ROS 2 與 Web 的橋樑。
        - 訂閱： 訂閱 ROS 2 的 /gps/fix Topic。
        - 轉換： 將接收到的 ROS 2 訊息轉換為 JSON 格式。
        - 發佈： 建立 WebSocket 端點，將即時座標數據推送至前端。
3.3. Frontend View (Vue 3)
        - 功能： 使用 Vue 3 建立應用頁面。
        - 通訊： 連接後端 WebSocket 獲取即時數據。
        - 地圖呈現： 整合地圖庫（如 OpenStreetMap）。
            在圖標上**標註當前位置**，並**繪製**出無人載具走過的**歷史路徑線段**。
3.4. 容器化與部署 (Docker)
        - 獨立鏡像： 為 Publisher、 Backend、 Frontend 分別撰寫 Dockerfile。
        - 一鍵啟動： 撰寫 docker-compose.yml，確保使用者執行 docker-compose up 後，系統能自動完成所有網路設定並正常運作。

### Option for DevOps
4. 請設計一套CI/CD Pipeline，由船廠的研發團隊部署到遠端的艦隊並符合下列要求，用文字+圖表答即可。
    - Quality
    - Security
    - Safety
    - AI導入
5. 請設計雲端地端的系統設計/網路架構，符合下列要求，主要服務有Nginx, AP, DB及其它應下列要求所需的軟硬體。
    - 網路分區與存取控制
    - HA設計
    - 資安的defense in depth

## Roadmap

1. 掌握領域關鍵字
   1. ROS 2 模擬產生的 GNSS(衛星GPS):以前法騰做過timeprovidor設備收容
   2. ROS 2 產出**固定頻率（5Hz）循環** -> 推估資料量
   3. python ROS2套件或者C++套件以cpython呼叫？
   4. 後端橋接器即時推送: ROS2
      1. FastAPI作為中介層: 如何接收ROS2？
      2. FastAPI轉websocket server？
   5. OpenStreetMap套件前端應用
   6. 雲端地端的系統設計
      1. 哪些上雲？哪些地端？
         1. 我的分析：通常DB會在地端內網，限制API接口來源白名單、AP在雲，僅限需提供介面操作, websocket接入地端ws server
      2. AP做HA -> cluster, DB做HA -> PostgreSQL(mm模式)??或者etcd切換
      3. 生成meraid架構圖描述資料流與[png]系統元件架構圖
2. 個人化技能, 建立專案架構
   1. pydantic資料模型：
      1. [GNSS_data]
      2. [data_transfer_formatting]
      3. [GPS_path_data]
   2. Dockerfile
      1. Publisher(ROS2模擬)
      2. Backend(接收與發送)
      3. Frontend
   3. API
      1. 發佈 sensor_msgs/msg/NavSatFix -> **Topic** /gps/fix
      2.
3. 根據需求技術套件選型： 處理訂閱(RebbitMQ/Redis), python ROS2套件

---

## 網域與用途

| 網域 | 用途 |
|------|------|
| `lts-map.personalwork.tw` | 前端地圖（Vue 3 `dist`／CloudFront → S3） |
| `lts-api.personalwork.tw` | FastAPI Bridge（REST、**Swagger**、**WebSocket** `/ws`） |
| `lts-rosdebug.personalwork.tw` | ROS 2 GNSS Publisher（模擬節點；對外僅供維運／除錯時慎開） |

### 還需要其他網域嗎？

**核心三服務：以上三個已足夠。** WebSocket 建議直接掛在 `lts-api`（`wss://lts-api.personalwork.tw/ws`），不必再拆 `lts-ws`。

| 項目 | 建議 |
|------|------|
| Redis／RabbitMQ／DB | **不要**公開網域，僅內網／compose／VPN |
| Swagger | 用 `https://lts-api.personalwork.tw/docs` 即可，無需獨立網域 |
| ROS Publisher | 生產宜內網；`lts-rosdebug` 若曝光公網需 IP 白名單或 VPN／Netbird |
| 選配（非必須） | Container Registry、監控（Grafana）、CI 頁面——有正式維運再加子網域 |

前端建置請設：`VITE_WS_URL=wss://lts-api.personalwork.tw/ws`（見 `Frontend/README.md`）。

---

## Docker 使用說明

Dockerfile 與 Compose 位於 [`docker/`](./docker/)。**請在專案根目錄**執行下列指令（build context 為 `.`）。

| 檔案 | 服務 |
|------|------|
| `docker/Dockerfile.ros2` | GNSS Publisher（`ROS2/`） |
| `docker/Dockerfile.fastapi` | FastAPI Bridge（`Backend/`） |
| `docker/Dockerfile.vue3` | Vue 3 地圖（`Frontend/` → nginx） |
| `docker/docker-compose.yml` | 三服務一鍵啟動 |

### 一鍵啟動（建議）

```bash
# 建置並啟動 Publisher + Backend + Frontend
docker compose -f docker/docker-compose.yml up --build

# 背景執行
docker compose -f docker/docker-compose.yml up --build -d

# 查看日誌 / 停止
docker compose -f docker/docker-compose.yml logs -f
docker compose -f docker/docker-compose.yml down
```

啟動後本機位址：

| 服務 | URL |
|------|-----|
| 地圖 | http://localhost:8080 |
| API／Swagger | http://localhost:8000/docs |
| WebSocket | ws://localhost:8000/ws |

三容器共用 `ltsnet`、`ROS_DOMAIN_ID=0`：Publisher → `/gps/fix` → Backend → 前端 WS。

### 單獨 docker build

```bash
# Publisher
docker build -f docker/Dockerfile.ros2 -t lts-rosnode .

# Backend（FastAPI + rclpy）
docker build -f docker/Dockerfile.fastapi -t lts-api .

# Frontend（正式網域 WS）
docker build -f docker/Dockerfile.vue3 \
  --build-arg VITE_WS_URL=wss://lts-api.personalwork.tw/ws \
  --build-arg VITE_APP_ORIGIN=https://lts-map.personalwork.tw \
  -t lts-map .

# 本機預覽用 WS（對應 compose 映射埠）
docker build -f docker/Dockerfile.vue3 \
  --build-arg VITE_WS_URL=ws://localhost:8000/ws \
  --build-arg VITE_APP_ORIGIN=http://localhost:8080 \
  -t lts-map:local .
```

### 單獨執行已建置映像（可選）

```bash
docker run --rm --network lts_ca1_ltsnet -e ROS_DOMAIN_ID=0 lts-rosnode
docker run --rm -p 8000:8000 --network lts_ca1_ltsnet -e ROS_DOMAIN_ID=0 lts-api
docker run --rm -p 8080:80 lts-map:local
```

> 網路名稱以 `docker network ls` 為準（compose 專案前綴可能不同）。日常開發優先用 `docker compose ... up`。  
> 更完整說明見 [`docker/README.md`](./docker/README.md)。
