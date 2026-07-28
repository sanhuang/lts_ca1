# Backend — Python 3.13 FastAPI / WebSocket

> 正式後端網域：**`https://lts-api.personalwork.tw`**  
> - REST／Swagger：`https://lts-api.personalwork.tw/docs`  
> - WebSocket：`wss://lts-api.personalwork.tw/ws`  
> 訂閱 ROS 2 `/gps/fix` → JSON → 推送前端（`lts-map.personalwork.tw`）

**現行策略：** 僅用進程內 **Python `queue`／`asyncio.Queue`** 做熱路徑緩衝；**不含 Celery／Redis**（擴充見 `more.md`）。

---

## 專案骨架

```text
Backend/
  app/
    __init__.py
    main.py                 # FastAPI 入口：lifespan、健康檢查、掛載 WS
    settings.py             # pydantic-settings（網域、Topic、WS path、CORS）
    ros_sub.py              # rclpy Node：訂閱 /gps/fix → queue_mem
    queue_mem.py            # 熱路徑：queue.Queue / asyncio.Queue
    ws_hub.py               # WebSocket 連線集合與 broadcast
    schemas/                # 維持套件：契約可給日後 Celery Worker 共用
      __init__.py
      gnss.py               # GNSS_data / WS 傳輸契約（Pydantic）
  requirements.txt
  more.md                   # （文件）日後 Celery + Redis／RabbitMQ 擴充
  more_case.md              # （文件）可延後／可重試情境
  README.md
  .env.example
```

### 目錄職責

| 路徑 | 職責 |
|------|------|
| `main.py` | HTTP + `/ws`；啟動／關閉時起停 ROS subscriber |
| `ros_sub.py` | DDS 訂閱，執行緒內 `spin`，`put_threadsafe` 進佇列 |
| `queue_mem.py` | `queue.Queue`／`asyncio.Queue`：ROS 執行緒 → 事件迴圈 |
| `ws_hub.py` | 對瀏覽器 5Hz 廣播 |
| `schemas/` | JSON 契約（獨立保留，利於日後 tasks 共用） |

---

## 資料流

```text
/gps/fix  →  ros_sub  →  queue_mem  →  ws_hub  →  wss://lts-api…/ws
           (rclpy thread) (python queue) (asyncio)
```

---

## 環境變數（見 `.env.example`）

| 變數 | 範例 | 說明 |
|------|------|------|
| `APP_PUBLIC_HOST` | `lts-api.personalwork.tw` | 對外主機名 |
| `WS_PATH` | `/ws` | WebSocket 路徑 |
| `ROS_TOPIC` | `/gps/fix` | GNSS Topic |
| `CORS_ORIGINS` | `https://lts-map.personalwork.tw` | 允許的前端來源 |

---

## 相關文件

- 日後佇列擴充（非現行）：`more.md` / `more_case.md`
- 前端網域與 WS：`../Frontend/README.md`
- 雲地架構：`../DevOps/archit.md`
