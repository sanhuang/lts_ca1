# LTS_CA1 — 於專案根目錄操作 docker/docker-compose.yml
COMPOSE_FILE := docker/docker-compose.yml
COMPOSE      := docker compose -f $(COMPOSE_FILE)

.PHONY: help up up-d down build logs ps restart stop

help: ## 顯示可用目標
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

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
