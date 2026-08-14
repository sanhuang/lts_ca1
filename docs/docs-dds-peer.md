# Fast DDS peer 設定與 hostdds 備援

> 對應 Items 3.4：讓 Publisher ↔ Backend 在 Docker 裡透過 ROS 2／DDS 一定能互通。
> 本文件只談：**① Fast DDS peer（主路徑）**、**③ hostdds profile（備援）**；不含 `.dockerignore`、一般 compose 小調。

---

## 一句話目標

```text
publisher（ROS 發 /gps/fix）──DDS──▶ backend（rclpy）──WS──▶ frontend（地圖）
```

DDS discovery 失敗時，healthz／Swagger 可能仍正常，但地圖無軌跡。

---

## ROS／DDS 名詞（非無人機專屬）

| 名稱 | 是什麼 | 白話 |
|------|--------|------|
| `ROS_DOMAIN_ID` | ROS 2 環境變數 | 通訊「房間號」；相同才互通。`0` 為常見預設。 |
| `RMW_IMPLEMENTATION` | ROS 2 環境變數 | 指定底層 RMW（ROS Middleware）實作。 |
| `rmw_fastrtps_cpp` | RMW 套件名 | 使用 **eProsima Fast DDS** 當通訊後端。 |

```text
ROS 2 Topic → RMW（由 RMW_IMPLEMENTATION 決定）→ DDS 實作（此處 Fast DDS）
```

另有 `rmw_cyclonedds_cpp` 等可替換；換實作時 Domain ID 兩邊仍須一致。

---

## DDS 與 Fast DDS：用 IT 術語比喻

| ROS／機器人側 | 近似 IT | 說明 |
|---------------|---------|------|
| **DDS** | 訊息匯流排**規格**（如 AMQP／MQTT 這類標準） | OMG 標準：發訂、QoS、發現；不是單一產品。 |
| **Fast DDS** | 某廠商的**實作**（如 RabbitMQ 之於 AMQP） | 可連結／運行的函式庫。 |
| **RMW** | 驅動／適配層（如 JDBC） | ROS 2 可插不同 DDS 後端。 |
| **Topic** | channel／subject | 邏輯通道名（如 `/gps/fix`）。 |
| **Pub／Sub** | Producer／Consumer | DDS 常偏 **peer-to-peer**，不一定有中央 Broker。 |
| **Discovery** | 服務發現 | 「網路上誰在發／聽這個 topic」。 |
| **ROS_DOMAIN_ID** | VLAN／獨立 namespace／房間號 | 不同 ID＝兩套互不看見的匯流排。 |
| **QoS** | 佇列深度、可靠投遞策略 | reliability、depth 等契約。 |

面試一句話：**ROS 管應用語意；DDS 是即時發訂規格；Fast DDS 是具體引擎。** 拓撲比 Kafka／Rabbit 更常去中心、偏本機／內網。本專案瀏覽器側仍走 WebSocket，DDS 只在 Publisher↔Backend。

---

## ① Fast DDS peer（主路徑）

**問題：** 預設 multicast discovery 在 Docker bridge（尤其 macOS）常失敗 → 尚未建立 DDS 配對。
**作法：** XML（如 `fastdds_discovery.xml`）用 **initial peers** 寫死連 `publisher`／`backend`；兩容器設 `FASTRTPS_DEFAULT_PROFILES_FILE`，維持同 `ROS_DOMAIN_ID`。frontend 不需 peer XML。

**不做會怎樣：** macOS 等高機率永遠收不到 `/gps/fix`；表象是地圖不動，易誤判成前端／WS 問題。

---

## ③ hostdds profile（備援）

**作法：** compose profile（如 `hostdds`）讓 publisher／backend 用 `network_mode: host`（DDS 近似本機兩行程）。**多半僅 Linux**；macOS 以 ① 為主。

**不做會怎樣：** ① 已通則幾乎無影響；① 仍失敗時沒有標準逃生口。優先序：先 ① → 再必要時開 ③。

---

## 擴充：同一地圖多台路徑

**不要**為多機再開不同 `ROS_DOMAIN_ID`（那是隔離，Backend 在 Domain 0 看不到 Domain 1）。

應：**同一網路 + 同一 Domain**，用不同 ROS Node，並以訊息內 **`node_id`／`frame_id`**（或不同 topic／namespace）區分；前端依 id 分轨跡。

| 問題 | 本質 | 方向 |
|------|------|------|
| Discovery 失敗 | 找不到對端 | peer／網路／同 Domain |
| 多台路徑 | 已互通，要辨識是誰 | 同 Domain + `node_id`／多 topic |

---

## 驗證與現況缺口

- `make up` 後：healthz OK、Backend 有座標進佇列、地圖 live。
- 缺口（實作前）：尚無 peer XML／`FASTRTPS_DEFAULT_PROFILES_FILE`、尚無 `hostdds` profile。
