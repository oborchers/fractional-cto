# Cursor-Based Pagination

Complete Stripe-style cursor pagination with `has_more` + `next_cursor`. Implementations in Node.js/Express and Python/FastAPI with real database queries.

## Node.js / Express + PostgreSQL

```javascript
// routes/orders.js
const express = require('express');
const router = express.Router();
const pool = require('../db'); // pg Pool instance

/**
 * GET /v1/orders?limit=20&after=ord_01HXK3GJ6W&before=ord_01HXK3GJ5V
 *
 * Returns a cursor-paginated list of orders.
 * Default sort: reverse chronological (newest first).
 */
router.get('/v1/orders', async (req, res) => {
  // 1. Parse and validate parameters
  const limit = Math.min(Math.max(parseInt(req.query.limit, 10) || 20, 1), 100);
  const after = req.query.after || null;   // cursor: fetch items older than this
  const before = req.query.before || null; // cursor: fetch items newer than this

  if (after && before) {
    return res.status(400).json({
      type: 'https://api.example.com/errors/invalid-request',
      title: 'Invalid Request',
      status: 400,
      detail: 'Cannot specify both "after" and "before" parameters.',
      code: 'invalid_pagination',
    });
  }

  try {
    let query;
    let params;

    if (after) {
      // Forward pagination: items older than the cursor
      // Fetch limit + 1 to determine has_more
      query = `
        SELECT id, customer_id, status, total, currency, created_at, updated_at
        FROM orders
        WHERE (created_at, id) < (
          SELECT created_at, id FROM orders WHERE id = $1
        )
        ORDER BY created_at DESC, id DESC
        LIMIT $2
      `;
      params = [after, limit + 1];
    } else if (before) {
      // Backward pagination: items newer than the cursor
      // Fetch in ascending order, then reverse for consistent output
      query = `
        SELECT id, customer_id, status, total, currency, created_at, updated_at
        FROM orders
        WHERE (created_at, id) > (
          SELECT created_at, id FROM orders WHERE id = $1
        )
        ORDER BY created_at ASC, id ASC
        LIMIT $2
      `;
      params = [before, limit + 1];
    } else {
      // First page: no cursor
      query = `
        SELECT id, customer_id, status, total, currency, created_at, updated_at
        FROM orders
        ORDER BY created_at DESC, id DESC
        LIMIT $1
      `;
      params = [limit + 1];
    }

    const result = await pool.query(query, params);
    let rows = result.rows;

    // 2. Determine has_more using the limit + 1 trick
    const hasMore = rows.length > limit;
    if (hasMore) {
      rows = rows.slice(0, limit); // Remove the extra row
    }

    // 3. Reverse rows if paginating backward (we fetched in ASC order)
    if (before) {
      rows.reverse();
    }

    // 4. Build the cursor from the last item
    const nextCursor = hasMore && rows.length > 0
      ? rows[rows.length - 1].id
      : null;

    // 5. Return consistent list envelope
    res.json({
      data: rows.map(formatOrder),
      has_more: hasMore,
      next_cursor: nextCursor,
    });
  } catch (err) {
    console.error('Pagination error:', err);
    res.status(500).json({
      type: 'https://api.example.com/errors/internal-error',
      title: 'Internal Server Error',
      status: 500,
      detail: 'An unexpected error occurred.',
      code: 'internal_error',
    });
  }
});

function formatOrder(row) {
  return {
    id: row.id,
    customer: row.customer_id, // bare ID; expandable via ?expand[]=customer
    status: row.status,
    total: row.total,
    currency: row.currency,
    created_at: row.created_at.toISOString(),
    updated_at: row.updated_at.toISOString(),
  };
}

module.exports = router;
```

### Required index

```sql
-- Composite index for efficient cursor pagination
-- Supports ORDER BY created_at DESC, id DESC
-- and WHERE (created_at, id) < (ts, id) range scans
CREATE INDEX idx_orders_pagination ON orders (created_at DESC, id DESC);
```

### Client usage

```javascript
// Client: paginate through all orders
async function fetchAllOrders() {
  let cursor = null;
  let allOrders = [];

  do {
    const url = new URL('https://api.example.com/v1/orders');
    url.searchParams.set('limit', '100');
    if (cursor) {
      url.searchParams.set('after', cursor);
    }

    const response = await fetch(url);
    const body = await response.json();

    allOrders.push(...body.data);
    cursor = body.has_more ? body.next_cursor : null;
  } while (cursor);

  return allOrders;
}
```

---

## Python / FastAPI + PostgreSQL (asyncpg)

```python
# routes/orders.py
from fastapi import APIRouter, Query, HTTPException
from typing import Optional
import asyncpg

router = APIRouter()

# Assume pool is initialized at app startup
# pool: asyncpg.Pool

MAX_LIMIT = 100
DEFAULT_LIMIT = 20


@router.get("/v1/orders")
async def list_orders(
    limit: int = Query(DEFAULT_LIMIT, ge=1, le=MAX_LIMIT),
    after: Optional[str] = Query(None, description="Cursor: return items after this ID"),
    before: Optional[str] = Query(None, description="Cursor: return items before this ID"),
):
    """
    List orders with cursor-based pagination.

    Returns a consistent envelope: { data, has_more, next_cursor }.
    Default sort: newest first (reverse chronological).
    """
    if after and before:
        raise HTTPException(
            status_code=400,
            detail={
                "type": "https://api.example.com/errors/invalid-request",
                "title": "Invalid Request",
                "status": 400,
                "detail": 'Cannot specify both "after" and "before" parameters.',
                "code": "invalid_pagination",
            },
        )

    # Fetch limit + 1 to determine has_more without a count query
    fetch_limit = limit + 1

    async with pool.acquire() as conn:
        if after:
            # Forward pagination: items older than the cursor
            rows = await conn.fetch(
                """
                SELECT id, customer_id, status, total, currency, created_at, updated_at
                FROM orders
                WHERE (created_at, id) < (
                    SELECT created_at, id FROM orders WHERE id = $1
                )
                ORDER BY created_at DESC, id DESC
                LIMIT $2
                """,
                after,
                fetch_limit,
            )
        elif before:
            # Backward pagination: items newer than the cursor
            rows = await conn.fetch(
                """
                SELECT id, customer_id, status, total, currency, created_at, updated_at
                FROM orders
                WHERE (created_at, id) > (
                    SELECT created_at, id FROM orders WHERE id = $1
                )
                ORDER BY created_at ASC, id ASC
                LIMIT $2
                """,
                before,
                fetch_limit,
            )
        else:
            # First page
            rows = await conn.fetch(
                """
                SELECT id, customer_id, status, total, currency, created_at, updated_at
                FROM orders
                ORDER BY created_at DESC, id DESC
                LIMIT $1
                """,
                fetch_limit,
            )

    rows = list(rows)

    # Determine has_more
    has_more = len(rows) > limit
    if has_more:
        rows = rows[:limit]

    # Reverse if backward pagination (fetched in ASC)
    if before:
        rows.reverse()

    # Build next_cursor from the last item
    next_cursor = rows[-1]["id"] if has_more and rows else None

    return {
        "data": [format_order(row) for row in rows],
        "has_more": has_more,
        "next_cursor": next_cursor,
    }


def format_order(row: asyncpg.Record) -> dict:
    return {
        "id": row["id"],
        "customer": row["customer_id"],
        "status": row["status"],
        "total": row["total"],
        "currency": row["currency"],
        "created_at": row["created_at"].isoformat(),
        "updated_at": row["updated_at"].isoformat(),
    }
```

### Optional: opaque Base64 cursor

When the sort column is not the ID (e.g., sorting by `total` or a custom field), use an opaque cursor that encodes the sort key and a tiebreaker:

```python
import base64
import json


def encode_cursor(row: dict, sort_field: str = "created_at") -> str:
    """Encode an opaque cursor from the last row in the result set."""
    cursor_data = {
        "s": str(row[sort_field]),  # sort key
        "id": row["id"],            # tiebreaker
    }
    return base64.urlsafe_b64encode(
        json.dumps(cursor_data, separators=(",", ":")).encode()
    ).decode().rstrip("=")


def decode_cursor(cursor: str) -> dict:
    """Decode an opaque cursor. Returns { s, id }."""
    # Restore Base64 padding
    padding = 4 - len(cursor) % 4
    if padding != 4:
        cursor += "=" * padding
    return json.loads(base64.urlsafe_b64decode(cursor))
```

### Key implementation details

1. **The `LIMIT + 1` trick.** Fetch one extra row. If returned, `has_more = true`; discard the extra row before responding. This avoids a separate `COUNT(*)` query.
2. **Composite `WHERE` clause.** `WHERE (created_at, id) < ($cursor_ts, $cursor_id)` uses a row-value comparison that PostgreSQL optimizes into an index seek on the composite index.
3. **Backward pagination reversal.** When paginating with `before`, fetch in ascending order to use the index efficiently, then reverse the result array before returning.
4. **Cursor as resource ID.** When IDs are time-sortable (ULID, KSUID, Stripe-style prefixed IDs), use the ID directly as the cursor. No encoding needed, fully debuggable. Fall back to Base64-encoded cursors when the sort order does not match the ID order.
