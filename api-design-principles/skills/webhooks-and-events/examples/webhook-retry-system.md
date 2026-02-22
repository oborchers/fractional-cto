# Webhook Retry System

A webhook delivery system with exponential backoff, jitter, dead letter queue for permanently failed events, and delivery status tracking. Handles the full lifecycle: initial delivery, retry scheduling, failure escalation, and manual replay.

## Node.js

### Retry Schedule and Delivery Engine

```typescript
import crypto from "crypto";

// Retry intervals in seconds — exponential backoff over 72 hours
const RETRY_SCHEDULE_SECONDS = [
  0,      // Attempt 1: immediate
  300,    // Attempt 2: 5 minutes
  1800,   // Attempt 3: 30 minutes
  7200,   // Attempt 4: 2 hours
  28800,  // Attempt 5: 8 hours
  86400,  // Attempt 6: 24 hours
  172800, // Attempt 7: 48 hours (final retry, ~72h from first attempt)
];

const MAX_ATTEMPTS = RETRY_SCHEDULE_SECONDS.length;
const DELIVERY_TIMEOUT_MS = 30_000; // 30 seconds

interface WebhookEvent {
  id: string;
  type: string;
  created: number;
  data: { object: Record<string, unknown> };
}

interface WebhookEndpoint {
  id: string;
  url: string;
  secret: string;
  status: "enabled" | "disabled";
  enabledEvents: string[];
}

interface DeliveryAttempt {
  eventId: string;
  endpointId: string;
  attemptNumber: number;
  statusCode: number | null;
  errorMessage: string | null;
  responseTimeMs: number;
  attemptedAt: Date;
}

interface DeliveryJob {
  eventId: string;
  endpointId: string;
  endpointUrl: string;
  payload: string;
  signingSecret: string;
  attemptNumber: number;
}

function getRetryDelayMs(attemptNumber: number): number {
  const index = Math.min(attemptNumber, RETRY_SCHEDULE_SECONDS.length - 1);
  const baseDelay = RETRY_SCHEDULE_SECONDS[index] * 1000;

  // Add +/- 20% jitter to prevent thundering herd
  const jitter = baseDelay * 0.2 * (Math.random() * 2 - 1);
  return Math.max(0, baseDelay + jitter);
}

function signPayload(payload: string, secret: string): string {
  const timestamp = Math.floor(Date.now() / 1000);
  const signedContent = `${timestamp}.${payload}`;
  const signature = crypto
    .createHmac("sha256", secret)
    .update(signedContent, "utf8")
    .digest("hex");
  return `t=${timestamp},v1=${signature}`;
}

async function deliverWebhook(job: DeliveryJob): Promise<void> {
  const startTime = Date.now();
  const signatureHeader = signPayload(job.payload, job.signingSecret);

  let statusCode: number | null = null;
  let errorMessage: string | null = null;

  try {
    const response = await fetch(job.endpointUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Webhook-Signature": signatureHeader,
        "X-Webhook-Id": job.eventId,
      },
      body: job.payload,
      signal: AbortSignal.timeout(DELIVERY_TIMEOUT_MS),
    });

    statusCode = response.status;

    if (response.status >= 200 && response.status < 300) {
      // Success — record the attempt and stop
      await recordDeliveryAttempt({
        eventId: job.eventId,
        endpointId: job.endpointId,
        attemptNumber: job.attemptNumber,
        statusCode,
        errorMessage: null,
        responseTimeMs: Date.now() - startTime,
        attemptedAt: new Date(),
      });
      await markDelivered(job.eventId, job.endpointId);
      return;
    }

    errorMessage = `HTTP ${response.status}`;
  } catch (error) {
    errorMessage =
      error instanceof Error ? error.message : "Unknown delivery error";
  }

  // Record the failed attempt
  await recordDeliveryAttempt({
    eventId: job.eventId,
    endpointId: job.endpointId,
    attemptNumber: job.attemptNumber,
    statusCode,
    errorMessage,
    responseTimeMs: Date.now() - startTime,
    attemptedAt: new Date(),
  });

  // Schedule retry or move to dead letter queue
  const nextAttempt = job.attemptNumber + 1;

  if (nextAttempt < MAX_ATTEMPTS) {
    const delayMs = getRetryDelayMs(nextAttempt);
    await scheduleRetry({ ...job, attemptNumber: nextAttempt }, delayMs);
  } else {
    await moveToDeadLetterQueue(job, errorMessage);
  }
}
```

### Dead Letter Queue and Monitoring

```typescript
interface DeadLetterEntry {
  eventId: string;
  endpointId: string;
  endpointUrl: string;
  payload: string;
  lastErrorMessage: string | null;
  totalAttempts: number;
  firstAttemptAt: Date;
  lastAttemptAt: Date;
  movedToDeadLetterAt: Date;
}

async function moveToDeadLetterQueue(
  job: DeliveryJob,
  lastError: string | null
): Promise<void> {
  const entry: DeadLetterEntry = {
    eventId: job.eventId,
    endpointId: job.endpointId,
    endpointUrl: job.endpointUrl,
    payload: job.payload,
    lastErrorMessage: lastError,
    totalAttempts: MAX_ATTEMPTS,
    firstAttemptAt: await getFirstAttemptTime(job.eventId, job.endpointId),
    lastAttemptAt: new Date(),
    movedToDeadLetterAt: new Date(),
  };

  await db.deadLetterQueue.create({ data: entry });
  await markFailed(job.eventId, job.endpointId);

  // Notify the endpoint owner
  await sendFailureNotification(job.endpointId, job.eventId, lastError);

  // Check if this endpoint should be disabled
  await checkEndpointHealth(job.endpointId);
}

async function checkEndpointHealth(endpointId: string): Promise<void> {
  // Count consecutive failures in the last 7 days
  const recentFailures = await db.deliveryAttempts.count({
    where: {
      endpointId,
      statusCode: { notIn: [200, 201, 202, 204] },
      attemptedAt: { gte: new Date(Date.now() - 7 * 24 * 60 * 60 * 1000) },
    },
  });

  // Disable endpoint after sustained failures
  if (recentFailures >= 50) {
    await db.webhookEndpoints.update({
      where: { id: endpointId },
      data: { status: "disabled" },
    });

    await sendEndpointDisabledNotification(endpointId, recentFailures);
  }
}

// Manual replay: re-deliver a specific event to a specific endpoint
async function replayEvent(
  eventId: string,
  endpointId: string
): Promise<void> {
  const event = await db.events.findUnique({ where: { id: eventId } });
  const endpoint = await db.webhookEndpoints.findUnique({
    where: { id: endpointId },
  });

  if (!event || !endpoint) {
    throw new Error("Event or endpoint not found");
  }

  const payload = JSON.stringify(event);

  await deliverWebhook({
    eventId: event.id,
    endpointId: endpoint.id,
    endpointUrl: endpoint.url,
    payload,
    signingSecret: endpoint.secret,
    attemptNumber: 0, // Reset attempt counter for replays
  });
}
```

### Event Dispatch: Connecting Events to Endpoints

```typescript
async function dispatchEvent(event: WebhookEvent): Promise<void> {
  // Find all enabled endpoints subscribed to this event type
  const endpoints = await db.webhookEndpoints.findMany({
    where: {
      status: "enabled",
      OR: [
        { enabledEvents: { has: event.type } },
        { enabledEvents: { has: "*" } },
      ],
    },
  });

  const payload = JSON.stringify(event);

  // Enqueue a delivery job for each endpoint
  for (const endpoint of endpoints) {
    await deliveryQueue.add("deliver", {
      eventId: event.id,
      endpointId: endpoint.id,
      endpointUrl: endpoint.url,
      payload,
      signingSecret: endpoint.secret,
      attemptNumber: 0,
    });
  }
}
```

## Python

### Retry Schedule and Delivery Engine

```python
import hmac
import hashlib
import json
import time
import random
import httpx
from dataclasses import dataclass
from datetime import datetime, timedelta

RETRY_SCHEDULE_SECONDS = [
    0,       # Attempt 1: immediate
    300,     # Attempt 2: 5 minutes
    1800,    # Attempt 3: 30 minutes
    7200,    # Attempt 4: 2 hours
    28800,   # Attempt 5: 8 hours
    86400,   # Attempt 6: 24 hours
    172800,  # Attempt 7: 48 hours
]

MAX_ATTEMPTS = len(RETRY_SCHEDULE_SECONDS)
DELIVERY_TIMEOUT_SECONDS = 30


@dataclass
class DeliveryJob:
    event_id: str
    endpoint_id: str
    endpoint_url: str
    payload: str
    signing_secret: str
    attempt_number: int


@dataclass
class DeliveryAttempt:
    event_id: str
    endpoint_id: str
    attempt_number: int
    status_code: int | None
    error_message: str | None
    response_time_ms: float
    attempted_at: datetime


def get_retry_delay_seconds(attempt_number: int) -> float:
    """Calculate retry delay with jitter."""
    index = min(attempt_number, len(RETRY_SCHEDULE_SECONDS) - 1)
    base_delay = RETRY_SCHEDULE_SECONDS[index]
    # +/- 20% jitter
    jitter = base_delay * 0.2 * (random.random() * 2 - 1)
    return max(0, base_delay + jitter)


def sign_payload(payload: str, secret: str) -> str:
    """Generate the webhook signature header value."""
    timestamp = int(time.time())
    signed_content = f"{timestamp}.{payload}"
    signature = hmac.new(
        secret.encode("utf-8"),
        signed_content.encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()
    return f"t={timestamp},v1={signature}"


async def deliver_webhook(job: DeliveryJob) -> None:
    """
    Attempt to deliver a webhook. On failure, schedule a retry
    or move to the dead letter queue.
    """
    signature_header = sign_payload(job.payload, job.signing_secret)
    start_time = time.monotonic()
    status_code = None
    error_message = None

    try:
        async with httpx.AsyncClient(
            timeout=DELIVERY_TIMEOUT_SECONDS
        ) as client:
            response = await client.post(
                job.endpoint_url,
                content=job.payload,
                headers={
                    "Content-Type": "application/json",
                    "X-Webhook-Signature": signature_header,
                    "X-Webhook-Id": job.event_id,
                },
            )
            status_code = response.status_code

            if 200 <= response.status_code < 300:
                await record_delivery_attempt(DeliveryAttempt(
                    event_id=job.event_id,
                    endpoint_id=job.endpoint_id,
                    attempt_number=job.attempt_number,
                    status_code=status_code,
                    error_message=None,
                    response_time_ms=(time.monotonic() - start_time) * 1000,
                    attempted_at=datetime.utcnow(),
                ))
                await mark_delivered(job.event_id, job.endpoint_id)
                return

            error_message = f"HTTP {response.status_code}"

    except Exception as e:
        error_message = str(e)

    # Record the failed attempt
    await record_delivery_attempt(DeliveryAttempt(
        event_id=job.event_id,
        endpoint_id=job.endpoint_id,
        attempt_number=job.attempt_number,
        status_code=status_code,
        error_message=error_message,
        response_time_ms=(time.monotonic() - start_time) * 1000,
        attempted_at=datetime.utcnow(),
    ))

    # Schedule retry or dead letter
    next_attempt = job.attempt_number + 1

    if next_attempt < MAX_ATTEMPTS:
        delay = get_retry_delay_seconds(next_attempt)
        await schedule_retry(
            DeliveryJob(
                event_id=job.event_id,
                endpoint_id=job.endpoint_id,
                endpoint_url=job.endpoint_url,
                payload=job.payload,
                signing_secret=job.signing_secret,
                attempt_number=next_attempt,
            ),
            delay_seconds=delay,
        )
    else:
        await move_to_dead_letter_queue(job, error_message)
```

### Dead Letter Queue and Monitoring

```python
@dataclass
class DeadLetterEntry:
    event_id: str
    endpoint_id: str
    endpoint_url: str
    payload: str
    last_error_message: str | None
    total_attempts: int
    first_attempt_at: datetime
    last_attempt_at: datetime
    moved_to_dead_letter_at: datetime


async def move_to_dead_letter_queue(
    job: DeliveryJob,
    last_error: str | None,
) -> None:
    """Move a permanently failed delivery to the dead letter queue."""
    entry = DeadLetterEntry(
        event_id=job.event_id,
        endpoint_id=job.endpoint_id,
        endpoint_url=job.endpoint_url,
        payload=job.payload,
        last_error_message=last_error,
        total_attempts=MAX_ATTEMPTS,
        first_attempt_at=await get_first_attempt_time(
            job.event_id, job.endpoint_id
        ),
        last_attempt_at=datetime.utcnow(),
        moved_to_dead_letter_at=datetime.utcnow(),
    )

    await db.dead_letter_queue.insert(entry)
    await mark_failed(job.event_id, job.endpoint_id)
    await send_failure_notification(
        job.endpoint_id, job.event_id, last_error
    )
    await check_endpoint_health(job.endpoint_id)


async def check_endpoint_health(endpoint_id: str) -> None:
    """Disable an endpoint if it has too many recent failures."""
    cutoff = datetime.utcnow() - timedelta(days=7)
    recent_failures = await db.delivery_attempts.count(
        endpoint_id=endpoint_id,
        status_code_not_in=[200, 201, 202, 204],
        attempted_at_gte=cutoff,
    )

    if recent_failures >= 50:
        await db.webhook_endpoints.update(
            id=endpoint_id,
            status="disabled",
        )
        await send_endpoint_disabled_notification(
            endpoint_id, recent_failures
        )


async def replay_event(event_id: str, endpoint_id: str) -> None:
    """Manually re-deliver a specific event to a specific endpoint."""
    event = await db.events.find(id=event_id)
    endpoint = await db.webhook_endpoints.find(id=endpoint_id)

    if not event or not endpoint:
        raise ValueError("Event or endpoint not found")

    payload = json.dumps(event, separators=(",", ":"))

    await deliver_webhook(DeliveryJob(
        event_id=event["id"],
        endpoint_id=endpoint["id"],
        endpoint_url=endpoint["url"],
        payload=payload,
        signing_secret=endpoint["secret"],
        attempt_number=0,  # Reset for replays
    ))
```

### Event Dispatch

```python
async def dispatch_event(event: dict) -> None:
    """Fan out a single event to all subscribed endpoints."""
    endpoints = await db.webhook_endpoints.find_many(
        status="enabled",
        enabled_events_contains_any=[event["type"], "*"],
    )

    payload = json.dumps(event, separators=(",", ":"))

    for endpoint in endpoints:
        await delivery_queue.enqueue(
            "deliver",
            DeliveryJob(
                event_id=event["id"],
                endpoint_id=endpoint["id"],
                endpoint_url=endpoint["url"],
                payload=payload,
                signing_secret=endpoint["secret"],
                attempt_number=0,
            ),
        )
```

## Key Points

- **Exponential backoff with jitter is mandatory.** Without jitter, a downed endpoint that recovers gets hit by all queued retries simultaneously, likely going down again. The 20% jitter spread prevents this thundering herd.
- **The 72-hour retry window balances reliability with finality.** Most transient issues (deployments, DNS propagation, certificate renewals) resolve within hours. Three days gives consumers ample time to fix their endpoint without keeping events in limbo indefinitely.
- **The dead letter queue is the safety net.** Events that exhaust all retries are not deleted — they are moved to a dead letter queue where they can be inspected and replayed manually after the root cause is fixed.
- **Endpoint health monitoring prevents wasted resources.** An endpoint returning 500 for a week is not going to start working on its own. Disable it after sustained failures and notify the owner, rather than burning compute on deliveries that will never succeed.
- **Manual replay enables recovery from consumer bugs.** If a consumer deploys a bug that returns 500 for a specific event type, they need a way to replay those events after the fix. The replay function resets the attempt counter and re-delivers with a fresh signature.
- **Every delivery attempt is recorded.** The full history of attempts (status code, response time, error message) powers the delivery dashboard and enables debugging without guesswork.
