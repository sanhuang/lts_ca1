"""GPS_path_data：CSV 模擬路徑點契約（對齊 ROS2/path_data.csv）。"""

from __future__ import annotations

import csv
from pathlib import Path
from typing import Iterable

from pydantic import BaseModel, Field

REQUIRED_CSV_HEADERS: frozenset[str] = frozenset({"latitude", "longitude"})


class GpsPathPoint(BaseModel):
    """單一路徑點（latitude / longitude）。"""

    latitude: float
    longitude: float


class GpsPathData(BaseModel):
    """
    Roadmap `[GPS_path_data]`：整條模擬路徑。
    與 Publisher 讀取的 CSV 欄位約定一致。
    """

    points: list[GpsPathPoint] = Field(min_length=1)

    @classmethod
    def from_csv(cls, csv_path: Path | str) -> GpsPathData:
        path = Path(csv_path)
        with path.open(newline="", encoding="utf-8") as f:
            reader = csv.DictReader(f)
            cls.require_headers(reader.fieldnames)
            points = [
                GpsPathPoint(
                    latitude=float(row["latitude"]),
                    longitude=float(row["longitude"]),
                )
                for row in reader
            ]
        if not points:
            raise ValueError(f"no points in {path}")
        return cls(points=points)

    @classmethod
    def from_rows(cls, rows: Iterable[dict[str, str | float]]) -> GpsPathData:
        return cls(
            points=[
                GpsPathPoint(
                    latitude=float(row["latitude"]),
                    longitude=float(row["longitude"]),
                )
                for row in rows
            ]
        )

    @staticmethod
    def require_headers(fieldnames: Iterable[str] | None) -> None:
        """輕量表頭檢查：Publisher 可不依賴 pydantic 而複用同一契約。"""
        headers = set(fieldnames or ())
        missing = REQUIRED_CSV_HEADERS - headers
        if missing:
            raise ValueError(
                f"CSV missing required headers {sorted(REQUIRED_CSV_HEADERS)}; "
                f"missing={sorted(missing)}"
            )


# Roadmap 符號別名
GPS_path_data = GpsPathData
