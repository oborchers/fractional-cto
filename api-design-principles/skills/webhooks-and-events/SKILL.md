---
name: webhooks-and-events
description: "This skill should be used when the user is designing webhook systems, implementing webhook signing with HMAC-SHA256, building webhook retry logic, choosing event naming conventions, handling webhook ordering, implementing webhook endpoints, or building event-driven API integrations. Covers Stripe-style webhook patterns, signature verification, exponential backoff retries, and event deduplication."
version: 1.0.0
---

# Webhooks Are Promises You Must Keep

A webhook is a contract: when something happens on your platform, you will tell the subscriber about it reliably, securely, and in a format they can trust. Every failed delivery, every unsigned payload, every missing retry erodes that trust. Stripe delivers billions of webhook events with cryptographic verification, exponential backoff retries over a 72-hour window, and a structured event format that has become the industry standard. Your webhook system must meet the same bar.

The webhook producer carries the burden of proof. Consumers must be able to verify the event is authentic, handle duplicates gracefully, and trust that missed deliveries will be retried.

## Event Naming: The `resource.action` Convention

Name every event type as `resource.action`, dot-separated, with the action in past tense. This is Stripe's convention and it has become the de facto standard across modern APIs.

```
order.created
order.updated
order.cancelled
payment.succeeded
payment.failed
payment.refunded
invoice.paid
invoice.overdue
invoice.finalized
customer.subscription.created
customer.subscription.updated
customer.subscription.deleted
customer.subscription.trial_will_end
```

**Rules:**

- Use dot-separated namespacing. Nested resources become `parent.child.action` (e.g., `customer.subscription.created`).
- Actions are always past tense. Something happened — you are reporting it. Use `.created`, `.updated`, `.deleted`, `.succeeded`, `.failed`. Never `.create` (that sounds like a command) or `.creating` (that implies in-progress).
- Use snake_case within segments when multiple words are needed: `payment_intent.succeeded`, not `paymentIntent.succeeded`.
- Maintain a canonical event type catalog. Document every event type your API can emit. Adding events is non-breaking; removing or renaming events is a breaking change.

## Event Payload Structure

Every event follows the same envelope. Consumers parse one format regardless of the event type.

```json
{
  "id": "evt_1NdBKYLkdIwHu7ixr0rMHeVX",
  "type": "order.created",
  "created": 1689956724,
  "api_version": "2024-01-15",
  "data": {
    "object": {
      "id": "ord_01HXK3GJ5V8WJKPT",
      "status": "pending",
      "total": 4999,
      "currency": "usd",
      "customer": "cus_NffrFeUfNV2Hib"
    },
    "previous_attributes": {}
  },
  "request": {
    "id": "req_abc123def456",
    "idempotency_key": "KG5LxwFBepaKHyKt"
  }
}
```

**Required fields:**

| Field | Purpose |
|-------|---------|
| `id` | Unique event identifier with `evt_` prefix. Consumers use this for deduplication. |
| `type` | The event type string (`resource.action`). Drives routing in the consumer. |
| `created` | Unix timestamp of event creation. Used for ordering and staleness checks. |
| `data.object` | The full resource in its current state after the event occurred. |
| `data.previous_attributes` | For `.updated` events: the fields that changed and their old values. Empty object for other event types. |
| `request.id` | The API request ID that triggered this event (`null` for async or system events). Enables end-to-end tracing. |

**Design decisions:**

- `created` is a Unix timestamp integer, not an ISO 8601 string. No timezone ambiguity.
- `data.object` contains the full resource snapshot, not a diff. Consumers reconstruct current state from a single event without fetching the API.
- `previous_attributes` is populated only for `.updated` events. Empty object otherwise.

## Webhook Signing: HMAC-SHA256 with Timestamp

Sign every webhook payload with HMAC-SHA256. Include a timestamp in the signed content to prevent replay attacks. This is non-negotiable — an unsigned webhook endpoint is an open door for attackers to inject fake events.

**The signature header:**

```
X-Webhook-Signature: t=1689956724,v1=5257a869e7ecebeda32affa62cdca3fa51cad7e77a0e56ff536d0ce8e108d8bd
```

**Signing algorithm (sender side):**

1. Generate the current Unix timestamp.
2. Concatenate the timestamp and the raw JSON payload body with a dot separator: `{timestamp}.{payload}`.
3. Compute the HMAC-SHA256 of that string using the endpoint's signing secret.
4. Build the header: `t={timestamp},v1={hex_signature}`.

**Verification algorithm (receiver side):**

1. Parse `t` and `v1` from the signature header.
2. Check that the timestamp is within the tolerance window (reject if older than 5 minutes).
3. Reconstruct the signed payload string: `{t}.{raw_body}`.
4. Compute the HMAC-SHA256 using the shared webhook secret.
5. Compare the computed signature to `v1` using a constant-time comparison function.
6. If the comparison fails, reject with `400 Bad Request`.

**Critical implementation details:**

- Always use **constant-time comparison** (`crypto.timingSafeEqual` in Node.js, `hmac.compare_digest` in Python). Standard string equality leaks timing information that attackers can exploit to reconstruct the signature byte by byte.
- Always verify against the **raw request body bytes**, not a re-serialized JSON object. JSON serialization is not deterministic — key ordering, whitespace, and Unicode escaping can differ between serializers, breaking the signature.
- The signing secret is per-endpoint, prefixed with `whsec_` (e.g., `whsec_test_51MqLiJLkdIwH`). Return it only once, at endpoint creation time. If the consumer loses it, rotate and issue a new one.

## Timestamp Validation: Replay Protection

The timestamp in the signature header prevents replay attacks. Without it, an attacker who intercepts a valid webhook payload can replay it days later and the signature will still verify.

**Rule:** Reject any event where the timestamp is more than **5 minutes** old. This tolerance window accounts for clock skew between servers while keeping the replay window tight.

```
Attacker captures: t=1689956724,v1=abc123...
Replays 2 hours later.
Receiver: current_time - 1689956724 = 7200 seconds > 300 seconds
=> REJECTED
```

Five minutes is the standard tolerance. Stripe uses 300 seconds. If your infrastructure has exceptional clock skew, widen to 10 minutes but never more.

## Retry Strategy: Exponential Backoff

When delivery fails — the endpoint returns a non-2xx status code, the connection times out, or DNS resolution fails — retry with exponential backoff. Do not drop events after a single failure.

**Recommended retry schedule:**

```
Attempt  1: Immediate
Attempt  2: 5 minutes
Attempt  3: 30 minutes
Attempt  4: 2 hours
Attempt  5: 8 hours
Attempt  6: 24 hours
Attempt  7: 48 hours
Final:      72 hours after first attempt
```

**Rules:**

- Add **jitter** to every retry delay (plus or minus 20%). Without jitter, all failed deliveries for a down endpoint retry simultaneously, creating a thundering herd that makes recovery harder.
- Set a **30-second timeout** per delivery attempt. If the endpoint does not respond within 30 seconds, treat it as a failure and schedule the next retry.
- After exhausting all retries (72-hour window), mark the event as permanently failed. Send an email notification to the endpoint owner.
- If an endpoint fails consistently over multiple days, **disable it automatically** and notify the account owner. Do not silently continue retrying a dead endpoint indefinitely.
- Store every delivery attempt with its status code, response time, and error message. This history powers the delivery dashboard.

## Idempotency: Consumers Must Handle Duplicates

Webhooks provide **at-least-once** delivery, never exactly-once. Network failures, retries, and edge cases mean the same event may arrive more than once. Every webhook consumer must be idempotent.

**The pattern:** Before processing an event, check if `event.id` has already been processed. If it has, return `200 OK` without re-processing. Record the event ID within the same database transaction as the business logic to avoid race conditions.

```
Incoming event: evt_1NdBKYLkdIwHu7ixr0rMHeVX
  → Check processed_events table for this ID
  → Already exists? Return 200, skip processing
  → Not found? BEGIN transaction:
      1. INSERT into processed_events
      2. Execute business logic
      3. COMMIT
  → Return 200
```

The deduplication check and the business logic must happen atomically. If you check for duplicates, process the event, and then record the event ID as separate steps, a crash between steps 2 and 3 will cause the event to be re-processed on the next delivery.

## Event Ordering: Do Not Rely on Arrival Order

Events may arrive out of order. A `customer.subscription.updated` event might arrive before the `customer.subscription.created` event if the first delivery attempt for `created` fails and is retried.

**The pattern:** Use the `created` timestamp to determine which event reflects the latest state. Implement a latest-wins strategy:

- Store `last_event_timestamp` alongside each resource.
- When processing an event, compare its `created` timestamp to the stored `last_event_timestamp`.
- If the incoming event is older, skip the update — a newer event has already been applied.
- Use upsert operations (insert-or-update) instead of separate create and update handlers. This handles any arrival order gracefully.

```
Event A (created: 1000): customer.subscription.created  → arrives second
Event B (created: 1001): customer.subscription.updated  → arrives first

Processing B first: upsert with last_event_timestamp = 1001
Processing A second: created = 1000 < last_event_timestamp = 1001 → skip
```

This eliminates the brittle assumption that `created` always arrives before `updated`. Build your handlers to work regardless of event order.

## Webhook Endpoint Requirements

**For webhook producers (your API):**

- Set a **30-second timeout** per delivery. If the consumer does not respond, treat it as a failure.
- Accept any **2xx status code** as successful delivery. Do not require exactly `200`.
- Ignore the response body. Webhook delivery is fire-and-forget after a successful status code.

**For webhook consumers (your users):**

- Respond with `200 OK` **within 5 seconds**. Return immediately, then process the event asynchronously using a background job queue.
- Never perform long-running work synchronously in the handler. If processing takes 25 seconds and the producer times out at 30, one slow query triggers unnecessary retries.
- Use the raw request body for signature verification, not a parsed-and-re-serialized object.

## Webhook Registration API

Let consumers register endpoints via your API and filter which event types they receive. Do not require manual configuration in a dashboard.

```
POST /v1/webhook_endpoints
{
  "url": "https://example.com/webhooks",
  "enabled_events": ["order.created", "payment.succeeded", "payment.failed"],
  "description": "Production payment events"
}

→ 201 Created
{
  "id": "wh_1MqVTHLkdIwHu7ix5RbKdAnA",
  "url": "https://example.com/webhooks",
  "status": "enabled",
  "enabled_events": ["order.created", "payment.succeeded", "payment.failed"],
  "secret": "whsec_live_abc123...",
  "created": 1689956724
}
```

**Rules:**

- Return the signing `secret` only on creation. Never return it on subsequent GET or LIST requests.
- Support `enabled_events` filtering. A consumer processing only payments should not receive order events.
- Support a wildcard `["*"]` to subscribe to all event types.
- Provide CRUD operations: create, list, retrieve, update, and delete endpoints.
- Include a `status` field (`enabled` / `disabled`) that reflects whether the endpoint is active.
- Expose an events API (`GET /v1/events`) that lets consumers list recent events for debugging, with filters by type and date range.

## Monitoring and Observability

A webhook system without monitoring is a black hole. Build these from day one:

**Delivery dashboard.** Show every delivery attempt for every endpoint: timestamp, event type, HTTP status code, response time, and whether it was a retry. Let consumers see their own endpoint's delivery history.

**Failure alerts.** When an endpoint accumulates consecutive failures (e.g., 5 in a row), send an email alert to the owner. Do not wait until the 72-hour retry window expires.

**Manual replay.** Provide a dashboard button and an API endpoint (`POST /v1/events/:id/retry`) to re-trigger delivery of a specific event. Replays recover data after consumer bug fixes.

**Metrics.** Track delivery success rate, p95 response time, retry rate, and failure rate per endpoint. Use these for automatic endpoint disabling decisions.

## Examples

Working implementations in `examples/`:
- **`examples/webhook-signature-verification.md`** -- Complete HMAC-SHA256 webhook signature generation (sender) and verification (receiver) with timestamp validation in Node.js and Python
- **`examples/webhook-retry-system.md`** -- Webhook delivery system with exponential backoff, dead letter queue, and delivery status tracking in Node.js and Python

## Review Checklist

When reviewing or building webhook systems:

- [ ] Every event type follows the `resource.action` naming convention with past-tense actions
- [ ] Event payloads use the standard envelope: `id`, `type`, `created`, `data.object`, `request`
- [ ] All payloads are signed with HMAC-SHA256 using a per-endpoint secret
- [ ] Signature includes a timestamp and verification rejects events older than 5 minutes
- [ ] Signature comparison uses constant-time equality, never standard string comparison
- [ ] Failed deliveries retry with exponential backoff up to 72 hours with jitter
- [ ] Endpoints that fail consistently are automatically disabled with owner notification
- [ ] Webhook handlers are idempotent — duplicate events are detected by `event.id` and skipped
- [ ] Event ordering is handled via timestamp comparison, not arrival order assumptions
- [ ] Consumers respond within 5 seconds and process events asynchronously
- [ ] The registration API supports event type filtering and returns the signing secret only at creation
- [ ] A delivery dashboard with manual replay is available for debugging failed deliveries
