"""ROS 執行緒 ↔ asyncio 之間的記憶體佇列（熱路徑）。"""

from __future__ import annotations

import asyncio
import queue
from typing import Any


class MemoryBridgeQueue:
    """
    熱路徑緩衝：
    - 生產端（rclpy callback / 任意執行緒）用 put_threadsafe
    - 消費端（asyncio）用 get
    """

    def __init__(self, maxsize: int = 256) -> None:
        self._sync_q: queue.Queue[Any] = queue.Queue(maxsize=maxsize)
        self._loop: asyncio.AbstractEventLoop | None = None
        self._async_q: asyncio.Queue[Any] | None = None

    def bind_loop(self, loop: asyncio.AbstractEventLoop) -> None:
        self._loop = loop
        self._async_q = asyncio.Queue(maxsize=self._sync_q.maxsize)

    def put_threadsafe(self, item: Any) -> None:
        """由 ROS spin 執行緒呼叫；若已 bind_loop 則轉進 asyncio.Queue。"""
        if self._loop is None or self._async_q is None:
            try:
                self._sync_q.put_nowait(item)
            except queue.Full:
                try:
                    self._sync_q.get_nowait()
                except queue.Empty:
                    pass
                self._sync_q.put_nowait(item)
            return

        def _enqueue() -> None:
            assert self._async_q is not None
            if self._async_q.full():
                try:
                    self._async_q.get_nowait()
                except asyncio.QueueEmpty:
                    pass
            self._async_q.put_nowait(item)

        self._loop.call_soon_threadsafe(_enqueue)

    async def get(self) -> Any:
        if self._async_q is not None:
            return await self._async_q.get()
        while True:
            try:
                return self._sync_q.get_nowait()
            except queue.Empty:
                await asyncio.sleep(0.01)
