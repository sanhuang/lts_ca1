"""GNSS_data / data_transfer_formatting：WebSocket JSON 契約（對齊前端）。"""

from datetime import datetime, timezone
from typing import Any, Literal

from pydantic import BaseModel, Field


class GnssFixMessage(BaseModel):
    """
    Roadmap `[GNSS_data]`：由 sensor_msgs/NavSatFix 轉出的前端可用結構。

    前端地圖路徑僅必讀 latitude / longitude；其餘為選填擴充欄位。
    """

    latitude: float
    longitude: float
    altitude: float | None = None
    status: int | None = None
    timestamp: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    frame_id: str | None = None


class WsEnvelope(BaseModel):
    """
    Roadmap `[data_transfer_formatting]`：WebSocket 外層信封。

    實際推送：`{ "type": "gnss_fix", "data": { latitude, longitude, ... } }`
    """

    type: Literal["gnss_fix", "heartbeat", "status"] = "gnss_fix"
    data: GnssFixMessage | dict[str, Any] | None = None


# Roadmap 符號別名
GNSS_data = GnssFixMessage
data_transfer_formatting = WsEnvelope
