# LTS_CA1 — 於專案根目錄操作 docker/docker-compose.yml
COMPOSE_FILE := docker/docker-compose.yml
COMPOSE      := docker compose -f $(COMPOSE_FILE)

FRONTEND_DIR  := Frontend
VITE_WS_URL   ?= ws://localhost:8000/ws
FRONTEND_PORT ?= 8080
# 可覆寫：make frontend VITE_INIT_LAT=25.0330 VITE_INIT_LON=121.5654
VITE_INIT_LAT ?= 25.0330
VITE_INIT_LON ?= 121.5654
VITE_INIT_ZOOM ?= 16

.PHONY: help up up-d down build logs ps restart stop \
	frontend vue-build vue-preview

help: ## 顯示可用目標
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

up: ## 建置並前景啟動（Publisher + Backend + Frontend）
	$(COMPOSE) up --build

up-d: ## 建置並背景啟動
	$(COMPOSE) up --build -d

down: ## 停止並移除容器
	$(COMPOSE) down

build: ## 僅建置映像（不啟動）
	$(COMPOSE) build

logs: ## 追蹤全部服務日誌
	$(COMPOSE) logs -f

ps: ## 查看服務狀態
	$(COMPOSE) ps

restart: ## 重啟全部服務
	$(COMPOSE) restart

stop: ## 停止服務（保留容器）
	$(COMPOSE) stop

# --- 本機 Vue dist（不經 Docker；WS 預設連 localhost:8000）---

vue-build: ## 安裝依賴並產出 Frontend/dist
	cd $(FRONTEND_DIR) && npm install && \
		VITE_WS_URL=$(VITE_WS_URL) \
		VITE_INIT_LAT=$(VITE_INIT_LAT) \
		VITE_INIT_LON=$(VITE_INIT_LON) \
		VITE_INIT_ZOOM=$(VITE_INIT_ZOOM) \
		npm run build

vue-preview: ## 服務既有 dist（需先 vue-build）
	cd $(FRONTEND_DIR) && npx vite preview --host --port $(FRONTEND_PORT)

frontend: vue-build ## 建置 dist 並本機啟動（http://localhost:8080）
	cd $(FRONTEND_DIR) && npx vite preview --host --port $(FRONTEND_PORT)
