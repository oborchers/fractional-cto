---
name: prefixed-ids
description: "This skill should be used when the user is designing ID formats for API resources, implementing type-safe identifiers, choosing between UUID and prefixed IDs, generating IDs with KSUID or ULID, creating ID validation, or following Stripe's prefixed ID pattern. Covers prefix conventions, ID generation, validation, and debugging benefits."
version: 1.0.0
---

# Every ID Should Declare Its Type

When a support engineer sees `cus_NffrFeUfNV2Hib` in a log line, they know it is a customer. When they see `550e8400-e29b-41d4-a716-446655440000`, they know nothing. Stripe prefixes every ID with a short type indicator, and that seemingly small decision compounds across debugging, routing, type safety, log analysis, and cross-service communication. Adopt this pattern for every resource in your API.

## The Prefix Pattern

Every ID follows the format `{type}_{random}`:

```
cus_NffrFeUfNV2Hib          -- customer
ord_01HXK3GJ5V8WJKPT2MNR   -- order
pi_3MtwBwLkdIwHu7ix28a3     -- payment intent
```

The prefix is a short, lowercase abbreviation of the resource type. The underscore is a fixed separator. The random part is a collision-resistant, alphanumeric string.

## Format Rules

Follow these constraints for every prefixed ID:

- **Prefix length:** 2-5 lowercase characters. Short enough to read at a glance, long enough to be unambiguous.
- **Separator:** Always a single underscore. Never a hyphen, colon, or dot.
- **Random part:** Base62 characters (`a-zA-Z0-9`). URL-safe, no special characters. 14-24 characters depending on the generation strategy.
- **Total length:** 18-30 characters. Short enough to paste in Slack, long enough to be collision-free.

## Prefix Catalog

Define a canonical prefix for every resource type in your API. Maintain this as a living registry -- never reuse a prefix for a different resource.

| Prefix | Resource | Example |
|--------|----------|---------|
| `usr_` | User | `usr_01HXK3GJ5V8WJKP` |
| `org_` | Organization | `org_2ZutauDiLLuKvLgb` |
| `ord_` | Order | `ord_01ARZ3NDEKTSV4RR` |
| `prod_` | Product | `prod_NWjs8kKbJWmuuc` |
| `inv_` | Invoice | `inv_1MtHbELkdIwHu7ix` |
| `pay_` | Payment | `pay_3MtwBwLkdIwHu7ix` |
| `sub_` | Subscription | `sub_1MowQVLkdIwHu7ix` |
| `wh_` | Webhook Endpoint | `wh_1MqVTHLkdIwHu7ix` |
| `evt_` | Event | `evt_9Kx2mPbQ7rTvYw4j` |
| `sess_` | Session | `sess_2dH3VUuCJRx7wnlv` |
| `tok_` | Token | `tok_1MioVOLkdIwHu7ix` |
| `key_` | API Key | `key_4eC39HqLyjWDarjt` |
| `cus_` | Customer | `cus_NffrFeUfNV2Hib` |
| `price_` | Price | `price_1MoBy5LkdIwHu7ix` |
| `txn_` | Transaction | `txn_3MmlLrLkdIwHu7ix` |

## ID Generation: Choosing the Random Part

The prefix gives you type safety. The random part must give you uniqueness, collision resistance, and ideally time-sortability. Pick one strategy and use it everywhere.

| Strategy | Sortable | Length (with prefix) | URL-Safe | Best For |
|----------|----------|---------------------|----------|----------|
| **ULID** | Yes (ms) | ~30 chars | Yes (Crockford Base32) | General-purpose API IDs. B-tree friendly, chronological `ORDER BY id`. |
| **KSUID** | Yes (sec) | ~31 chars | Yes (Base62) | High-entropy IDs with time sorting. 128 bits of randomness per second. |
| **nanoid** | No | ~28 chars | Yes | Short IDs where time ordering is irrelevant. Smallest library. |
| **UUID v7** | Yes (ms) | ~36 chars | No (hex) | Standards compliance. Broad ecosystem support. Longer than alternatives. |

**Recommendation:** Use ULID or KSUID. Time-sortability means `created_at` is embedded in the ID itself, which enables cursor-based pagination without a separate timestamp column. Both produce sequential values that avoid random B-tree page splits, giving you better database write performance than UUID v4 or nanoid.

Do not use UUID v4. It is universally supported but completely opaque, not sortable, and unnecessarily long.

**Implementation pattern:**

```typescript
import { ulid } from "ulid";

function generateId(prefix: string): string {
  return `${prefix}_${ulid()}`;
}

generateId("cus");  // "cus_01HXK3GJ5V8WJKPT2MNR9QZK1"
generateId("ord");  // "ord_01HXK3GK7RABCDE8FGHJ3KLMN"
```

The ULID portion encodes a millisecond timestamp in the first 10 characters (Crockford Base32), followed by 16 characters of cryptographic randomness. IDs generated within the same millisecond are lexicographically ordered by their random component, which means `ORDER BY id` gives you chronological order without a separate `created_at` index.

## Database Considerations

Store prefixed IDs as `TEXT` or `VARCHAR` columns, not as binary. The human-readability of prefixed IDs is their primary advantage -- converting them to binary for storage defeats the purpose and makes database debugging harder.

**Primary key indexing.** Time-sortable random parts (ULID, KSUID) produce monotonically increasing values within each prefix. This means inserts append to the end of the B-tree index rather than causing random page splits. The result is significantly better write throughput than UUID v4, which scatters inserts across the entire index.

**Querying by type.** Because all IDs for a given resource share the same prefix, you can filter by type with a prefix scan: `WHERE id LIKE 'cus_%'`. This is efficient on a B-tree index because the shared prefix means all matching rows are physically adjacent.

**Foreign keys.** Prefixed IDs work normally as foreign keys. The prefix adds a few bytes of overhead per row, but the debugging benefits far outweigh the marginal storage cost. A typical prefixed ID with ULID is 30 characters -- comparable to a UUID's 36 characters with hyphens.

## Validation

Validate prefixed IDs at the API boundary before touching the database. A `pi_` ID passed to a `/customers` endpoint should return a 400 immediately -- no query needed.

**Regex pattern for validation:**

```
^[a-z]{2,5}_[a-zA-Z0-9]{14,27}$
```

This catches the prefix (2-5 lowercase letters), the underscore separator, and the random part (14-27 alphanumeric characters). Adjust the random part length to match your generation strategy.

**Type-specific validation:** Check that the prefix matches the expected resource type for the endpoint. If the route is `/v1/customers/:id`, the ID must start with `cus_`. If it starts with `ord_`, reject it with a clear error message:

```
{
  "error": {
    "type": "invalid_request_error",
    "message": "Expected customer ID (prefix 'cus_'), got 'ord_01HXK3GJ5V8WJKP'"
  }
}
```

This eliminates an entire class of bugs where IDs are passed to the wrong endpoint. Without prefixes, a bare UUID sent to the wrong endpoint produces a confusing "not found" error instead of a clear type mismatch.

**Request body validation.** Apply the same validation to IDs in request bodies, not just path parameters. When a client sends `{ "customer_id": "ord_abc123" }` in a POST body, reject it immediately. The prefix makes the mismatch detectable without a database round-trip.

**Polymorphic ID resolution.** In webhook payloads, event logs, and audit trails, a single field may contain IDs of different types. Use the prefix to route to the correct handler:

```typescript
function resolveResource(id: string) {
  const parsed = parseId(id);
  switch (parsed.prefix) {
    case "cus": return customerService.get(id);
    case "ord": return orderService.get(id);
    case "inv": return invoiceService.get(id);
    default:   throw new Error(`Unknown resource type: ${parsed.prefix}`);
  }
}
```

## Why This Matters: The Debugging Multiplier

Prefixed IDs pay dividends across every layer of the stack:

**Log analysis.** Grep your application logs for `pi_` to find all payment intent activity. Grep for `cus_` to trace a customer's journey. With bare UUIDs, you need surrounding context to know what a log entry refers to.

```bash
# Find all payment-related activity
grep "pay_" /var/log/app.log

# Count orders vs. invoices in today's logs
grep -c "ord_" /var/log/app/2026-02-22.log
grep -c "inv_" /var/log/app/2026-02-22.log
```

**Support tickets.** When a user pastes `ord_01ARZ3NDEKTSV4RR` into a support ticket, the agent immediately knows this is an order and navigates to the orders dashboard. No database lookup to determine the resource type.

**Cross-service communication.** In a microservices architecture, IDs flow through queues, events, and caches. A prefixed ID is self-describing -- any service that encounters it knows what type of resource it references without parsing surrounding context.

**Preventing cross-type confusion.** Without prefixes, passing a user ID where an order ID is expected is a silent bug that produces a "not found" error. With prefixes, the mismatch is caught at the API boundary with a clear, actionable error.

**Observability dashboards.** Build Datadog, Splunk, or CloudWatch queries that filter by prefix. A query for `pi_3MtwBw*` immediately scopes to a single payment intent. A query for `evt_` surfaces all events. This works because the prefix is embedded in the value itself, not in metadata that might be missing from some log entries.

## Anti-Patterns

**Auto-incrementing integers.** They leak volume information (customer #50,000 tells competitors your scale), enable enumeration attacks (trivial to scrape `/users/1` through `/users/50000`), and are not globally unique across services or tables. Never expose sequential integers in a public API.

**Bare UUIDs.** `550e8400-e29b-41d4-a716-446655440000` is globally unique but tells you nothing about what it represents. Every log line, support ticket, and queue message requires additional context to interpret. UUID v4 also produces random values that cause B-tree page splits in database indexes.

**Inconsistent formats.** Mixing prefixed IDs for some resources, UUIDs for others, and integers for the rest creates cognitive overhead for every developer who touches the API. Pick one format and enforce it everywhere.

**Reusing prefixes.** If `usr_` once meant "user" and you repurpose it for "usage record," every existing log, support script, and integration breaks. Prefixes are permanent. Retire them; never reassign.

**Underscores in prefixes.** The prefix `sub_sched_` is ambiguous -- is the prefix `sub` or `sub_sched`? Keep prefixes as single tokens without underscores. Use a distinct abbreviation instead (e.g., `schd_` for subscription schedule).

## Examples

Working implementations in `examples/`:
- **`examples/prefixed-id-generator.md`** -- Complete ID generation utility with prefix registry, generation, validation, and parsing in Node.js and Python
- **`examples/id-middleware-validation.md`** -- Express and FastAPI middleware that validates prefixed IDs in route params, returning 400 on invalid format

## Review Checklist

When reviewing code that handles resource IDs:

- [ ] Every resource type has a registered prefix in the prefix catalog
- [ ] All IDs follow the `{prefix}_{random}` format with an underscore separator
- [ ] Prefixes are 2-5 lowercase characters with no underscores
- [ ] The random part uses a time-sortable strategy (ULID or KSUID preferred)
- [ ] ID validation happens at the API boundary, before any database query
- [ ] Type mismatches return a 400 error with a message naming the expected prefix
- [ ] No auto-incrementing integers are exposed in any public-facing endpoint
- [ ] No bare UUIDs are used as primary identifiers in API responses
- [ ] The prefix catalog is maintained as a single source of truth in code
- [ ] IDs are URL-safe (no special characters beyond the underscore separator)
- [ ] No prefix is reused or reassigned to a different resource type
- [ ] Cross-service messages include prefixed IDs that are self-describing
