# Webhook Signature Verification

Complete HMAC-SHA256 webhook signature generation (sender side) and verification (receiver side) with timestamp-based replay protection. Covers the full round trip: building the signature header when delivering a webhook, and verifying it when receiving one.

## Node.js

### Sender: Generating the Signature

```typescript
import crypto from "crypto";

interface SignatureResult {
  header: string;
  timestamp: number;
}

function signWebhookPayload(
  payload: string,
  secret: string
): SignatureResult {
  const timestamp = Math.floor(Date.now() / 1000);

  // Step 1: Build the signed content — timestamp + dot + raw payload
  const signedContent = `${timestamp}.${payload}`;

  // Step 2: Compute HMAC-SHA256
  const signature = crypto
    .createHmac("sha256", secret)
    .update(signedContent, "utf8")
    .digest("hex");

  // Step 3: Build the header value
  const header = `t=${timestamp},v1=${signature}`;

  return { header, timestamp };
}

// Usage: delivering a webhook
async function deliverWebhook(
  endpointUrl: string,
  event: object,
  signingSecret: string
): Promise<Response> {
  const payload = JSON.stringify(event);
  const { header } = signWebhookPayload(payload, signingSecret);

  return fetch(endpointUrl, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Webhook-Signature": header,
      "X-Webhook-Id": (event as any).id,
    },
    body: payload,
    signal: AbortSignal.timeout(30_000), // 30-second timeout
  });
}
```

### Receiver: Verifying the Signature

```typescript
import crypto from "crypto";

class WebhookVerificationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "WebhookVerificationError";
  }
}

function verifyWebhookSignature(
  rawBody: string,
  signatureHeader: string,
  secret: string,
  toleranceSeconds: number = 300 // 5 minutes
): void {
  // Step 1: Parse the signature header
  const parts: Record<string, string> = {};
  for (const element of signatureHeader.split(",")) {
    const [key, ...valueParts] = element.split("=");
    parts[key] = valueParts.join("=");
  }

  const timestamp = parts["t"];
  const receivedSignature = parts["v1"];

  if (!timestamp || !receivedSignature) {
    throw new WebhookVerificationError(
      "Missing timestamp or signature in header"
    );
  }

  // Step 2: Check timestamp tolerance — reject replay attacks
  const timestampAge = Math.floor(Date.now() / 1000) - parseInt(timestamp, 10);
  if (Math.abs(timestampAge) > toleranceSeconds) {
    throw new WebhookVerificationError(
      `Timestamp outside tolerance window (age: ${timestampAge}s, tolerance: ${toleranceSeconds}s)`
    );
  }

  // Step 3: Compute expected signature from the raw body
  const signedContent = `${timestamp}.${rawBody}`;
  const expectedSignature = crypto
    .createHmac("sha256", secret)
    .update(signedContent, "utf8")
    .digest("hex");

  // Step 4: Constant-time comparison — prevents timing attacks
  const expected = Buffer.from(expectedSignature, "hex");
  const received = Buffer.from(receivedSignature, "hex");

  if (expected.length !== received.length) {
    throw new WebhookVerificationError("Invalid signature");
  }

  if (!crypto.timingSafeEqual(expected, received)) {
    throw new WebhookVerificationError("Invalid signature");
  }
}

// Express middleware usage
import express from "express";

const app = express();

app.post(
  "/webhooks",
  express.raw({ type: "application/json" }),
  (req, res) => {
    const signatureHeader = req.headers["x-webhook-signature"] as string;
    if (!signatureHeader) {
      return res.status(400).json({ error: "Missing signature header" });
    }

    try {
      verifyWebhookSignature(
        req.body.toString("utf8"),
        signatureHeader,
        process.env.WEBHOOK_SECRET!
      );
    } catch (err) {
      return res.status(400).json({
        error: err instanceof Error ? err.message : "Verification failed",
      });
    }

    const event = JSON.parse(req.body.toString("utf8"));

    // Enqueue for async processing — respond immediately
    eventQueue.add(event);

    res.status(200).json({ received: true });
  }
);
```

## Python

### Sender: Generating the Signature

```python
import hmac
import hashlib
import json
import time
import httpx


def sign_webhook_payload(payload: str, secret: str) -> tuple[str, int]:
    """
    Sign a webhook payload with HMAC-SHA256 and a timestamp.

    Returns:
        Tuple of (signature_header, timestamp)
    """
    timestamp = int(time.time())

    # Build the signed content: timestamp + dot + raw payload
    signed_content = f"{timestamp}.{payload}"

    # Compute HMAC-SHA256
    signature = hmac.new(
        secret.encode("utf-8"),
        signed_content.encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()

    header = f"t={timestamp},v1={signature}"
    return header, timestamp


async def deliver_webhook(
    endpoint_url: str,
    event: dict,
    signing_secret: str,
) -> httpx.Response:
    """Deliver a signed webhook event to an endpoint."""
    payload = json.dumps(event, separators=(",", ":"))
    header, _ = sign_webhook_payload(payload, signing_secret)

    async with httpx.AsyncClient(timeout=30.0) as client:
        return await client.post(
            endpoint_url,
            content=payload,
            headers={
                "Content-Type": "application/json",
                "X-Webhook-Signature": header,
                "X-Webhook-Id": event["id"],
            },
        )
```

### Receiver: Verifying the Signature

```python
import hmac
import hashlib
import time


class WebhookVerificationError(Exception):
    pass


def verify_webhook_signature(
    raw_body: bytes,
    signature_header: str,
    secret: str,
    tolerance_seconds: int = 300,  # 5 minutes
) -> None:
    """
    Verify a webhook signature. Raises WebhookVerificationError on failure.

    Args:
        raw_body: The raw request body as bytes.
        signature_header: The X-Webhook-Signature header value.
        secret: The webhook signing secret (whsec_...).
        tolerance_seconds: Maximum age of event in seconds.
    """
    # Step 1: Parse the signature header
    parts = dict(
        pair.split("=", 1) for pair in signature_header.split(",")
    )

    timestamp = parts.get("t")
    received_signature = parts.get("v1")

    if not timestamp or not received_signature:
        raise WebhookVerificationError(
            "Missing timestamp or signature in header"
        )

    # Step 2: Check timestamp tolerance
    timestamp_age = abs(time.time() - int(timestamp))
    if timestamp_age > tolerance_seconds:
        raise WebhookVerificationError(
            f"Timestamp outside tolerance window "
            f"(age: {timestamp_age:.0f}s, tolerance: {tolerance_seconds}s)"
        )

    # Step 3: Compute expected signature
    signed_content = f"{timestamp}.{raw_body.decode('utf-8')}"
    expected_signature = hmac.new(
        secret.encode("utf-8"),
        signed_content.encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()

    # Step 4: Constant-time comparison
    if not hmac.compare_digest(expected_signature, received_signature):
        raise WebhookVerificationError("Invalid signature")


# FastAPI usage
from fastapi import FastAPI, Request, HTTPException

app = FastAPI()

@app.post("/webhooks")
async def handle_webhook(request: Request):
    signature_header = request.headers.get("x-webhook-signature")
    if not signature_header:
        raise HTTPException(status_code=400, detail="Missing signature header")

    raw_body = await request.body()

    try:
        verify_webhook_signature(
            raw_body=raw_body,
            signature_header=signature_header,
            secret=WEBHOOK_SECRET,
        )
    except WebhookVerificationError as e:
        raise HTTPException(status_code=400, detail=str(e))

    event = json.loads(raw_body)

    # Enqueue for async processing
    await event_queue.put(event)

    return {"received": True}
```

## Key Points

- **Sign the raw payload string, not a re-serialized object.** JSON serialization is not deterministic — key order, whitespace, and Unicode escaping vary between languages and libraries. The sender and receiver must operate on identical bytes.
- **Always use constant-time comparison.** Standard string equality (`==`) short-circuits on the first mismatched byte. An attacker can time thousands of requests to reconstruct the signature one byte at a time. `crypto.timingSafeEqual` (Node.js) and `hmac.compare_digest` (Python) prevent this.
- **The 5-minute tolerance window balances security and clock skew.** Tighter windows (30 seconds) break when server clocks drift. Wider windows (1 hour) leave a large replay attack surface.
- **Return the signing secret only at endpoint creation time.** If the consumer loses it, rotate the secret and issue a new one. Never expose the secret in GET or LIST responses.
- **The signature header format (`t=...,v1=...`) supports versioning.** When you need to change the signing algorithm, add a `v2` scheme. Continue sending both `v1` and `v2` during the migration period so consumers can upgrade at their own pace.
