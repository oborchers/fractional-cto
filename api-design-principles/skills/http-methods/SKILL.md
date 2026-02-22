---
name: http-methods
description: "This skill should be used when the user is choosing HTTP methods for API endpoints, designing CRUD operations, implementing idempotent operations, deciding between PUT and PATCH, handling bulk operations, or working with HTTP verb semantics. Covers GET, POST, PUT, PATCH, DELETE with idempotency rules, status code pairings, and real-world patterns."
version: 1.0.0
---

# Every Verb Is a Promise

HTTP methods are not suggestions. They are a contract between your API and every client, proxy, cache, browser, and crawler that will ever touch it. When you label an endpoint `GET`, you promise it is safe to retry, safe to cache, and will never modify state. When you use `POST`, you acknowledge that duplicates are possible without explicit safeguards. Getting this wrong does not just break conventions — it breaks infrastructure assumptions that the entire web stack relies on.

The five core methods — GET, POST, PUT, PATCH, DELETE — cover virtually every API operation. The rules below are drawn from the HTTP/1.1 specification (RFC 7231), Stripe, GitHub, Google, Zalando, and Microsoft REST API guidelines. Where these sources converge, treat the pattern as settled law.

## GET — Read Without Side Effects

GET retrieves a resource or collection. It is safe (no side effects), idempotent (same result every call), and cacheable.

**Rules:**
- Never modify server state in a GET handler. Not "usually" — never. The Google Web Accelerator incident of 2005 pre-fetched links on pages, deleting records on sites that used GET for destructive operations.
- Never include a request body. The HTTP spec allows servers to ignore it, and many proxies strip it entirely.
- Return `200 OK` with the resource body, or `404 Not Found` if the resource does not exist.
- Support conditional requests with `ETag` and `If-None-Match` headers. Return `304 Not Modified` when content has not changed — this is free performance.
- Use query parameters for filtering, sorting, and pagination. Never encode filters in the path.

```
GET /orders                          → 200 OK (collection)
GET /orders/789                      → 200 OK (single resource)
GET /orders?status=pending&sort=-created_at  → 200 OK (filtered, sorted)
GET /orders/789 + If-None-Match: "etag"     → 304 Not Modified
```

**BAD:**
```
GET /orders/789/cancel               → Modifies state via GET
GET /getOrderById?id=789             → Verb in URL, filter as query param for identity
```

## POST — Create or Trigger, Never Assume Idempotent

POST creates a new resource or triggers an action. It is neither safe nor idempotent — two identical POST requests may create two resources.

**Rules:**
- Return `201 Created` with a `Location` header pointing to the new resource for creation operations.
- Return `200 OK` or `202 Accepted` for action operations (cancel, refund, send).
- The server assigns the resource ID, not the client.
- Use POST for complex search queries that exceed URL length limits, batch operations, and non-CRUD actions that do not map to other verbs.
- To make POST safely retryable, implement the `Idempotency-Key` header pattern (see the Idempotency section below).

```
POST /orders                         → 201 Created + Location: /orders/790
POST /orders/789/cancel              → 200 OK (action)
POST /search                         → 200 OK (complex query body)
POST /orders/batch                   → 200 OK (batch operation)
```

**BAD:**
```
POST /orders/list                    → Use GET for retrieval
POST /createOrder                    → Verb in URL; POST /orders is sufficient
```

## PUT — Full Replacement, Always Idempotent

PUT replaces the entire resource at the given URL. Calling PUT twice with the same body produces the same result — this is its defining characteristic.

**Rules:**
- The client must send the complete resource representation. Any field not included is reset to its default value or removed. This is the critical distinction from PATCH.
- Return `200 OK` with the updated resource, or `204 No Content` if no body is returned.
- Can perform upsert: return `201 Created` if the resource did not exist, `200 OK` if it did.
- The client determines the resource identity via the URL. Use PUT when the client controls the ID or key.

```
PUT /users/42
{
  "name": "Oliver Borchers",
  "email": "oliver@example.com",
  "role": "admin",
  "is_active": true
}
→ 200 OK (all fields replaced)
```

**BAD — partial body with PUT semantics:**
```
PUT /users/42
{ "role": "admin" }
→ name, email, is_active are now wiped — this is correct PUT behavior,
  but almost certainly not what the client intended.
  Use PATCH for partial updates.
```

## PATCH — Partial Update, Preferred Over PUT

PATCH updates only the fields included in the request body. Everything else stays unchanged. This is the method most modern APIs use for updates.

**Rules:**
- Only modify the fields present in the request. Leave all other fields untouched.
- Return `200 OK` with the full updated resource so the client sees the current state.
- Prefer JSON Merge Patch (`application/merge-patch+json`) for simplicity. Use JSON Patch (`application/json-patch+json`) when you need operations like `remove`, `move`, or `test`.
- PATCH is not guaranteed idempotent by the spec (an increment operation would not be), but standard JSON merge patches are idempotent in practice.

```
PATCH /users/42
{ "role": "admin" }
→ 200 OK (only role changed; name, email, is_active preserved)
```

**Why PATCH over PUT for most updates:** Stripe, GitHub, and Twilio all default to partial-update semantics. PUT requires the client to know and send every field, creating risk of accidental data loss when a field is forgotten. PATCH is safer for resources with many fields, for mobile clients with bandwidth constraints, and for concurrent updates where multiple clients modify different fields.

## DELETE — Remove, Stay Idempotent

DELETE removes the resource at the given URL. It must be idempotent — deleting an already-deleted resource is not an error.

**Rules:**
- Return `204 No Content` with no response body, or `200 OK` with the deleted resource as confirmation (Stripe returns `{ "id": "...", "deleted": true }`).
- Deleting a resource that does not exist should return `204` (idempotent) or `404` — both are acceptable, but `204` is more consistent with idempotency guarantees.
- For soft-delete, consider `PATCH /users/42 { "deleted_at": "2024-..." }` or `POST /users/42/archive` to make the intent explicit.
- Avoid request bodies on DELETE. Some APIs accept them for batch deletes (`POST /users/batch-delete` with a body of IDs is the safer pattern).

```
DELETE /users/42                     → 204 No Content
DELETE /users/42 (already deleted)   → 204 No Content (idempotent)
DELETE /posts/10/comments/5          → 204 No Content
```

**BAD:**
```
POST /users/42/delete                → DELETE verb exists for this purpose
GET  /deleteUser?id=42               → GET must never modify state
```

## Decision Framework

Use this table as a quick reference for every endpoint you design.

| Method | Idempotent? | Safe? | Cacheable? | Typical Success Codes | Request Body |
|--------|-------------|-------|------------|----------------------|--------------|
| GET | Yes | Yes | Yes | 200, 304 | No |
| POST | **No** | No | No | 201, 200, 202 | Yes |
| PUT | Yes | No | No | 200, 201, 204 | Yes (full) |
| PATCH | Usually | No | No | 200, 204 | Yes (partial) |
| DELETE | Yes | No | No | 204, 200 | Avoid |
| HEAD | Yes | Yes | Yes | 200, 304 | No |
| OPTIONS | Yes | Yes | No | 200, 204 | No |

## Idempotency Rules Per Verb

Idempotency means making the same request multiple times produces the same result as making it once. This is critical for reliability — network failures force retries, and retries must not cause duplicate side effects.

**Naturally idempotent (safe to retry without extra work):**
- **GET** — Reading never changes state.
- **PUT** — Replacing with the same data yields the same resource.
- **DELETE** — Deleting an already-deleted resource is a no-op.
- **HEAD / OPTIONS** — Read-only by definition.

**Not idempotent (requires explicit safeguards):**
- **POST** — Two identical POSTs may create two resources, charge a card twice, or send two emails. Implement the `Idempotency-Key` header to make POST safely retryable. The client generates a UUID and includes it in the request header. The server stores the response keyed to this value and returns the cached response on retry.
- **PATCH** — Most JSON merge patches are idempotent in practice, but increment or append operations are not. Design your PATCH payloads to be declarative ("set role to admin") rather than imperative ("increment login_count by 1").

```
POST /v1/charges
Idempotency-Key: req_unique_abc123
Content-Type: application/json

{ "amount": 2000, "currency": "usd" }

# Client retries with the same key after timeout →
# Server returns cached response, no duplicate charge.
# Response header: Idempotent-Replayed: true
```

Stripe keys expire after 24 hours. This pattern is now an IETF draft standard adopted by Adyen, PayPal, and others.

## Common Mistakes

**GET with side effects.** The most dangerous mistake. If a GET handler sends an email, creates a log entry, increments a counter, or modifies a database row, crawlers, prefetchers, and monitoring tools will trigger those side effects silently.

**POST for everything.** Using POST where GET, PUT, PATCH, or DELETE would be correct destroys cacheability, breaks idempotency assumptions, and forces every client to read documentation instead of relying on HTTP semantics.

**PUT with partial bodies.** Sending `{ "email": "new@example.com" }` to a PUT endpoint wipes every field not included. If you mean "update one field," use PATCH.

**DELETE with complex side effects.** If "deleting" an order triggers refunds, emails, and inventory changes, model this as `POST /orders/789/cancel` instead. DELETE should mean the resource is gone, not that a complex business process kicks off.

**Ignoring idempotency on POST.** Any POST endpoint that charges money, sends a message, or creates a billable resource must support the Idempotency-Key pattern. Network retries are inevitable; duplicate charges are unacceptable.

**Confusing 200 and 201.** Return `201 Created` when a POST creates a new resource. Return `200 OK` when a POST triggers an action or when PUT/PATCH updates an existing resource. The distinction tells clients whether to expect a `Location` header.

## Good vs. Bad Pairs

| Scenario | GOOD | BAD | Why |
|----------|------|-----|-----|
| Fetch a user | `GET /users/42` | `POST /getUser` | GET is for retrieval; verbs violate REST |
| Create an order | `POST /orders` | `PUT /orders` | PUT requires client to specify ID |
| Update one field | `PATCH /users/42 { "role": "admin" }` | `PUT /users/42 { "role": "admin" }` | PUT wipes unspecified fields |
| Delete a resource | `DELETE /users/42` | `POST /users/42/delete` | DELETE verb exists for this |
| Cancel an order | `POST /orders/42/cancel` | `DELETE /orders/42` | DELETE implies removal, not state change |
| Idempotent create | `PUT /bookmarks/repo-123` | `POST /bookmarks` (with dedup) | PUT is naturally idempotent for upserts |
| Simple search | `GET /users?q=oliver` | `POST /users/search` | Read-only search should use GET |
| Complex search | `POST /search` (with body) | `GET /search` (with body) | GET bodies are unreliable; long queries break URLs |

## Examples

Working implementations in `examples/`:
- **`examples/crud-endpoint-patterns.md`** — Complete CRUD implementation for an /orders resource showing correct method, route, status code, and request/response body for each operation in Node.js/Express and Python/FastAPI.
- **`examples/idempotency-key-middleware.md`** — Idempotency-Key header middleware that prevents duplicate POST operations, with implementations in Node.js/Express and Python/FastAPI.

## Review Checklist

When designing or reviewing API endpoints:

- [ ] Every GET handler is free of side effects — no writes, no emails, no counters
- [ ] POST endpoints return `201 Created` with a `Location` header for resource creation
- [ ] PUT endpoints require the full resource representation in the request body
- [ ] PATCH is used instead of PUT for partial updates
- [ ] DELETE returns `204 No Content` and is idempotent (succeeds even if resource is already gone)
- [ ] POST endpoints that create resources or charge money support the `Idempotency-Key` header
- [ ] Non-CRUD actions use `POST /resource/{id}/action`, not GET or custom verbs
- [ ] No verbs in resource URLs (`POST /orders`, not `POST /createOrder`)
- [ ] Status codes match the operation: 200 for success, 201 for creation, 204 for deletion, 404 for missing
- [ ] The decision framework table (method, idempotency, safety, cacheability) is documented in the API style guide
