"""rclpy 訂閱 /gps/fix → MemoryBridgeQueue（骨架；需 ROS 2 環境）。"""

from __future__ import annotations

import logging
import threading
from typing import TYPE_CHECKING, Any, Callable

if TYPE_CHECKING:
    from app.queues.memory import MemoryBridgeQueue

logger = logging.getLogger(__name__)


class GpsFixSubscriber:
    """
    進程內嵌 ROS 2 Node。
    實際 rclpy import 延遲到 start()，以便無 ROS 時仍可載入 FastAPI 骨架。
    """

    def __init__(
        self,
        topic: str,
        bridge_queue: MemoryBridgeQueue,
        *,
        on_message: Callable[[dict[str, Any]], None] | None = None,
    ) -> None:
        self.topic = topic
        self.bridge_queue = bridge_queue
        self.on_message = on_message
        self._node: Any = None
        self._rclpy: Any = None

    def start(self) -> None:
        try:
            import rclpy
            from rclpy.node import Node
            from sensor_msgs.msg import NavSatFix
        except ImportError as exc:
            raise RuntimeError(
                "rclpy / sensor_msgs 未安裝。請在 ROS 2 映像內執行，"
                "或先用 mock 模式開發 HTTP/WS。"
            ) from exc

        self._rclpy = rclpy
        if not rclpy.ok():
            rclpy.init()

        parent = self

        class _Node(Node):
            def __init__(self) -> None:
                super().__init__("lts_gps_bridge")
                self.create_subscription(NavSatFix, parent.topic, self._cb, 10)

            def _cb(self, msg: Any) -> None:
                payload = {
                    "latitude": float(msg.latitude),
                    "longitude": float(msg.longitude),
                    "altitude": float(msg.altitude),
                    "status": int(msg.status.status) if msg.status else None,
                    "frame_id": getattr(msg.header, "frame_id", None),
                }
                parent.bridge_queue.put_threadsafe(payload)
                if parent.on_message:
                    parent.on_message(payload)

        self._node = _Node()
        logger.info("ROS subscriber started on %s", self.topic)

    def spin(self) -> None:
        assert self._rclpy is not None and self._node is not None
        self._rclpy.spin(self._node)

    def stop(self) -> None:
        if self._node is not None:
            self._node.destroy_node()
            self._node = None
        if self._rclpy is not None and self._rclpy.ok():
            self._rclpy.shutdown()


def start_subscriber_thread(subscriber: GpsFixSubscriber) -> threading.Thread:
    subscriber.start()
    thread = threading.Thread(target=subscriber.spin, name="rclpy-spin", daemon=True)
    thread.start()
    return thread
