"""FastAPI 入口：健康檢查、WebSocket、ROS → Python queue → 廣播。"""

from __future__ import annotations

import asyncio
import logging
from contextlib import asynccontextmanager
from typing import Any

from fastapi import FastAPI, WebSocket
from fastapi.middleware.cors import CORSMiddleware

from app.queue_mem import MemoryBridgeQueue
from app.schemas.gnss import GnssFixMessage, WsEnvelope
from app.settings import get_settings
from app.ws_hub import WsHub

logger = logging.getLogger(__name__)
settings = get_settings()

bridge_queue = MemoryBridgeQueue()
ws_hub = WsHub()
_pump_task: asyncio.Task[None] | None = None
_ros_thread: Any = None


async def _pump_queue_to_ws() -> None:
    """消費 Python queue → Pydantic 驗證 → WebSocket 廣播。"""
    while True:
        raw = await bridge_queue.get()
        try:
            fix = GnssFixMessage.model_validate(raw)
            envelope = WsEnvelope(type="gnss_fix", data=fix)
            await ws_hub.broadcast_json(envelope.model_dump(mode="json"))
        except Exception:
            logger.exception("failed to handle gnss payload: %s", raw)


@asynccontextmanager
async def lifespan(app: FastAPI):
    global _pump_task, _ros_thread
    loop = asyncio.get_running_loop()
    bridge_queue.bind_loop(loop)
    _pump_task = asyncio.create_task(_pump_queue_to_ws(), name="gnss-ws-pump")

    # ROS 訂閱：無 rclpy 時僅記錄警告，HTTP/WS 骨架仍可啟動（方便前端聯調）
    try:
        from app.ros_sub import GpsFixSubscriber, start_subscriber_thread

        subscriber = GpsFixSubscriber(settings.ros_topic, bridge_queue)
        _ros_thread = start_subscriber_thread(subscriber)
        app.state.gps_subscriber = subscriber
    except Exception as exc:
        logger.warning("ROS subscriber not started: %s", exc)
        app.state.gps_subscriber = None

    yield

    if _pump_task:
        _pump_task.cancel()
        try:
            await _pump_task
        except asyncio.CancelledError:
            pass
    sub = getattr(app.state, "gps_subscriber", None)
    if sub is not None:
        try:
            sub.stop()
        except Exception:
            logger.exception("error stopping ROS subscriber")


app = FastAPI(
    title=settings.app_name,
    version="0.1.0",
    lifespan=lifespan,
    docs_url="/docs",
    redoc_url="/redoc",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origin_list,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/healthz")
def healthz() -> dict[str, str]:
    return {"status": "ok", "host": settings.app_public_host}


@app.get("/")
def root() -> dict[str, str]:
    return {
        "service": settings.app_name,
        "docs": "/docs",
        "ws": settings.ws_path,
        "public_host": settings.app_public_host,
    }


@app.websocket(settings.ws_path)
async def websocket_endpoint(websocket: WebSocket) -> None:
    await ws_hub.connect(websocket)
    await ws_hub.client_loop(websocket)
