# Cursor 問答紀錄 — ROS 2 + Web 實時路徑監控系統

> 來源：依 `README.md` 面試 sideproject 需求整理的領域關鍵字說明與初步需求分析。

---

## 一、領域關鍵字說明（建議寫入 `knowadges.md`）

### 1. ROS 2（Robot Operating System 2）

機器人中介軟體，用 **Node / Topic / Message** 做分散式通訊。本專案用 ROS 2 Node 模擬 GNSS 資料來源，對外發佈標準訊息，不必接真機 GPS。

### 2. GNSS / GPS / NavSatFix

- **GNSS**：全球衛星導航系統總稱（GPS、北斗、Galileo 等）。
- **GPS**：GNSS 的一種；題目用 GPS 座標（Latitude, Longitude）。
- **`sensor_msgs/msg/NavSatFix`**：ROS 標準訊息，含緯度、經度、海拔、狀態與協方差等，本專案發佈到 `/gps/fix`。

### 3. Topic / Publisher / Subscriber

- **Topic**：具名資料通道（此處 `/gps/fix`）。
- **Publisher**：GNSS Node，以 **5Hz** 循環發佈。
- **Subscriber**：Backend Bridge 訂閱同一 Topic，再轉成 Web 可用格式。

### 4. 5Hz 固定頻率與資料量粗估

5Hz = 每秒 5 筆。單筆 NavSatFix 轉 JSON 粗估約 100–300 bytes。

| 時長 | 筆數 | 約流量（單連線） |
|------|------|------------------|
| 1 秒 | 5 | ~0.5–1.5 KB/s |
| 1 分 | 300 | ~30–90 KB |
| 1 小時 | 18,000 | ~2–5 MB |

面試可強調：頻率不高、即時性重於吞吐，WebSocket 推送足夠；瓶頸多在 ROS↔Web 橋接與前端地圖重繪。

### 5. rclpy / rclcpp（ROS 2 Client Library）

- **rclpy**：Python 綁定，上手快，適合面試 demo。
- **rclcpp**：C++，效能較好。

### 6. ROS–Web Bridge（後端橋接器）

ROS 2 與瀏覽器協定不同（DDS vs HTTP/WS）。Backend 負責：訂閱 ROS → 轉 JSON → 經 WebSocket 推前端。常見做法：

- FastAPI 進程內嵌 `rclpy` Node（同容器/同網路）
- 或透過 `rosbridge` / 中介 MQ（題目指定 FastAPI，優先進程內訂閱）

資料流示意（擴充／對照用；題目優先仍為進程內 `rclpy`）：

```text
方案1: rosbridge
================

  [path_data.csv]
         |
         v
  [ROS2 GNSS Publisher] ----NavSatFix@5Hz----> /gps/fix
                                                    |
                                                    v
                                            [rosbridge_suite]
                                            (ROS <-> JSON/WS)
                                                    |
                          websocket (rosbridge 協定) |
                                                    v
                                            [FastAPI 轉發/適配]
                                            (可薄可厚)
                                                    |
                                      JSON / 自訂 WS |
                                                    v
                                            [Vue3 + OSM]


方案2: 中介 MQ（Redis / RabbitMQ）
==================================

  [path_data.csv]
         |
         v
  [ROS2 GNSS Publisher] ----NavSatFix@5Hz----> /gps/fix
                                                    |
                                                    v
                                        [ROS→MQ 轉發服務]
                                        (rclpy subscribe
                                         後 publish 到 MQ)
                                                    |
                                         GNSS JSON  |
                                                    v
                                      +---------------------+
                                      |  Redis / RabbitMQ   |
                                      +---------------------+
                                           |           |
                              Pub/Sub 或    |           |  任務佇列
                              Stream 消費   |           |  (選配 Celery)
                                           v           v
                                    [FastAPI Bridge]  [Worker]
                                    訂閱 MQ → WS推送   寫DB/告警
                                           |
                                           v
                                    [Vue3 + OSM]
```

### 7. FastAPI + WebSocket

- **FastAPI**：Python ASGI Web 框架。
- **WebSocket**：全雙工長連線，適合 5Hz 推流。
- 流程：訂閱 `/gps/fix` → 轉 JSON → `ws` 廣播給已連線前端。

### 8. Vue 3 + OpenStreetMap（OSM）

- **Vue 3**：前端 SPA。
- **OSM**：開源地圖圖資；前端常用 **Leaflet** 或 **MapLibre** 疊加標記與折線。
- 需求重點：**當前位置標記** + **歷史路徑 Polyline**。

### 9. Docker / docker-compose

三服務各一 Dockerfile（Publisher、Backend、Frontend），`docker-compose up` 一鍵啟動並處理網路（例如共用 bridge network，Backend 能連到 ROS DDS/Discovery）。

### 10. Option：雲地、HA、Defense in Depth（加分題）

- **雲地混合**：即時控制/感測多在地端（船/車）；雲端偏監控、設定、歷史、CI/CD。
- **HA**：AP 多副本 + LB；DB 主從或叢集。
- **Defense in Depth**：分區（DMZ/內網）、白名單、TLS、最小權限、WAF、網路隔離層層防護。
- **CI/CD Quality / Security / Safety / AI**：測試與靜態分析、掃描與簽章、安全變更門檻、AI 輔助審查（非取代人工）。

### 11. 資料模型關鍵字（Roadmap）

建議用 Pydantic 分層：

- **GNSS_data**：對應 NavSatFix 欄位
- **GPS_path_data**：CSV 路徑點
- **data_transfer_formatting**：WebSocket JSON schema（前端契約）

### 12. 中介層選型備註

Roadmap 提到 RabbitMQ/Redis：**核心題不強制**。5Hz、單 Topic 時，FastAPI 直接訂閱 ROS 即可；MQ 較適合多消費者、斷線緩衝、跨主機解耦——面試可當「擴展方案」說明。

---

## 二、初步需求分析

### 1. 專案目標（一句話）

端到端演示：**ROS 2 模擬 GNSS → FastAPI 橋接 → Vue 地圖即時路徑**，並以 Docker Compose 可重現部署。

### 2. 功能需求（Must / Should / Could）

| 優先級 | 需求 | 說明 |
|--------|------|------|
| Must | 自產 `path_data.csv` | Lat/Lon 序列 |
| Must | GNSS Publisher | 讀 CSV，5Hz 發 `NavSatFix` 到 `/gps/fix` |
| Must | Backend Bridge | 訂閱 Topic → JSON → WebSocket |
| Must | Frontend | WS 連線；地圖上當前點 + 歷史軌跡 |
| Must | 三服務 Docker + compose | `docker-compose up` 可跑 |
| Should | 斷線重連 / 連線狀態 UI | 面試加分 |
| Should | 固定 JSON schema（Pydantic） | 前後端契約清楚 |
| Could | 路徑重播控制（暫停/速率） | 超出最小題面 |
| Option | CI/CD 設計（文字+圖） | Quality/Security/Safety/AI |
| Option | 雲地架構圖 | 分區、HA、縱深防禦 |

### 3. 系統邊界與資料流

```
[path_data.csv]
      ↓
[ROS2 GNSS Publisher] --NavSatFix@5Hz--> /gps/fix
      ↓ (subscribe)
[FastAPI Bridge] --JSON@WebSocket--> [Vue3 + OSM Map]
      ↑
[Docker Compose 網路與一鍵啟動]
```

**系統內**：Publisher、Backend、Frontend、CSV、Compose。
**系統外（可不做）**：真 GNSS 硬體、持久化 DB、認證、多載具——Option 架構題可文字設計。

### 4. 非功能需求（面試常問）

| 面向 | 初步定義 |
|------|----------|
| 即時性 | 端到端延遲目標可訂 < 200–500ms（演示級） |
| 頻率 | 固定 5Hz；前端可節流重繪避免卡頓 |
| 可重現 | 單一 `docker-compose up` |
| 可觀測 | 日誌能看出發佈/訂閱/WS 推送 |
| 擴展（Option） | 多艦隊、雲監控、HA、資安分層 |

### 5. 技術選型建議（對齊 Roadmap）

| 層 | 建議 | 理由 |
|----|------|------|
| Publisher | Python + `rclpy` | 與 FastAPI 同語言、交付快 |
| Backend | FastAPI + 內嵌 rclpy | 符合題目，少一層依賴 |
| 資料契約 | Pydantic | 對齊個人化技能 |
| Frontend | Vue 3 + Leaflet + OSM tiles | 輕、常見、夠畫軌跡 |
| 部署 | 三 Dockerfile + compose | 題目硬性要求 |
| MQ | 首版不做 | 需求未要求；當演進方案即可 |

### 6. 風險與面試可講點

1. **ROS 2 在 Docker 的 Discovery**：多容器 DDS 需注意網路/RMW；可講 `ROS_DOMAIN_ID`、host network 或同 compose network。
2. **FastAPI 與 rclpy 同進程**：asyncio 與 ROS spin 執行緒模型要講清楚（背景 thread spin + WS broadcast）。
3. **CSV 循環發佈**：檔案結束後 loop；地圖路徑是「累積」還是「每圈清空」需自行定義並寫進需求。
4. **地圖座標**：WGS84 lat/lon 與 OSM 一致，通常無需投影轉換。
5. **Option 題**：核心 demo 與架構敘事分開；架構圖強調資料流、信任邊界、HA 與 Safety（船用/車用變更管制）。

### 7. 建議交付切片（MVP → 加分）

1. CSV + Publisher 單獨驗證 `ros2 topic echo /gps/fix`
2. Backend 訂閱並列印 / 簡單 WS
3. Vue 地圖接 WS 畫點與線
4. Docker 化三服務
5. （時間允許）CI/CD + 雲地架構文件與圖

---

## 三、寫入 `knowadges.md` 的建議大綱

```markdown
# Knowledges — ROS2 + Web 即時路徑監控

## 領域關鍵字
### ROS 2 / Topic / NavSatFix / 5Hz ...
### FastAPI Bridge / WebSocket ...
### Vue3 / OSM / Leaflet ...
### Docker Compose / DDS Discovery ...
###（Option）雲地 / HA / Defense in Depth / CI/CD 四面向

## 資料量估算
## 技術選型決策紀錄
## 待釐清問題
- 路徑循環時前端是否清空歷史線段？
- ROS 映像與 RMW 選擇（Fast DDS / Cyclone）？
```

---

## 四、後續可延伸

- 將上述關鍵字正式整理進 `knowadges.md`
- Option：CI/CD 與雲地架構拆成「面試口述稿 + 圖表文字稿」
