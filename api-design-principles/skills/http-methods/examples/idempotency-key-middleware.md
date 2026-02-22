# Idempotency-Key Middleware

Middleware that intercepts POST requests carrying an `Idempotency-Key` header and prevents duplicate processing. If the server has already handled a request with that key, it returns the cached response without re-executing the handler. This pattern — pioneered by Stripe and now an IETF draft standard — makes POST safely retryable after network failures.

## Pseudocode

```
middleware IdempotencyKey(request, response, next):
    // Only apply to POST requests — GET, PUT, DELETE are already idempotent
    if request.method != "POST":
        return next()

    key = request.headers["Idempotency-Key"]
    if key is empty:
        return next()  // No key provided, process normally

    // Check if this key has been seen before
    cached = store.get(key)

    if cached exists:
        // Verify the request fingerprint matches (same path, same body hash)
        if cached.fingerprint != hash(request.path + request.body):
            return 422 error "Idempotency key reused with different parameters"

        // Return cached response without re-executing
        response.setHeader("Idempotent-Replayed", "true")
        return cached.status_code, cached.headers, cached.body

    // First time seeing this key — process the request
    result = next()

    // Cache the response, keyed by Idempotency-Key
    // TTL of 24 hours (Stripe's default)
    store.set(key, {
        fingerprint: hash(request.path + request.body),
        status_code: result.status,
        headers: result.headers,
        body: result.body,
    }, ttl=24_hours)

    return result
```

## Node.js (Express)

```javascript
import crypto from "crypto";
import express from "express";

const app = express();
app.use(express.json());

// In production, use Redis with TTL instead of an in-memory Map.
// Keys expire after 24 hours to match Stripe's behavior.
const idempotencyStore = new Map();

const IDEMPOTENCY_TTL_MS = 24 * 60 * 60 * 1000; // 24 hours

function fingerprint(req) {
  const payload = `${req.method}:${req.originalUrl}:${JSON.stringify(req.body)}`;
  return crypto.createHash("sha256").update(payload).digest("hex");
}

function idempotencyMiddleware(req, res, next) {
  // Only apply to POST — other methods are already idempotent by spec
  if (req.method !== "POST") {
    return next();
  }

  const key = req.headers["idempotency-key"];
  if (!key) {
    return next();
  }

  // Validate key format (UUID recommended)
  if (key.length > 255) {
    return res.status(400).json({
      error: {
        type: "invalid_request_error",
        message: "Idempotency-Key must be 255 characters or fewer.",
      },
    });
  }

  const requestFingerprint = fingerprint(req);
  const cached = idempotencyStore.get(key);

  if (cached) {
    // Key exists — check if the request matches
    if (cached.fingerprint !== requestFingerprint) {
      return res.status(422).json({
        error: {
          type: "idempotency_error",
          message:
            "Idempotency-Key has already been used with different request parameters.",
        },
      });
    }

    // Check expiration
    if (Date.now() > cached.expires_at) {
      idempotencyStore.delete(key);
      // Fall through to process normally
    } else {
      // Return cached response
      res.set("Idempotent-Replayed", "true");
      for (const [header, value] of Object.entries(cached.headers)) {
        res.set(header, value);
      }
      return res.status(cached.status_code).json(cached.body);
    }
  }

  // Intercept the response to cache it
  const originalJson = res.json.bind(res);
  res.json = (body) => {
    idempotencyStore.set(key, {
      fingerprint: requestFingerprint,
      status_code: res.statusCode,
      headers: {
        "content-type": "application/json",
        ...(res.getHeader("location")
          ? { location: res.getHeader("location") }
          : {}),
      },
      body,
      expires_at: Date.now() + IDEMPOTENCY_TTL_MS,
    });

    return originalJson(body);
  };

  next();
}

// Apply middleware globally
app.use(idempotencyMiddleware);

// Example: charge creation endpoint
app.post("/v1/charges", (req, res) => {
  const { amount, currency, customer_id } = req.body;

  // Simulate charge processing
  const charge = {
    id: `ch_${crypto.randomBytes(12).toString("base64url")}`,
    object: "charge",
    amount,
    currency,
    customer_id,
    status: "succeeded",
    created_at: new Date().toISOString(),
  };

  res.status(201).location(`/v1/charges/${charge.id}`).json(charge);
});

// Example: order creation endpoint
app.post("/orders", (req, res) => {
  const order = {
    id: `ord_${crypto.randomBytes(12).toString("base64url")}`,
    object: "order",
    ...req.body,
    status: "pending",
    created_at: new Date().toISOString(),
  };

  res.status(201).location(`/orders/${order.id}`).json(order);
});

app.listen(3000);
```

## Python (FastAPI)

```python
import hashlib
import json
import time
from datetime import datetime, timezone
from typing import Any
from uuid import uuid4

from fastapi import FastAPI, Request, Response
from fastapi.responses import JSONResponse
from starlette.middleware.base import BaseHTTPMiddleware

app = FastAPI()

# In production, use Redis with TTL instead of a dict.
idempotency_store: dict[str, dict[str, Any]] = {}

IDEMPOTENCY_TTL_SECONDS = 24 * 60 * 60  # 24 hours


def compute_fingerprint(method: str, path: str, body: bytes) -> str:
    payload = f"{method}:{path}:{body.decode()}"
    return hashlib.sha256(payload.encode()).hexdigest()


class IdempotencyMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        # Only apply to POST requests
        if request.method != "POST":
            return await call_next(request)

        key = request.headers.get("idempotency-key")
        if not key:
            return await call_next(request)

        # Validate key length
        if len(key) > 255:
            return JSONResponse(
                status_code=400,
                content={
                    "error": {
                        "type": "invalid_request_error",
                        "message": "Idempotency-Key must be 255 characters or fewer.",
                    }
                },
            )

        # Read body for fingerprinting
        body = await request.body()
        request_fingerprint = compute_fingerprint(
            request.method, request.url.path, body
        )

        cached = idempotency_store.get(key)

        if cached:
            # Check fingerprint mismatch
            if cached["fingerprint"] != request_fingerprint:
                return JSONResponse(
                    status_code=422,
                    content={
                        "error": {
                            "type": "idempotency_error",
                            "message": (
                                "Idempotency-Key has already been used "
                                "with different request parameters."
                            ),
                        }
                    },
                )

            # Check expiration
            if time.time() > cached["expires_at"]:
                del idempotency_store[key]
                # Fall through to process normally
            else:
                # Return cached response
                return JSONResponse(
                    status_code=cached["status_code"],
                    content=cached["body"],
                    headers={
                        **cached.get("headers", {}),
                        "Idempotent-Replayed": "true",
                    },
                )

        # Process the request
        response = await call_next(request)

        # Cache the response for successful POST requests
        if 200 <= response.status_code < 300:
            # Read response body
            response_body = b""
            async for chunk in response.body_iterator:
                response_body += chunk if isinstance(chunk, bytes) else chunk.encode()

            try:
                body_json = json.loads(response_body)
            except json.JSONDecodeError:
                body_json = None

            # Collect headers to cache
            cached_headers = {}
            if "location" in response.headers:
                cached_headers["location"] = response.headers["location"]

            idempotency_store[key] = {
                "fingerprint": request_fingerprint,
                "status_code": response.status_code,
                "body": body_json,
                "headers": cached_headers,
                "expires_at": time.time() + IDEMPOTENCY_TTL_SECONDS,
            }

            # Reconstruct response since we consumed the body
            return JSONResponse(
                status_code=response.status_code,
                content=body_json,
                headers=dict(response.headers),
            )

        return response


app.add_middleware(IdempotencyMiddleware)


# Example: charge creation endpoint
@app.post("/v1/charges", status_code=201)
def create_charge(request: Request, response: Response):
    charge_id = f"ch_{uuid4().hex[:24]}"

    charge = {
        "id": charge_id,
        "object": "charge",
        "status": "succeeded",
        "created_at": datetime.now(timezone.utc).isoformat(),
    }

    response.headers["Location"] = f"/v1/charges/{charge_id}"
    return charge


# Example: order creation endpoint
@app.post("/orders", status_code=201)
def create_order(request: Request, response: Response):
    order_id = f"ord_{uuid4().hex[:24]}"

    order = {
        "id": order_id,
        "object": "order",
        "status": "pending",
        "created_at": datetime.now(timezone.utc).isoformat(),
    }

    response.headers["Location"] = f"/orders/{order_id}"
    return order
```

## Key Points

- **Only intercept POST requests.** GET, PUT, and DELETE are already idempotent by the HTTP specification. Applying idempotency keys to them adds complexity without benefit.
- **Fingerprint the request.** The key alone is not enough. If a client reuses a key with different parameters (different amount, different customer), return a `422` error immediately. Stripe calls this an `idempotency_error`.
- **Cache the full response.** Store the status code, relevant headers (especially `Location`), and the response body. On replay, return exactly what the original request returned.
- **Set the `Idempotent-Replayed: true` header** on cached responses so clients know the response is a replay, not a fresh execution.
- **Expire keys after 24 hours.** This matches Stripe's v1 behavior. Keys must not live forever — they serve as a retry window, not permanent deduplication.
- **Use Redis in production.** The in-memory Map/dict examples are for clarity. Production systems need persistence across restarts, atomic operations, and built-in TTL via `SET key value EX 86400`.
- **Clients should generate UUID v4 keys.** The key must be unique per logical operation. Retries of the same operation reuse the same key; new operations get new keys.
