# Docker 映像與一鍵啟動

| 檔案 | 對應服務 | 建議網域 |
|------|----------|----------|
| `Dockerfile.ros2` | GNSS Publisher | `lts-rosnode.personalwork.tw`（除錯） |
| `Dockerfile.fastapi` | FastAPI Bridge | `lts-api.personalwork.tw` |
| `Dockerfile.vue3` | Vue 3 地圖 | `lts-map.personalwork.tw` |

## 啟動

於**專案根目錄**：

```bash
docker compose -f docker/docker-compose.yml up --build
```

| 服務 | 本機位址 |
|------|----------|
| 地圖 | http://localhost:8080 |
| API／Swagger | http://localhost:8000/docs |
| WebSocket | ws://localhost:8000/ws |

三容器共用 `ltsnet` 與 `ROS_DOMAIN_ID=0`，Publisher → `/gps/fix` → Backend。

## 建置單一映像

```bash
docker build -f docker/Dockerfile.ros2 -t lts-rosnode .
docker build -f docker/Dockerfile.fastapi -t lts-api .
docker build -f docker/Dockerfile.vue3 \
  --build-arg VITE_WS_URL=wss://lts-api.personalwork.tw/ws \
  -t lts-map .
```
