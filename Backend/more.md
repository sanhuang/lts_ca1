# Backend 擴充項目 — Celery + Redis／RabbitMQ

> 對應 `requirements.txt` 選配：
>
> ```text
> # redis>=5.0.0          # Pub/Sub 或 Streams：跨進程解耦、短暫斷線緩衝
> # # aio-pika / pika     # 若改 RabbitMQ 再選用
> ```
>
> 本文說明：**何時**從現行「進程內 Python Queue」升級，以及以 **Celery 搭配 Redis／RabbitMQ** 的開發步驟與優勢。

---

## 1. 現行作法（對照基線）

首版 Bridge 建議：

```text
rclpy callback  →  queue.Queue / asyncio.Queue  →  FastAPI WebSocket 廣播
```

| 元件 | 角色 |
|------|------|
| `queue.Queue` | 執行緒安全：ROS spin 執行緒 → 主事件迴圈 |
| `asyncio.Queue` | 協程間緩衝：讀取後 `broadcast` 給各 WS |

**特點：** 零額外套件、延遲低、同進程即可跑通 5Hz demo。  
**上限：** 無法跨進程／跨主機；進程重啟佇列清空；難做多消費者、重試、持久化任務。

---

## 2. 擴充目標：Celery + Broker（Redis 或 RabbitMQ）

把「可延後、可重試、可水平擴展」的工作從即時 WS 熱路徑拆出：

```text
                    ┌─ 熱路徑（仍建議進程內 Queue / 或 Redis Pub/Sub）─→ WebSocket
/gps/fix → Bridge ─┤
                    └─ 冷／旁路路徑 → Celery Task → Redis/RabbitMQ → Worker
                                              ├─ 寫入 PostgreSQL 軌跡
                                              ├─ 告警／超速判斷
                                              ├─ 匯總上雲
                                              └─ 多載具後處理
```

> **重要區分：** Celery 擅長**任務佇列**（at-least-once、重試、排程），不適合取代 5Hz 低延遲 WS 推流。  
> 即時座標仍用 Python Queue（單進程）或 **Redis Pub/Sub／Streams**（多進程扇出）；Celery 處理擴充業務。

---

## 3. 對比：Python Queue vs Celery + Redis／RabbitMQ

| 面向 | 現行 `queue`／`asyncio.Queue` | Celery + Redis／RabbitMQ |
|------|------------------------------|---------------------------|
| 部署複雜度 | 低，隨 AP 進程即可 | 需 Broker + Worker 容器 |
| 延遲 | 極低（記憶體） | 毫秒～數十毫秒級；不適熱路徑 |
| 進程重啟 | 佇列資料遺失 | Broker 可持久化訊息（視設定） |
| 跨進程／主機 | 否 | 是 |
| 多消費者 | 手動扇出 | Worker 水平擴展、任務路由 |
| 重試／死信 | 需自寫 | 內建 retry、ack、可接 DLQ（RabbitMQ 更完整） |
| 監控 | 自建 | Flower／Broker 儀表、任務狀態 |
| 適用 | MVP、同容器 Bridge | 持久化、告警、匯總、多載具後處理 |
| 與 HA | 主備切換時記憶體佇列丟 | Standby 升主後 Worker 仍吃同一 Broker |

### 優勢摘要（相對直接 Python Queue）

1. **解耦：** 訂閱 ROS 的 AP 不必承擔寫 DB／跑重邏輯；失敗不堵 WS。  
2. **可靠投遞：** 任務可持久化、重試、逾時；符合「軌跡不能默默丟」的產品化需求。  
3. **水平擴展：** 加 Celery Worker 即可消化多載具寫入峰值，無需加厚單一 FastAPI 進程。  
4. **HA 友善：** Bridge Active／Standby 切換時，未完成任務仍在 Redis／RabbitMQ，Worker 繼續消費。  
5. **可觀測：** 任務成功／失敗／耗時可查，面試可對齊 DevOps Quality／Safety 稽核。  
6. **Broker 可選：** 輕量用 **Redis**；要路由鍵、ACK、DLQ 更強用 **RabbitMQ**（`aio-pika`／`pika` 偏原生 AMQP；Celery 則統一用 Celery API）。

### 何時**不要**上 Celery

- 僅單車、5Hz、無 DB／無告警的面試 MVP。  
- 把每筆 GNSS **同步**塞進 Celery 再推 WS（多餘延遲與複雜度）。

---

## 4. Broker 怎麼選（對應 requirements 註解）

| Broker | 啟用套件方向 | 適合 |
|--------|--------------|------|
| **Redis** | `redis` + Celery `broker_url=redis://...` | 開發快、扇出與簡易任務佇列；亦可另開 Pub/Sub 給多 Bridge |
| **RabbitMQ** | Celery + AMQP URL；除錯／非 Celery 客戶端可用 `pika`／`aio-pika` | 企業路由、持久佇列、DLQ、多團隊共用匯流排 |

建議演進：

1. 先 **Redis**（一個服務兼 Broker；必要時同一 Redis 做 Pub/Sub）。  
2. 任務契約變複雜、要 DLQ／細路由再遷 **RabbitMQ**。

---

## 5. 開發步驟（Celery + Redis 為主路徑）

### Step 0 — 決策與範圍

- [ ] 確認熱路徑仍為：ROS →（進程內 Queue）→ WebSocket。  
- [ ] 列出進 Celery 的任務：例如 `persist_gnss_point`、`evaluate_geofence`、`enqueue_cloud_sync`。  
- [ ] 決定 Broker：預設 Redis。

### Step 1 — 依賴啟用

在 `requirements.txt` 取消註解並補齊（範例）：

```text
redis>=5.0.0
celery[redis]>=5.4.0,<6.0.0
# 若改 RabbitMQ：
# celery[librabbitmq] 或僅 amqp:// 即可；除錯可用 pika / aio-pika
```

本地／compose 增加服務：`redis`（或 `rabbitmq:3-management`）、`worker`。

### Step 2 — 設定（pydantic-settings）

```text
CELERY_BROKER_URL=redis://redis:6379/0
CELERY_RESULT_BACKEND=redis://redis:6379/1   # 可選；不需查結果可省略
GNSS_TASK_QUEUE=gnss.persist
```

### Step 3 — 專案骨架

```text
Backend/
  app/
    main.py              # FastAPI + rclpy + WS
    settings.py
    queues/
      memory.py          # 現行 asyncio/queue（熱路徑）
    celery_app.py        # Celery 實例
    tasks/
      gnss.py            # persist / alert 等
    schemas/             # Pydantic GNSS JSON
  more.md
  requirements.txt
```

### Step 4 — 定義 Celery App 與 Task

1. `celery_app.py`：`Celery("backend_bridge", broker=..., include=["app.tasks.gnss"])`  
2. `tasks/gnss.py`：`@app.task(bind=True, max_retries=3, autoretry_for=(...))`  
3. Task 入參用 **可序列化 dict**（Pydantic `.model_dump()`），避免直接傳 ROS msg 物件。  
4. 冪等：以 `(vehicle_id, timestamp_ns)` 當唯一鍵，避免 Active／Standby 切換重複寫入。

### Step 5 — 在 Bridge 熱路徑「非阻塞投遞」

在 rclpy／Queue 消費迴圈中：

1. 驗證 JSON（Pydantic）。  
2. `await broadcast(ws_clients, payload)` — 即時。  
3. `persist_gnss_point.delay(payload)` — 立刻返回，不 await 寫 DB。  

原則：**Celery 失敗不得中斷 WS。**

### Step 6 — Worker 進程

```bash
celery -A app.celery_app.celery worker -Q gnss.persist -l info -c 2
```

Docker Compose 範例角色：

| Service | 指令 |
|---------|------|
| `backend` | uvicorn（含 ROS subscribe） |
| `redis` | redis:7 |
| `worker` | celery worker |
| （可選）`flower` | 任務監控 UI |

### Step 7 — 可靠性與背壓

- [ ] 設定 `task_acks_late=True`、適當 `visibility`／prefetch，避免 Worker crash 丟任務。  
- [ ] 限制 Queue 長度或丟棄策略：DB 慢時優先保 WS，次要任務可降採樣（例如 5Hz 寫入改 1Hz）。  
- [ ] 死信／失敗告警：Redis 可另開 failed list；RabbitMQ 用 DLX。  
- [ ] 逾時：`task_time_limit` 防止卡住佔滿 concurrency。

### Step 8 — 驗證清單

| 測試 | 預期 |
|------|------|
| 僅起 backend、停 worker | 地圖仍即時更新；任務堆積在 Broker |
| 再起 worker | 堆積任務消化，DB 追上 |
| kill 單一 worker | 其他 worker 或重啟後續跑（at-least-once → 靠冪等） |
| broker 短暫斷線 | Celery 重連；Bridge 日誌警告但不死 |

### Step 9 —（可選）改 RabbitMQ

1. compose 加 `rabbitmq`，`CELERY_BROKER_URL=amqp://user:pass@rabbitmq:5672//`  
2. 宣告 durable queue、必要時 DLX。  
3. 非 Celery 服務若要直接吃同一匯流排，再用 `pika`／`aio-pika`（與 requirements 註解對齊）。  
4. 回歸跑 Step 8。

### Step 10 —（可選）Redis 同時做多進程 WS 扇出

若多個 Bridge 實例都要推同一座標：

- 一實例訂 ROS → `PUBLISH gnss.live`  
- 各實例訂閱後推自己的 WS 客戶端  

此路徑用 **`redis` Pub/Sub 或 Streams**，**不必**經 Celery。Celery 仍只負責 persist／alert。

---

## 6. 建議的資料流（擴充後完整圖）

```mermaid
flowchart LR
  Pub[ROS Publisher] --> Topic[/gps/fix/]
  Topic --> Bridge[FastAPI + rclpy]
  Bridge --> MemQ[asyncio / queue.Queue]
  MemQ --> WS[WebSocket 客戶端]
  Bridge --> CeleryProd[Celery .delay]
  CeleryProd --> Broker[(Redis 或 RabbitMQ)]
  Broker --> Worker[Celery Worker]
  Worker --> DB[(PostgreSQL)]
  Worker --> Alert[告警／匯總]
```

---

## 7. 與 DevOps／HA 文件的對齊

| 文件 | 關聯 |
|------|------|
| `DevOps/Advance.md` | DB 異步寫入、多載具後處理 → 用 Celery 落地 |
| `DevOps/archit.md` | Broker／Worker 放 App 區；Broker 憑證與網路分區 |
| 現行 MVP | 不啟用本擴充；保留 `requirements.txt` 註解即可 |

---

## 8. 實作優先級建議

| 優先級 | 項目 |
|--------|------|
| P0 | 進程內 Queue + WS（現行） |
| P1 | Redis + Celery 寫軌跡／冪等 |
| P2 | Flower、降採樣、失敗告警 |
| P3 | 遷 RabbitMQ；Redis Pub/Sub 多 Bridge 扇出 |

---

## 9. 一句話收束

> Python Queue 把 ROS 執行緒安全接到 WebSocket；Celery + Redis／RabbitMQ 則在**不拖慢 5Hz 熱路徑**的前提下，提供跨進程、可重試、可擴展的旁路任務能力——這正是 `requirements.txt` 將 `redis`／`pika` 列為選配的原因。  
