---
name: rate-limiting-and-security
description: "This skill should be used when the user is implementing rate limiting, choosing rate limit algorithms, adding rate limit headers, securing API endpoints, preventing OWASP API Top 10 vulnerabilities, configuring CORS, validating input, or implementing request signing. Covers sliding window, token bucket, and leaky bucket algorithms, rate limit response headers, and API security best practices."
version: 1.0.0
---

# Guard Every Gate, Log Every Attempt

Rate limiting and security are not features you bolt on before launch. They are load-bearing walls. Stripe rate-limits at 100 requests per second per key. GitHub returns `X-RateLimit-Remaining` on every single response. Cloudflare rejects millions of malicious requests before they reach origin servers. These companies do not treat protection as optional — they treat it as infrastructure. An unprotected API is not "MVP-ready"; it is a liability waiting for its first spike of traffic or its first automated attacker.

The patterns below are drawn from Stripe, GitHub, Twilio, Cloudflare, the OWASP API Security Top 10 (2023 edition), and the IETF RateLimit header fields draft. Where these sources converge, treat the practice as non-negotiable.

## Rate Limiting Algorithms

Choose the algorithm that matches your traffic shape. The sliding window counter is the right default for most APIs.

| Algorithm | Burst Handling | Memory | Accuracy | Best For |
|-----------|---------------|--------|----------|----------|
| Fixed Window | Poor (2x burst at boundary) | Very low | Approximate | Simple internal APIs |
| Sliding Window Log | None (strict) | High | Exact | Audit-sensitive endpoints |
| **Sliding Window Counter** | **Good** | **Low** | **Very good** | **Most APIs (recommended)** |
| Token Bucket | Controlled burst up to capacity | Low | Good | API gateways, cloud APIs |
| Leaky Bucket | None (queued, adds latency) | Moderate | Exact | Traffic smoothing |

**Fixed Window** divides time into discrete intervals (e.g., one minute) and counts requests per interval. The problem: 100 requests at 0:59 and 100 at 1:01 produce 200 requests in two seconds — double the intended rate. Only use this for non-critical internal services.

**Sliding Window Counter** is a hybrid that weights the previous window's count against the current window's position. At 15 seconds into a new minute, 75% of the previous window's count plus 100% of the current window's count approximates the true trailing-window count. Two counters per key, no timestamp storage, no boundary burst. This is the algorithm most production APIs use.

**Token Bucket** starts with a full bucket (e.g., 100 tokens), drains one token per request, and refills at a constant rate (e.g., 10 per second). It allows controlled bursts up to bucket capacity, then enforces the sustained rate. AWS API Gateway uses this model. Choose it when you want to permit short traffic spikes without rejecting legitimate clients.

**Leaky Bucket** processes requests at a fixed drain rate and queues incoming requests. If the queue fills, new requests are rejected. It produces perfectly smooth output but adds latency. Use it when downstream services cannot tolerate any burst.

## Rate Limit Headers on Every Response

Return rate limit headers on every response — not just 429s. Clients need to know their remaining budget before they exhaust it.

```http
HTTP/1.1 200 OK
X-RateLimit-Limit: 5000
X-RateLimit-Remaining: 4987
X-RateLimit-Reset: 1705996400
```

| Header | Description | Format |
|--------|-------------|--------|
| `X-RateLimit-Limit` | Maximum requests allowed in the window | Integer |
| `X-RateLimit-Remaining` | Requests remaining in current window | Integer |
| `X-RateLimit-Reset` | When the window resets | Unix timestamp or seconds remaining |
| `Retry-After` | How long to wait before retrying (on 429 only) | Seconds or HTTP-date |

GitHub includes `X-RateLimit-Used` and `X-RateLimit-Resource` for additional visibility. At minimum, always return `Limit`, `Remaining`, and `Reset` on success responses and `Retry-After` on 429 responses.

## 429 Too Many Requests Response Format

When a client exceeds the limit, return a structured 429 with enough information to recover.

```json
HTTP/1.1 429 Too Many Requests
Retry-After: 30
Content-Type: application/json

{
  "error": {
    "type": "rate_limit_error",
    "code": "rate_limit_exceeded",
    "message": "Rate limit exceeded. Please retry after 30 seconds.",
    "retry_after": 30,
    "limit": 100,
    "remaining": 0,
    "reset_at": "2025-01-23T12:01:00Z"
  }
}
```

**Rules:**
- Always include the `Retry-After` header — clients and libraries depend on it for automatic backoff.
- Include `retry_after` in the JSON body as well for clients that parse the body before headers.
- Never return a bare 429 with no body. The client has no way to know when to retry.
- For tiered plans, include the current plan and an upgrade URL in the error: `"message": "Rate limit exceeded for your plan (Starter: 120 req/min). Upgrade to Pro for higher limits."` This turns a frustration into a conversion opportunity.

**Client-side handling:** Always use exponential backoff with jitter. Without jitter, a thousand rate-limited clients all retry at the same intervals, creating thundering herd. Stripe's client libraries implement this automatically. If you publish SDKs, build it in.

## Tiered Rate Limits

Apply rate limits across two dimensions: endpoint sensitivity and plan tier.

**By endpoint sensitivity:**
```
GET  /users              → 600 req/min  (read, cheap)
POST /users              → 60  req/min  (write, moderate)
POST /ai/generate        → 10  req/min  (compute-heavy, expensive)
POST /exports            → 5   req/min  (bulk operation)
```

**By plan tier:**
```
Free:        60  req/min,    1,000/day
Starter:    120  req/min,   10,000/day
Pro:        600  req/min,  100,000/day
Enterprise: Custom (negotiated)
```

**By dimension (GitHub's multi-layer model):**
- Per API key: primary limit (Stripe does 100 req/s per key)
- Per user: aggregate across all keys (GitHub does 5,000 req/hr per user)
- Per IP: for unauthenticated requests (GitHub does 60 req/hr per IP)
- Per endpoint: protect expensive operations independently
- Per organization: aggregate across all members

Communicate the active tier in response headers: `X-RateLimit-Policy: pro`. On 429 responses for tiered APIs, include the upgrade path.

## OWASP API Security Top 10

The OWASP API Security Top 10 (2023 edition) is the definitive list of API vulnerabilities. Every API review should check against these.

| # | Vulnerability | One-Line Summary |
|---|--------------|------------------|
| API1 | Broken Object Level Authorization | API does not verify the user owns the requested resource. Fix: check ownership on every request. |
| API2 | Broken Authentication | Weak auth, missing brute-force protection, token leakage. Fix: rate-limit logins, short-lived tokens, MFA. |
| API3 | Broken Object Property Level Authorization | API returns internal fields or accepts fields the client should not set. Fix: explicit response serialization, field allowlists. |
| API4 | Unrestricted Resource Consumption | Missing rate limits, no payload size caps, no pagination limits. Fix: rate limiting, body size limits, max page size. |
| API5 | Broken Function Level Authorization | Users access admin endpoints. Fix: role checks on every handler. |
| API6 | Unrestricted Access to Sensitive Business Flows | Bots abuse legitimate flows (purchasing, signups). Fix: CAPTCHA, per-action rate limits, anomaly detection. |
| API7 | Server Side Request Forgery (SSRF) | User-supplied URL fetched by server, accessing internal services. Fix: validate URL scheme, block private IP ranges, use allowlists. |
| API8 | Security Misconfiguration | Missing security headers, verbose errors, default credentials. Fix: HSTS, `X-Content-Type-Options: nosniff`, safe error messages. |
| API9 | Improper Inventory Management | Old API versions running, debug endpoints in production, shadow APIs. Fix: API catalog, sunset process, gateway as single entry point. |
| API10 | Unsafe Consumption of APIs | Trusting third-party API responses without validation. Fix: validate and sanitize external data the same as user input. |

**API1 (BOLA) is the number one API vulnerability worldwide.** A user changes `/users/123/orders` to `/users/456/orders` and sees another user's data because the handler checks authentication but not authorization. Every endpoint that takes a resource ID must verify the authenticated user has access to that specific resource.

## CORS Configuration

Cross-Origin Resource Sharing controls which domains can call your API from a browser. Get it wrong and you either block legitimate clients or open the door to credential theft.

**For APIs with known clients (dashboard, mobile web):**
```http
Access-Control-Allow-Origin: https://app.example.com
Access-Control-Allow-Methods: GET, POST, PUT, DELETE
Access-Control-Allow-Headers: Authorization, Content-Type, X-Request-ID
Access-Control-Allow-Credentials: true
Access-Control-Max-Age: 86400
Access-Control-Expose-Headers: X-RateLimit-Limit, X-RateLimit-Remaining
```

**For public APIs meant to be called from any origin:**
```http
Access-Control-Allow-Origin: *
Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS
Access-Control-Allow-Headers: Authorization, Content-Type
```

**Rules:**
- Never combine `Access-Control-Allow-Origin: *` with `Access-Control-Allow-Credentials: true`. Browsers reject this as a security violation.
- Never reflect the `Origin` header back without validation — this is equivalent to allowing every origin.
- Validate the `Origin` header server-side against an allowlist of trusted domains.
- Cache preflight responses with `Access-Control-Max-Age` to reduce OPTIONS request volume. 86400 seconds (24 hours) is standard.
- Expose rate limit headers so browser clients can read them: `Access-Control-Expose-Headers: X-RateLimit-Limit, X-RateLimit-Remaining, X-RateLimit-Reset`.

## Input Validation

Validate everything: path parameters, query parameters, headers, and request bodies. Every unvalidated input is an injection vector.

**Size limits:** Enforce maximum request body size at the web server and application layers. A 10 MB default is reasonable; most JSON API payloads should be far smaller. Set per-field string length limits (255 for names, 320 for emails, 5000 for text fields). Cap pagination: `limit` between 1 and 100, default 20.

**Type checking:** Validate ID formats with regex (`/^usr_[a-zA-Z0-9]{20}$/`). Validate enums against allowlists. Reject unexpected fields — Stripe returns a clear error for unknown parameters: `"Received unknown parameter: is_admin"`. This prevents mass assignment attacks.

**Sanitization:** Use parameterized queries for all database operations — never concatenate user input into SQL. Validate URL schemes and block private IP ranges for any user-supplied URLs (SSRF prevention). Check `Content-Type` headers match expected formats.

**Numeric bounds:** Enforce minimum and maximum values. `?limit=999999999` should not return the entire database. `?page=-1` should not produce undefined behavior.

## HTTPS Only, No Exceptions

Every API endpoint must be served over HTTPS. This is not a recommendation — it is a requirement.

```http
Strict-Transport-Security: max-age=63072000; includeSubDomains; preload
```

**Enforce at multiple layers:**
1. Load balancer: redirect HTTP to HTTPS with `301 Moved Permanently`
2. Application: reject non-HTTPS requests with `403 Forbidden`
3. HSTS header: tell browsers to never attempt HTTP again
4. TLS configuration: minimum TLS 1.2, prefer TLS 1.3, disable weak cipher suites

An API that accepts HTTP in any form sends credentials in plaintext. API keys in query parameters over HTTP are visible to every router, proxy, and ISP between client and server.

## Request Signing for Webhooks

Webhooks are outbound calls from your API to a customer's endpoint. Since anyone can POST to a webhook URL, signature verification is essential. Use HMAC-SHA256 — it is the industry standard (Stripe, GitHub, Shopify, Slack).

**Signing pattern:**
1. Construct the signed payload: `timestamp + "." + raw_json_body`
2. Compute: `HMAC-SHA256(webhook_signing_secret, signed_payload)`
3. Send the signature in a header: `X-Signature: t=1705996400,v1=5257a869...`

**Rules:**
- Always include a timestamp in the signed payload. Without it, attackers can replay captured webhooks indefinitely.
- Enforce a tolerance window (5 minutes is standard). Reject signatures with timestamps older than the tolerance.
- Use constant-time comparison (`hmac.compare_digest` in Python, `crypto.timingSafeEqual` in Node.js). A naive `==` comparison leaks timing information about how many characters match.
- Provide verification libraries in popular languages. Do not force customers to implement HMAC verification from scratch.

## IP Allowlisting for Server-to-Server

For server-to-server integrations, restrict API key usage to specific IP addresses or CIDR ranges.

```json
{
  "api_key": "sk_live_abc123",
  "ip_allowlist": ["203.0.113.0/24", "198.51.100.42/32"],
  "ip_allowlist_enabled": true
}
```

Requests from non-allowlisted IPs are rejected with `403 Forbidden`. This limits the blast radius of a leaked key — even with the key, an attacker cannot use it from an unauthorized network. Stripe and Twilio both support this for enterprise customers.

## Examples

Working implementations in `examples/`:
- **`examples/sliding-window-rate-limiter.md`** — Complete sliding window rate limiter with Redis, including rate limit headers on every response and 429 handling, with implementations in Node.js/Express and Python/FastAPI.
- **`examples/input-validation-middleware.md`** — Request validation middleware with size limits, type checking, and sanitization, with implementations in Node.js/Express and Python/FastAPI.

## Review Checklist

When designing or reviewing rate limiting and security:

- [ ] Rate limiting is implemented on all public endpoints using sliding window counter or token bucket
- [ ] Every response includes `X-RateLimit-Limit`, `X-RateLimit-Remaining`, and `X-RateLimit-Reset` headers
- [ ] 429 responses include `Retry-After` header and structured JSON body with retry information
- [ ] Rate limits are tiered by endpoint sensitivity (read vs write vs compute-heavy)
- [ ] CORS is configured with an explicit origin allowlist — no wildcard with credentials
- [ ] All input is validated: type checking, size limits, enum allowlists, numeric bounds
- [ ] Unknown request fields are rejected (mass assignment prevention)
- [ ] HTTPS is enforced at load balancer and application level with HSTS header
- [ ] Webhooks use HMAC-SHA256 signing with timestamp and constant-time comparison
- [ ] OWASP API1 (BOLA) is addressed: every endpoint verifies resource ownership, not just authentication
- [ ] Error messages are safe — no stack traces, no database details, no internal paths
- [ ] Security headers are set: `Strict-Transport-Security`, `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`
