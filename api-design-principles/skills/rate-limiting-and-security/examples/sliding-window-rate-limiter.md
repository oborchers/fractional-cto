# Sliding Window Rate Limiter

Complete sliding window rate limiter backed by Redis. Returns rate limit headers on every response and a structured 429 when the limit is exceeded. Includes per-key tracking and configurable window size.

## How the Sliding Window Counter Works

```
Window: 1 minute, Limit: 100

Previous window (0:00-1:00): 84 requests
Current window  (1:00-2:00): 36 requests so far

Current time: 1:15 (25% into current window)
Weight of previous window: 75% (remaining portion)

Estimated count: (84 * 0.75) + 36 = 63 + 36 = 99
-> Under limit (100). Allow request.
```

Two Redis keys per client per window. No per-request timestamp storage. Accurate enough for production use — this is the algorithm most APIs rely on.

## Node.js / Express

```ts
import { Router, Request, Response, NextFunction } from "express";
import Redis from "ioredis";

const redis = new Redis(process.env.REDIS_URL);

interface RateLimitConfig {
  windowMs: number;     // Window size in milliseconds
  maxRequests: number;  // Maximum requests per window
}

interface RateLimitResult {
  allowed: boolean;
  limit: number;
  remaining: number;
  resetAt: number;      // Unix timestamp (seconds)
  retryAfter: number;   // Seconds until reset
}

async function checkRateLimit(
  key: string,
  config: RateLimitConfig
): Promise<RateLimitResult> {
  const now = Date.now();
  const windowMs = config.windowMs;
  const windowStart = Math.floor(now / windowMs) * windowMs;
  const previousWindowStart = windowStart - windowMs;
  const elapsedInWindow = (now - windowStart) / windowMs; // 0.0 to 1.0

  const currentKey = `ratelimit:${key}:${windowStart}`;
  const previousKey = `ratelimit:${key}:${previousWindowStart}`;

  // Fetch both window counts and increment current in one round trip
  const pipeline = redis.pipeline();
  pipeline.get(previousKey);
  pipeline.incr(currentKey);
  pipeline.pexpire(currentKey, windowMs * 2); // Expire after 2 windows
  const results = await pipeline.exec();

  const previousCount = parseInt((results![0][1] as string) || "0", 10);
  const currentCount = parseInt((results![1][1] as string) || "1", 10);

  // Sliding window estimate
  const previousWeight = 1 - elapsedInWindow;
  const estimatedCount =
    Math.floor(previousCount * previousWeight) + currentCount;

  const resetAt = Math.ceil((windowStart + windowMs) / 1000);
  const retryAfter = Math.max(
    0,
    Math.ceil((windowStart + windowMs - now) / 1000)
  );

  return {
    allowed: estimatedCount <= config.maxRequests,
    limit: config.maxRequests,
    remaining: Math.max(0, config.maxRequests - estimatedCount),
    resetAt,
    retryAfter,
  };
}

function rateLimiter(config: RateLimitConfig) {
  return async (req: Request, res: Response, next: NextFunction) => {
    // Key by API key if present, otherwise by IP
    const key =
      req.headers["x-api-key"]?.toString() ||
      req.ip ||
      "unknown";

    const result = await checkRateLimit(key, config);

    // Always set rate limit headers — not just on 429
    res.set("X-RateLimit-Limit", String(result.limit));
    res.set("X-RateLimit-Remaining", String(result.remaining));
    res.set("X-RateLimit-Reset", String(result.resetAt));

    if (!result.allowed) {
      res.set("Retry-After", String(result.retryAfter));
      return res.status(429).json({
        error: {
          type: "rate_limit_error",
          code: "rate_limit_exceeded",
          message: `Rate limit exceeded. Please retry after ${result.retryAfter} seconds.`,
          retry_after: result.retryAfter,
          limit: result.limit,
          remaining: 0,
          reset_at: new Date(result.resetAt * 1000).toISOString(),
        },
      });
    }

    next();
  };
}

// --- Usage ---

const app = Router();

// Global rate limit: 100 requests per minute
app.use(rateLimiter({ windowMs: 60_000, maxRequests: 100 }));

// Stricter limit for expensive endpoints
app.post(
  "/api/v1/exports",
  rateLimiter({ windowMs: 60_000, maxRequests: 5 }),
  (req, res) => {
    res.json({ status: "export_started" });
  }
);

// Standard endpoint inherits global limit
app.get("/api/v1/users", (req, res) => {
  res.json({ data: [] });
});

export { rateLimiter, checkRateLimit };
```

## Python / FastAPI

```python
import time
import math
from typing import Optional

import redis.asyncio as redis
from fastapi import FastAPI, Request, Response
from fastapi.responses import JSONResponse
from starlette.middleware.base import BaseHTTPMiddleware

pool = redis.from_url("redis://localhost:6379", decode_responses=True)


class RateLimitResult:
    __slots__ = ("allowed", "limit", "remaining", "reset_at", "retry_after")

    def __init__(
        self,
        allowed: bool,
        limit: int,
        remaining: int,
        reset_at: int,
        retry_after: int,
    ):
        self.allowed = allowed
        self.limit = limit
        self.remaining = remaining
        self.reset_at = reset_at
        self.retry_after = retry_after


async def check_rate_limit(
    key: str,
    window_seconds: int,
    max_requests: int,
) -> RateLimitResult:
    now = time.time()
    window_ms = window_seconds * 1000
    now_ms = int(now * 1000)
    window_start = (now_ms // window_ms) * window_ms
    previous_window_start = window_start - window_ms
    elapsed_in_window = (now_ms - window_start) / window_ms  # 0.0 to 1.0

    current_key = f"ratelimit:{key}:{window_start}"
    previous_key = f"ratelimit:{key}:{previous_window_start}"

    # Fetch both windows and increment current in one round trip
    async with pool.pipeline(transaction=False) as pipe:
        pipe.get(previous_key)
        pipe.incr(current_key)
        pipe.pexpire(current_key, window_ms * 2)
        results = await pipe.execute()

    previous_count = int(results[0] or 0)
    current_count = int(results[1] or 1)

    # Sliding window estimate
    previous_weight = 1 - elapsed_in_window
    estimated_count = math.floor(previous_count * previous_weight) + current_count

    reset_at = math.ceil((window_start + window_ms) / 1000)
    retry_after = max(0, math.ceil((window_start + window_ms - now_ms) / 1000))

    return RateLimitResult(
        allowed=estimated_count <= max_requests,
        limit=max_requests,
        remaining=max(0, max_requests - estimated_count),
        reset_at=reset_at,
        retry_after=retry_after,
    )


def _get_client_key(request: Request) -> str:
    """Extract rate limit key from API key header or client IP."""
    api_key = request.headers.get("x-api-key")
    if api_key:
        return api_key
    return request.client.host if request.client else "unknown"


class RateLimitMiddleware(BaseHTTPMiddleware):
    """Global sliding window rate limiter applied to all routes."""

    def __init__(self, app, window_seconds: int = 60, max_requests: int = 100):
        super().__init__(app)
        self.window_seconds = window_seconds
        self.max_requests = max_requests

    async def dispatch(self, request: Request, call_next):
        key = _get_client_key(request)
        result = await check_rate_limit(
            key, self.window_seconds, self.max_requests
        )

        if not result.allowed:
            return JSONResponse(
                status_code=429,
                headers={
                    "X-RateLimit-Limit": str(result.limit),
                    "X-RateLimit-Remaining": "0",
                    "X-RateLimit-Reset": str(result.reset_at),
                    "Retry-After": str(result.retry_after),
                },
                content={
                    "error": {
                        "type": "rate_limit_error",
                        "code": "rate_limit_exceeded",
                        "message": (
                            f"Rate limit exceeded. "
                            f"Please retry after {result.retry_after} seconds."
                        ),
                        "retry_after": result.retry_after,
                        "limit": result.limit,
                        "remaining": 0,
                        "reset_at": time.strftime(
                            "%Y-%m-%dT%H:%M:%SZ", time.gmtime(result.reset_at)
                        ),
                    }
                },
            )

        response = await call_next(request)

        # Always set rate limit headers — not just on 429
        response.headers["X-RateLimit-Limit"] = str(result.limit)
        response.headers["X-RateLimit-Remaining"] = str(result.remaining)
        response.headers["X-RateLimit-Reset"] = str(result.reset_at)

        return response


# --- Usage ---

app = FastAPI()

# Global rate limit: 100 requests per minute
app.add_middleware(RateLimitMiddleware, window_seconds=60, max_requests=100)


# Per-endpoint stricter limit using a dependency
from fastapi import Depends, HTTPException


def rate_limit_dependency(window_seconds: int, max_requests: int):
    """FastAPI dependency for per-endpoint rate limiting."""

    async def _check(request: Request):
        key = f"{_get_client_key(request)}:{request.url.path}"
        result = await check_rate_limit(key, window_seconds, max_requests)
        if not result.allowed:
            raise HTTPException(
                status_code=429,
                detail={
                    "type": "rate_limit_error",
                    "code": "rate_limit_exceeded",
                    "message": (
                        f"Rate limit exceeded. "
                        f"Please retry after {result.retry_after} seconds."
                    ),
                    "retry_after": result.retry_after,
                },
                headers={"Retry-After": str(result.retry_after)},
            )

    return Depends(_check)


@app.post(
    "/api/v1/exports",
    dependencies=[rate_limit_dependency(window_seconds=60, max_requests=5)],
)
async def create_export():
    return {"status": "export_started"}


@app.get("/api/v1/users")
async def list_users():
    return {"data": []}
```

## Key Points

- Rate limit headers appear on every response, not just 429s — clients must see their remaining budget before they exhaust it
- The sliding window estimate uses two Redis counters per window, avoiding per-request timestamp storage
- Redis pipeline batches the GET + INCR + PEXPIRE into a single round trip for minimal latency
- Keys expire after two window periods, so Redis does not accumulate stale data
- The client key falls back from API key to IP address, covering both authenticated and unauthenticated requests
- Per-endpoint limits (e.g., 5 req/min for exports) layer on top of the global limit
- The 429 response body includes `retry_after`, `limit`, `remaining`, and `reset_at` so clients can implement automatic backoff without parsing headers
