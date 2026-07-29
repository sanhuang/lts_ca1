#!/usr/bin/env python3
"""讀取 path_data.csv，以固定頻率發佈 sensor_msgs/NavSatFix → /gps/fix。"""

from __future__ import annotations

import csv
import math
import os
import random
from pathlib import Path

import rclpy
from rclpy.node import Node
from sensor_msgs.msg import NavSatFix, NavSatStatus
from std_msgs.msg import Header


# 與 Backend GPS_path_data / GpsPathPoint 欄位約定一致（不依賴 pydantic）
REQUIRED_CSV_HEADERS = frozenset({"latitude", "longitude"})


def load_points(csv_path: Path) -> list[tuple[float, float]]:
    points: list[tuple[float, float]] = []
    with csv_path.open(newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        headers = set(reader.fieldnames or ())
        missing = REQUIRED_CSV_HEADERS - headers
        if missing:
            raise SystemExit(
                f"CSV missing required headers {sorted(REQUIRED_CSV_HEADERS)}; "
                f"missing={sorted(missing)} in {csv_path}"
            )
        for row in reader:
            points.append((float(row["latitude"]), float(row["longitude"])))
    if not points:
        raise SystemExit(f"no points in {csv_path}")
    return points


def meters_to_deg(north_m: float, east_m: float, lat: float) -> tuple[float, float]:
    dlat = north_m / 111_320.0
    dlon = east_m / (111_320.0 * max(0.2, math.cos(math.radians(lat))))
    return dlat, dlon


class GpsPublisher(Node):
    def __init__(
        self,
        points: list[tuple[float, float]],
        topic: str,
        rate_hz: float,
        *,
        jitter_m: float = 0.0,
    ) -> None:
        super().__init__("lts_gps_publisher")
        self._points = points
        self._idx = 0
        self._jitter_m = max(0.0, jitter_m)
        self._pub = self.create_publisher(NavSatFix, topic, 10)
        period = 1.0 / rate_hz
        self.create_timer(period, self._tick)
        self.get_logger().info(
            f"publishing {len(points)} points on {topic} @ {rate_hz} Hz"
            + (f"; jitter≈{self._jitter_m:.1f}m" if self._jitter_m else "")
        )

    def _tick(self) -> None:
        lat, lon = self._points[self._idx]
        self._idx = (self._idx + 1) % len(self._points)
        if self._jitter_m > 0:
            # 均勻圓盤雜訊，模擬 GNSS 微小抖動（非改變航跡形狀）
            ang = random.uniform(0.0, 2.0 * math.pi)
            rad = self._jitter_m * math.sqrt(random.random())
            dlat, dlon = meters_to_deg(rad * math.cos(ang), rad * math.sin(ang), lat)
            lat += dlat
            lon += dlon
        msg = NavSatFix()
        msg.header = Header()
        msg.header.stamp = self.get_clock().now().to_msg()
        msg.header.frame_id = "gps"
        msg.status.status = NavSatStatus.STATUS_FIX
        msg.status.service = NavSatStatus.SERVICE_GPS
        msg.latitude = lat
        msg.longitude = lon
        msg.altitude = 0.0
        msg.position_covariance_type = NavSatFix.COVARIANCE_TYPE_UNKNOWN
        self._pub.publish(msg)


def main() -> None:
    csv_path = Path(os.environ.get("GPS_CSV", "/app/path_data.csv"))
    topic = os.environ.get("ROS_TOPIC", "/gps/fix")
    rate_hz = float(os.environ.get("PUBLISH_RATE_HZ", "5.0"))
    # 預設 1.5m；設 GPS_JITTER_M=0 可關閉
    jitter_m = float(os.environ.get("GPS_JITTER_M", "1.5"))
    points = load_points(csv_path)

    rclpy.init()
    node = GpsPublisher(points, topic, rate_hz, jitter_m=jitter_m)
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == "__main__":
    main()
