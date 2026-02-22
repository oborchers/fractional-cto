---
name: caching-and-performance
description: "This skill should be used when the user is implementing HTTP caching, configuring Cache-Control headers, using ETags and conditional requests, setting up CDN caching for APIs, implementing response compression, choosing between gzip and Brotli, configuring HTTP/2, or implementing circuit breakers. Covers Cache-Control directives, ETag validation, CDN strategies, compression, and resilience patterns."
version: 1.0.0
---

# The Fastest Request Is the One You Never Make

Caching is the highest-leverage performance optimization available to any API. A correctly cached response eliminates network latency entirely, reduces server load, and improves perceived performance by orders of magnitude. Every API endpoint must ship with an explicit caching strategy -- omitting `Cache-Control` headers forces browsers into heuristic caching, which leads to unpredictable behavior. Start with caching, then layer compression, protocol upgrades, and resilience on top.

## Cache-Control Directives

Always set `Cache-Control` explicitly. Never rely on heuristic caching or the deprecated `Expires` header.

| Directive | Scope | When to Use |
|-----------|-------|-------------|
| `public` | Shared + private caches | Response is identical for all users (product catalogs, reference data, schemas) |
| `private` | Browser only | Response is user-specific (account details, dashboards). Prevents CDN/proxy caching |
| `no-cache` | All caches | Cache may store but must revalidate with origin before every use. Use when freshness matters but bandwidth savings from 304s are valuable |
| `no-store` | All caches | Never cache. Use for financial data, PII, balances, transactions |
| `max-age=N` | All caches | Response is fresh for N seconds. Primary TTL mechanism for all cacheable responses |
| `s-maxage=N` | Shared caches only | Overrides `max-age` for CDNs and proxies. Use to give CDNs longer TTLs than browsers |
| `must-revalidate` | All caches | Once stale, the cache must not serve the response without revalidating. Prevents serving stale content after TTL expires |
| `stale-while-revalidate=N` | All caches | Serve stale for N seconds while revalidating in the background. Best single directive for perceived performance on read-heavy endpoints |
| `immutable` | All caches | Response body will never change for this URL. Skip conditional revalidation entirely. Use for versioned URLs (schemas, configs with version in path) |

**Never combine contradictory directives.** `public, no-store` is nonsensical. `no-cache` and `no-store` are different -- `no-cache` still stores and validates; `no-store` prohibits storage entirely.

## Caching Strategy by Data Type

| Data Type | Cache-Control | TTL | Rationale |
|-----------|--------------|-----|-----------|
| Static reference data (country codes, currencies) | `public, max-age=300, s-maxage=86400, stale-while-revalidate=86400` | CDN: 24h, browser: 5m | Changes rarely, identical for all users |
| Product catalogs, pricing tiers | `public, max-age=300, s-maxage=3600, stale-while-revalidate=86400` | CDN: 1h, browser: 5m | Changes infrequently, high read volume |
| User-specific data (accounts, dashboards) | `private, max-age=60, stale-while-revalidate=300` | Browser: 1m | Must never be CDN-cached; use short browser TTLs |
| List endpoints, search results | `public, max-age=60, s-maxage=300` | CDN: 5m, browser: 1m | Can tolerate short staleness |
| Financial data, PII, balances | `no-store` | None | Staleness is unacceptable; never cache |
| Versioned schemas, immutable configs | `public, max-age=31536000, immutable` | 1 year | URL contains version; content never changes at that URL |
| Webhook deliveries, mutations | No caching headers | None | POST/PUT/DELETE must always reach origin |

## ETags and Conditional Requests

ETags enable conditional requests that save bandwidth without sacrificing freshness. The server generates a unique tag for each response version. On subsequent requests, the client sends `If-None-Match` with the stored ETag. If unchanged, the server returns `304 Not Modified` with no body.

**Use strong ETags by default.** Generate them from a content hash (SHA-256 of the canonical JSON) or a database version column. Weak ETags (`W/"..."`) are acceptable when minor representation differences (field order, whitespace) should not invalidate the cache.

**Pair ETags with `no-cache` for maximum freshness with bandwidth savings.** The combination `Cache-Control: no-cache` + `ETag` forces revalidation on every request but returns an empty 304 when nothing changed. GitHub uses this pattern for its entire API -- conditional requests that return 304 do not count against the rate limit.

**Support `If-Modified-Since` as a fallback.** Send both `ETag` and `Last-Modified` headers. Clients that support ETags use `If-None-Match`; older clients fall back to `If-Modified-Since`. When both are present, `If-None-Match` takes precedence per RFC 9110. Prefer ETags for APIs because `Last-Modified` has only 1-second granularity and is susceptible to clock skew.

## CDN Strategies for APIs

Use CDN edge caching for public, high-traffic, read-heavy endpoints. Never CDN-cache user-specific, financial, or real-time data.

**Set the `Vary` header correctly.** Without it, a CDN might serve a gzip-compressed response to a client that cannot decompress it. Common API configurations: `Vary: Accept-Encoding` for compression negotiation, `Vary: Accept, Accept-Encoding` for content negotiation, `Vary: Accept-Encoding, X-API-Version` for versioned APIs.

**Never use `Vary: Authorization` with `public` caching.** This creates a separate cache entry per auth token, driving hit rates to near zero. Use `Cache-Control: private` for user-specific responses instead.

**Build deliberate cache keys.** The default CDN cache key is the URL, which is often insufficient for APIs. Include relevant headers (`Accept-Encoding`, `Accept-Language`, `X-API-Version`) in the cache key. Never include the full `Authorization` header -- hash it or use a tier identifier if the response varies by subscription level.

**Use surrogate keys (cache tags) for targeted invalidation.** Tag cached responses with resource identifiers (e.g., `product-abc123`, `category-electronics`). When a product changes, purge by tag to invalidate both the detail endpoint and every collection that includes it. Fastly, Cloudflare (Cache Tags), and Varnish (xkey) support this pattern.

**Prefer `stale-while-revalidate` over aggressive purging.** For most read-heavy APIs, serving slightly stale data for a few seconds while revalidating in the background is preferable to complex real-time purge pipelines.

## Compression

Compress every API response larger than 1 KB. Do not compress responses smaller than 1 KB (overhead exceeds savings) or already-compressed content (images, archives).

**Support gzip as baseline, Brotli for modern clients.** Brotli produces 15-25% smaller payloads than gzip for JSON. Zstandard (zstd) is emerging with even better speed-to-ratio tradeoffs but browser support is limited (Chrome 123+, Firefox 126+).

**Negotiate via `Accept-Encoding`.** The client sends `Accept-Encoding: zstd, br, gzip` and the server responds with the best mutually-supported encoding. Priority order: `zstd > br > gzip > identity`. Always include `Vary: Accept-Encoding` so caches store separate copies per encoding.

**Compress at the gateway or CDN, not the application.** Application servers should send uncompressed responses to the reverse proxy or CDN, which handles compression centrally. This simplifies application code, avoids duplicate configuration across services, and offloads CPU from application servers.

## HTTP/2 and HTTP/3

**Enable HTTP/2 on every API.** HTTP/2 multiplexes multiple requests over a single TCP connection, eliminating the 6-connection-per-origin browser limit from HTTP/1.1. A single TLS handshake serves all concurrent requests. HPACK header compression reduces overhead from repetitive headers like `Authorization` and `Content-Type`.

**Skip server push for APIs.** Server push was designed for preloading related web resources. For APIs, clients know what they need. Server push adds complexity without meaningful benefit and is being deprecated in most implementations.

**Adopt HTTP/3 (QUIC) for latency-sensitive APIs.** HTTP/3 replaces TCP with QUIC (UDP-based), reducing connection setup to one round trip (zero for resumed connections). It eliminates TCP head-of-line blocking -- one slow stream no longer blocks others. Connection migration allows mobile clients to change networks without reconnecting. All major CDNs support HTTP/3. Advertise support via the `Alt-Svc` header: `Alt-Svc: h3=":443"; ma=86400`.

## Circuit Breakers

When your API depends on external services, wrap those dependencies in circuit breakers to prevent cascading failures.

**Three states:**

| State | Behavior | Transition |
|-------|----------|------------|
| **Closed** | Normal operation. Requests pass through. Failures are counted within a time window. | Opens when failure count exceeds threshold (e.g., 5 failures in 60 seconds) |
| **Open** | All requests fail immediately with a predefined fallback. No calls reach the dependency. | Transitions to Half-Open after a recovery timeout (e.g., 30 seconds) |
| **Half-Open** | A limited number of test requests are allowed through. | Closes if test requests succeed. Reopens if they fail. |

**Set thresholds based on the dependency.** Payment services need low thresholds (3-5 failures) and short recovery timeouts. Notification services can tolerate higher thresholds. Always provide a fallback -- queue for retry, return a cached response, or return a degraded result with a clear status.

**Combine with retries and exponential backoff.** Use full jitter (recommended by AWS): `delay = random(0, min(max_delay, base_delay * 2^attempt))`. Jitter prevents thundering herd problems when multiple clients retry simultaneously against a recovering service. Honor `Retry-After` headers when present.

## Connection Pooling and Keep-Alive

Reuse TCP connections. Creating a new connection for every request wastes time on TCP handshakes and TLS negotiation.

**Use connection pooling in API clients.** Every HTTP client library supports connection pools -- `requests.Session` in Python, `https.Agent` with `keepAlive: true` in Node.js, `http.Transport` with `MaxIdleConnsPerHost` in Go. A single pooled session should be shared across all requests to the same API.

**Configure keep-alive on servers.** Set `keepalive_timeout` to 60-90 seconds and `keepalive_requests` to 1000+ to allow connection reuse. Maintain a pool of keep-alive connections to upstream backends (e.g., `keepalive 32` in Nginx upstream blocks).

**Always drain and close response bodies.** In languages like Go, failing to read and close the response body prevents the connection from returning to the pool, causing connection leaks that eventually exhaust the pool.

## Review Checklist

When reviewing an API for caching and performance:

- [ ] Every endpoint sets an explicit `Cache-Control` header -- no heuristic caching
- [ ] Public, read-heavy endpoints use `s-maxage` and `stale-while-revalidate` for CDN caching
- [ ] User-specific endpoints use `Cache-Control: private`; sensitive data uses `no-store`
- [ ] ETags are generated for GET responses and `If-None-Match` is handled with 304
- [ ] `Vary` header is set correctly for endpoints with content negotiation or compression
- [ ] Responses larger than 1 KB are compressed; both gzip and Brotli are supported
- [ ] HTTP/2 is enabled; `Alt-Svc` header advertises HTTP/3 if supported
- [ ] External service dependencies are wrapped in circuit breakers with explicit fallbacks
- [ ] API clients use connection pooling, not per-request connections
- [ ] Retry logic uses exponential backoff with full jitter and honors `Retry-After` headers
- [ ] Cache invalidation strategy is defined: TTL-based, surrogate-key purge, or event-driven
