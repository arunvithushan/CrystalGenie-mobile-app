"""Tiny in-memory sliding-window rate limiter (per process) for auth endpoints.

Good enough for a single uvicorn worker in development/small deployments. For multiple
workers put the API behind a reverse proxy with rate limiting, or use Redis.
"""
from __future__ import annotations

import threading
import time
from collections import defaultdict, deque

from fastapi import Request

from app.core.errors import AppError


class RateLimiter:
    def __init__(self, max_calls: int, window_seconds: float):
        self.max_calls, self.window = max_calls, window_seconds
        self._hits: dict[str, deque] = defaultdict(deque)
        self._lock = threading.Lock()

    def hit(self, key: str) -> None:
        now = time.monotonic()
        with self._lock:
            q = self._hits[key]
            while q and now - q[0] > self.window:
                q.popleft()
            if len(q) >= self.max_calls:
                retry = int(self.window - (now - q[0])) + 1
                raise AppError(429, "rate_limited", "Too many attempts. Please wait and try again.",
                               headers={"Retry-After": str(retry)})
            q.append(now)

    def reset(self) -> None:
        with self._lock:
            self._hits.clear()


login_limiter = RateLimiter(max_calls=10, window_seconds=60)
sensitive_limiter = RateLimiter(max_calls=5, window_seconds=300)


def client_ip(request: Request) -> str:
    return request.client.host if request.client else "unknown"
