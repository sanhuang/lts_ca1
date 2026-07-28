"""GNSS / WebSocket JSON 契約（對齊前端與 NavSatFix 精簡欄位）。"""

from datetime import datetime, timezone
from typing import Literal

from pydantic import BaseModel, Field


class GnssFixMessage(BaseModel):
    """由 sensor_msgs/NavSatFix 轉出的前端可用結構。"""

    latitude: float
    longitude: float
    altitude: float | None = None
    status: int | None = None
    timestamp: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    frame_id: str | None = None


class WsEnvelope(BaseModel):
    """WebSocket 外層信封，便於前端分辨訊息類型。"""

    type: Literal["gnss_fix", "heartbeat", "status"] = "gnss_fix"
    data: GnssFixMessage | dict | None = None
