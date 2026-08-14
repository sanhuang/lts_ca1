# ROS 2 在本專案的用途與操作摘要

## 1. ROS 2 要解決什麼需求

依 `README.md` 需求 **3.1 GNSS Publisher**：

1. 撰寫一個 ROS 2 Node（本專案：Python / `rclpy`）
2. 讀取自行產出的 `path_data.csv`（Latitude, Longitude）
3. 以固定頻率 **5Hz** 循環發佈 `sensor_msgs/msg/NavSatFix` 至 Topic **`/gps/fix`**

ROS 2 在此系統中扮演「模擬 GNSS 資料來源」，是端到端監控鏈的第一段；後續 FastAPI Bridge、Vue 3 地圖皆依賴這段穩定可重複的假 GPS 流。

## 2. 怎麼用 ROS 2 達成

核心實作：`ROS2/gps_publisher.py`

| 需求 | ROS 2 做法 |
|------|------------|
| 模擬 GNSS | 不接真機，用 CSV 路徑點當航跡 |
| 固定 5Hz | `create_timer(1/5)`；可用 `PUBLISH_RATE_HZ` 覆寫 |
| 標準訊息 | 發佈 `NavSatFix`（lat/lon、status、header） |
| Topic 契約 | 預設 `/gps/fix`，Backend 訂閱同一 Topic |
| 循環路徑 | index 取模，走完從頭，路徑可持續繪製 |

可調環境變數：`GPS_CSV`、`ROS_TOPIC`、`PUBLISH_RATE_HZ`、`ROS_DOMAIN_ID`。

### 整條資料鏈

```text
path_data.csv
    ↓
ROS 2 Publisher（5Hz NavSatFix）
    ↓  Topic /gps/fix（DDS，同 ROS_DOMAIN_ID）
FastAPI Bridge（rclpy 訂閱 → JSON）
    ↓  WebSocket /ws
Vue 3 地圖（當前位置 + 歷史路徑）
```

瀏覽器不直接碰 ROS；Backend 在同一 Docker 網路（`ltsnet`）且 `ROS_DOMAIN_ID=0` 下用 `rclpy` 訂閱後轉 JSON。

### 一鍵啟動

```bash
docker compose -f docker/docker-compose.yml up --build
```

ROS 映像：`docker/Dockerfile.ros2`（基底 `ros:humble-ros-base`）。

**一句話：** ROS 2 = 用標準 GNSS Topic 模擬無人載具移動；CSV 當路徑、5Hz `NavSatFix` 當即時餵料。

## 3. 是否可用 ROS 2 自帶指令取代自寫 Node？

**不行（至少不符本題）。** ROS 2 **沒有**官方內建「讀 `path_data.csv` → 5Hz 循環發 `NavSatFix` 到 `/gps/fix`」的套件指令。

| 工具 | 能做什麼 | 符不符本題 |
|------|----------|------------|
| `ros2 topic pub` | 往 Topic 塞單筆／固定訊息 | 可發 `NavSatFix`，不適合讀整條 CSV、循環路徑 |
| `ros2 bag play` | 重播事先錄好的 bag | 可模擬串流，但 bag 需另產，且非「寫 Node 讀檔」 |
| `sensor_msgs` | 只提供 `NavSatFix` 訊息型別 | 不負責產生座標 |

生態系另有真機驅動（如 NMEA）、Gazebo GPS plugin、自錄 bag 等，皆非題目指定解。  
作業要求讀自有 CSV、5Hz、循環發佈 → 最直接是自寫 Publisher Node（本專案 `gps_publisher.py`）。

## 4. `Dockerfile.ros2` 容器內可用指令與用途

### 映像組成

- 基底：`ros:humble-ros-base`（Humble）
- 額外安裝：`python3-pip`、`ros-humble-sensor-msgs`
- Entrypoint：`source /opt/ros/${ROS_DISTRO}/setup.bash` 後執行 CMD
- 預設 CMD：`python3 /app/gps_publisher.py`

### 進入容器

```bash
docker run --rm -it --entrypoint /entrypoint.sh lts-rosnode bash

# 或 compose 已在跑時
docker exec -it <ros_container> bash
source /opt/ros/humble/setup.bash   # exec 進去不一定走過 entrypoint
```

### 本專案相關

| 指令 / 路徑 | 用途 |
|-------------|------|
| `python3 /app/gps_publisher.py` | 預設入口：讀 CSV、5Hz 發 `/gps/fix` |
| `cat /app/path_data.csv` | 查看模擬路徑座標 |
| `echo $PUBLISH_RATE_HZ` 等 | 檢視 `GPS_CSV`、`ROS_TOPIC`、`ROS_DOMAIN_ID` |
| `python3 -c "import rclpy; from sensor_msgs.msg import NavSatFix"` | 確認 rclpy / NavSatFix 可用 |
| `pip3` | 必要時安裝額外 Python 套件 |

### ROS 2 CLI（本題最常用）

| 指令 | 用途 |
|------|------|
| `ros2 topic list` | 確認是否有 `/gps/fix` |
| `ros2 topic echo /gps/fix` | 印出即時 NavSatFix |
| `ros2 topic hz /gps/fix` | 驗證約 5Hz |
| `ros2 topic info /gps/fix` | Publisher / Subscriber 與型別 |
| `ros2 topic type /gps/fix` | 應為 `sensor_msgs/msg/NavSatFix` |
| `ros2 topic bw /gps/fix` | 粗看頻寬 |
| `ros2 topic pub ...` | 手動塞假座標（測 Backend） |
| `ros2 node list` | 應見 `lts_gps_publisher` |
| `ros2 node info /lts_gps_publisher` | 該 Node 發佈的 Topic |
| `ros2 interface show sensor_msgs/msg/NavSatFix` | 查欄位定義 |
| `ros2 interface proto sensor_msgs/msg/NavSatFix` | `topic pub` 範本 |
| `ros2 doctor` | 環境 / DDS 健康檢查 |
| `ros2 pkg list` / `ros2 pkg prefix sensor_msgs` | 已安裝套件與路徑 |

其餘如 `ros2 service`、`ros2 action`、`ros2 param`、`ros2 run`、`ros2 launch` 視 base 映像內套件而定。

### 系統層

| 指令 | 用途 |
|------|------|
| `bash` / `sh` | 互動 shell |
| `env` / `printenv` | 檢視 ROS_* 與本題環境變數 |
| `ls`、`cat`、`head`、`grep`、`ps`、`kill` | 查檔、查進程 |
| `apt-get`（root） | 臨時加套件（執行中改動不會進映像） |

### 預設沒有

`ros-base` 不含：`rviz2`、`rqt*`、`ros-humble-desktop`、Gazebo、NMEA 等 driver。  
`ros2 bag` 是否完整可用取決於該 tag 是否帶 `rosbag2` 相關套件。

### 最短除錯路徑

```bash
source /opt/ros/humble/setup.bash
ros2 topic list
ros2 topic hz /gps/fix
ros2 topic echo /gps/fix --once
```

同網路且 `ROS_DOMAIN_ID=0` 下，能看到約 5Hz 與 lat/lon，即代表模擬 GNSS 符合需求。
