---
name: response-design-and-pagination
description: "This skill should be used when the user is designing API response formats, implementing pagination (cursor, offset, keyset), creating list endpoints, designing response envelopes, implementing expandable/embeddable objects, or structuring API output. Covers Stripe-style cursor pagination, consistent list envelopes, expand patterns, and response metadata."
version: 1.0.0
---

# Responses Are Contracts, Not Accidents

Every response your API returns is a contract. The moment a client parses it, the shape is frozen. Get it wrong and you carry the debt forever. Get it right -- consistent envelopes, stable pagination, predictable expand behavior -- and your API becomes a platform developers trust with production traffic.

Response design drives SDK generation, backward compatibility, and client-side caching. A well-structured response eliminates round trips, prevents breaking changes, and makes your API feel like a native library in every language.

## Single Resource Envelope

Return the full object on create and update. Always.

A POST that returns `{ "id": 42 }` forces a second GET to see what was created. A PATCH that returns `204 No Content` leaves the client guessing about server-side side effects like `updated_at` changes and computed defaults.

**Rules:**
- POST (201 Created): return the full resource plus a `Location` header
- PUT/PATCH (200 OK): return the full updated resource
- DELETE: return `204 No Content` or `200 OK` with a deletion confirmation object
- Include `created_at` and `updated_at` timestamps on every resource -- clients need them for display, sorting, and cache invalidation

**The resource shape must be identical everywhere it appears** -- in a GET, in a list, embedded in another resource, or returned from a mutation. If a compact form is needed, offer `?fields=id,name` rather than returning a different shape by default.

## List Envelope

Wrap every list response in a consistent envelope. Never return a naked top-level array.

**Use this structure for every list endpoint:**

```json
{
  "data": [
    { "id": "ord_01HXK3GJ5V", "status": "shipped", "created_at": "2026-01-15T10:30:00Z" },
    { "id": "ord_01HXK3GJ6W", "status": "pending", "created_at": "2026-01-14T08:15:00Z" }
  ],
  "has_more": true,
  "next_cursor": "ord_01HXK3GJ6W"
}
```

**Why this works:**
- `data` is always an array. Clients never check the type.
- `has_more` is a boolean that maps directly to "Load more" and "Show next page" UIs.
- `next_cursor` provides the opaque position marker for the next request.
- No `total_count` by default. Counting millions of rows is expensive and usually unnecessary. Offer it as an opt-in parameter (`?include_count=true`) when clients explicitly need it.

Stripe uses this envelope on every list endpoint across their entire API surface. The `object: "list"` discriminator and `url` field are additional Stripe conventions worth considering at scale -- they enable generic SDK deserialization without endpoint-specific knowledge.

## Pagination Strategy Comparison

| Aspect | Offset | Cursor (Opaque) | Keyset |
|--------|--------|-----------------|--------|
| **Query** | `?page=3&per_page=20` | `?limit=20&after=cursor_abc` | `?limit=20&created_after=2026-01-15T10:30:00Z` |
| **SQL** | `OFFSET 40 LIMIT 20` | `WHERE id < cursor ORDER BY id DESC LIMIT 21` | `WHERE (created_at, id) > (ts, id) LIMIT 21` |
| **Page 1 performance** | < 1ms | < 1ms | < 1ms |
| **Page 50,000 performance** | 500ms+ (O(n) -- scans and discards rows) | < 1ms (index seek) | < 1ms (index seek) |
| **Consistency under writes** | Items skipped or duplicated when rows are inserted/deleted between fetches | Stable -- cursor marks an exact position | Stable -- keyset marks an exact position |
| **Random page access** | Yes (`?page=47`) | No | No |
| **Total count** | Possible but expensive | Possible but expensive | Possible but expensive |
| **Client complexity** | Low | Low | Low-Medium |
| **Best for** | Admin UIs with "Page X of Y" requirements and small datasets | General-purpose API pagination (default choice) | Time-series data, event logs, audit trails |

## Cursor Pagination as the Default

Make cursor-based pagination the default for every list endpoint. It is O(1) at any page depth, consistent under concurrent writes, and trivial for clients to implement.

**Parameters:**
- `limit` -- Number of items to return (1-100, default 20)
- `after` -- Cursor marking the position to start after (for forward pagination)
- `before` -- Cursor marking the position to start before (for backward pagination)

**The `LIMIT + 1` trick:** Fetch one more item than requested. If you get `limit + 1` results, set `has_more: true` and return only `limit` items. If you get `limit` or fewer results, set `has_more: false`. This avoids a separate count query entirely.

**Stripe uses the resource ID as the cursor.** When IDs are naturally ordered (ULIDs, KSUIDs, or Stripe's own prefixed IDs), the ID itself serves as a perfect cursor -- no Base64 encoding needed, fully debuggable in logs. For APIs where the sort order does not align with the ID, use an opaque Base64-encoded cursor that encodes the sort key and a tiebreaker (typically the ID).

**Cursor opacity rule:** Clients must treat cursors as opaque strings. Document this explicitly. Even when the cursor is a plain resource ID, clients should not construct or parse cursors. This gives you the freedom to change the cursor encoding later without breaking clients.

## Expand/Embed Pattern

Default to returning references (IDs). Let clients request full objects with `?expand[]=field`.

**Without expand:**
```json
{
  "id": "ord_01HXK3GJ5V",
  "customer": "cus_4QFJOjw2pOmAGJ",
  "line_items": [
    { "id": "li_01ABC", "product": "prod_NWjs8kKb" }
  ]
}
```

**With `?expand[]=customer&expand[]=line_items.product`:**
```json
{
  "id": "ord_01HXK3GJ5V",
  "customer": {
    "id": "cus_4QFJOjw2pOmAGJ",
    "name": "Ada Lovelace",
    "email": "ada@example.com"
  },
  "line_items": [
    {
      "id": "li_01ABC",
      "product": {
        "id": "prod_NWjs8kKb",
        "name": "Pro Plan",
        "price": 4900
      }
    }
  ]
}
```

**Rules:**
- Limit expansion depth to 3-4 levels. Deeper expansions create performance and security risks.
- Cap the number of expand parameters per request (approximately 20).
- Document which fields are expandable. Not every reference should be expandable.
- Support expand on mutations (POST, PUT, PATCH) so clients get expanded data in the creation/update response without a second round trip.
- For list endpoints, use `?expand[]=data.customer` to expand fields on every item in the list.
- The expand pattern gives 80% of GraphQL's data-fetching benefit with 20% of the complexity. For most CRUD APIs, this is the right trade-off.

## Metadata and Timestamps

Every resource must include temporal metadata. Always.

**Required fields on every resource:**
- `id` -- Prefixed, globally unique identifier
- `created_at` -- ISO 8601 timestamp, set once at creation, never changes
- `updated_at` -- ISO 8601 timestamp, updated on every mutation

**Optional metadata fields:**
- `object` -- String type discriminator (`"customer"`, `"order"`) for polymorphic deserialization
- `deleted` -- Boolean, present on soft-deleted resources
- `metadata` -- Client-controlled key-value store for custom data (Stripe pattern)

Use ISO 8601 for all timestamps (`2026-02-22T10:30:00Z`). Unix timestamps are harder to read in logs and documentation. If you must support Unix timestamps, offer them as an alternative representation, not the primary one.

## Response Consistency Rules

1. **Same shape everywhere.** A customer object returned from `GET /customers/42`, listed in `GET /customers`, embedded in an order via expand, or returned from `POST /customers` must have the identical shape. No "summary" vs "detail" variants unless explicitly requested via `?fields=`.
2. **Null means absent, not undefined.** If a field has no value, return `null`. Never omit the key entirely -- clients that destructure the response will break.
3. **Empty collections are empty arrays, not null.** `"tags": []` not `"tags": null`. Clients should not need a null check before iterating.
4. **Stable field ordering is a courtesy.** JSON objects are unordered by spec, but returning fields in a consistent order (id first, timestamps last) makes responses easier to scan in logs and documentation.
5. **Never nest success data inside a `success` or `ok` wrapper.** Use HTTP status codes for success/failure signaling. `200` with `{ "success": false }` breaks HTTP semantics and is invisible to CDNs, monitoring tools, and client HTTP libraries.

## Pagination Parameters

Standardize pagination query parameters across all list endpoints:

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `limit` | integer | 20 | Items per page (1-100) |
| `after` | string | -- | Cursor: return items after this position |
| `before` | string | -- | Cursor: return items before this position |
| `include_count` | boolean | false | Opt-in total count (expensive) |

**Filtering and sorting apply before pagination.** If a client requests `?status=active&sort=created_at&limit=20&after=cursor`, the server filters to active items, sorts by `created_at`, then paginates from the cursor position.

**Enforce a maximum `limit`.** Without a cap, a client requesting `?limit=1000000` can exhaust server resources. Cap at 100 for most endpoints. Document the cap. Return `400` if exceeded.

**Store pagination state in URLs.** Every paginated response should include enough information for the client to construct the next request. The `next_cursor` value plus the documented parameter name (`after`) is sufficient. Some APIs go further and return full next/previous URLs -- this is a convenience but couples the response to a specific domain.

## Examples

Working implementations in `examples/`:
- **`examples/cursor-pagination.md`** -- Complete cursor-based pagination with Stripe-style `has_more` + `next_cursor`, in Node.js/Express and Python/FastAPI with database queries
- **`examples/expandable-objects.md`** -- Expand pattern implementation where `?expand[]=customer` inlines the full customer object instead of just the ID, in Node.js and Python

## Review Checklist

When reviewing or building API response formats:

- [ ] POST returns 201 with the full created resource and a `Location` header
- [ ] PUT/PATCH returns 200 with the full updated resource
- [ ] Every resource includes `id`, `created_at`, and `updated_at`
- [ ] List endpoints use a consistent envelope: `{ data: [], has_more, next_cursor }`
- [ ] Pagination is cursor-based by default (not offset-based)
- [ ] `limit` parameter is capped (max 100) and documented
- [ ] `has_more` is determined using the `LIMIT + 1` fetch trick (no separate count query)
- [ ] `total_count` is opt-in, not included by default
- [ ] Clients can request expanded related objects via `?expand[]=field`
- [ ] Expansion depth is limited (3-4 levels max)
- [ ] Resource shape is identical everywhere it appears (GET, list, embed, mutation response)
- [ ] Empty collections return `[]`, not `null`
