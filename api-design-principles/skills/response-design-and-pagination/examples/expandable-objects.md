# Expandable Objects

Stripe-style `?expand[]=field` implementation where related objects are returned as bare IDs by default and inlined as full objects on request. Implementations in Node.js/Express and Python/FastAPI.

## Node.js / Express

```javascript
// middleware/expand.js

/**
 * Parse expand[] query parameters into a structured expansion map.
 *
 * Input:  ?expand[]=customer&expand[]=line_items.product
 * Output: ['customer', 'line_items.product']
 */
function parseExpand(req) {
  const raw = req.query['expand[]'] || req.query.expand || [];
  const expansions = Array.isArray(raw) ? raw : [raw];

  // Enforce limits
  if (expansions.length > 20) {
    return { error: 'Maximum 20 expand parameters per request.' };
  }

  for (const exp of expansions) {
    const depth = exp.split('.').length;
    if (depth > 4) {
      return { error: `Expansion "${exp}" exceeds maximum depth of 4 levels.` };
    }
  }

  return { expansions };
}

module.exports = { parseExpand };
```

```javascript
// services/expander.js

/**
 * Registry of expandable fields and their loaders.
 *
 * Each entry maps a resource type + field name to a function
 * that loads the related object by ID.
 */
const EXPANDABLE_FIELDS = {
  order: {
    customer: {
      loader: async (id) => db.customers.findById(id),
    },
    'line_items.product': {
      // Nested: expand product inside each line item
      loader: async (id) => db.products.findById(id),
    },
  },
  charge: {
    customer: {
      loader: async (id) => db.customers.findById(id),
    },
    invoice: {
      loader: async (id) => db.invoices.findById(id),
    },
  },
};

/**
 * Expand fields on a resource object based on the requested expansions.
 *
 * @param {object} resource - The resource object (with bare ID references)
 * @param {string} resourceType - e.g., 'order', 'charge'
 * @param {string[]} expansions - e.g., ['customer', 'line_items.product']
 * @param {number} depth - Current recursion depth (max 4)
 * @returns {object} Resource with expanded fields
 */
async function expandResource(resource, resourceType, expansions, depth = 0) {
  if (depth > 4 || !expansions.length) {
    return resource;
  }

  const result = { ...resource };
  const config = EXPANDABLE_FIELDS[resourceType] || {};

  for (const expansion of expansions) {
    const [field, ...rest] = expansion.split('.');
    const remaining = rest.join('.');

    // Handle list-level expansions: expand[]=data.customer
    if (field === 'data' && Array.isArray(result.data)) {
      const subExpansions = remaining ? [remaining] : [];
      result.data = await Promise.all(
        result.data.map((item) =>
          expandResource(item, resourceType, subExpansions, depth)
        )
      );
      continue;
    }

    // Check if this field is expandable
    if (!config[field] && !config[expansion]) {
      continue; // Silently skip non-expandable fields (Stripe behavior)
    }

    const value = result[field];

    if (typeof value === 'string') {
      // Field is a bare ID string -- hydrate it
      const loader = config[field]?.loader;
      if (loader) {
        const expanded = await loader(value);
        if (expanded) {
          result[field] = remaining
            ? await expandResource(expanded, field, [remaining], depth + 1)
            : expanded;
        }
      }
    } else if (Array.isArray(value) && remaining) {
      // Field is an array of objects -- expand nested fields on each item
      result[field] = await Promise.all(
        value.map((item) =>
          expandResource(item, field, [remaining], depth + 1)
        )
      );
    }
  }

  return result;
}

module.exports = { expandResource };
```

```javascript
// routes/orders.js
const express = require('express');
const router = express.Router();
const { parseExpand } = require('../middleware/expand');
const { expandResource } = require('../services/expander');
const db = require('../db');

/**
 * GET /v1/orders/:id
 * GET /v1/orders/:id?expand[]=customer&expand[]=line_items.product
 */
router.get('/v1/orders/:id', async (req, res) => {
  const { error, expansions } = parseExpand(req);
  if (error) {
    return res.status(400).json({
      type: 'https://api.example.com/errors/invalid-request',
      title: 'Invalid Request',
      status: 400,
      detail: error,
      code: 'invalid_expand',
    });
  }

  const order = await db.orders.findById(req.params.id);
  if (!order) {
    return res.status(404).json({
      type: 'https://api.example.com/errors/resource-not-found',
      title: 'Resource Not Found',
      status: 404,
      detail: `No order found with ID ${req.params.id}.`,
      code: 'order_not_found',
    });
  }

  // Without expand: customer is "cus_4QFJOjw2pOmAGJ"
  // With expand[]=customer: customer is { id: "cus_4QFJ...", name: "Ada", ... }
  const result = await expandResource(order, 'order', expansions);
  res.json(result);
});

/**
 * GET /v1/orders?expand[]=data.customer
 *
 * List endpoint with expand support.
 * Use "data." prefix to expand fields on list items.
 */
router.get('/v1/orders', async (req, res) => {
  const { error, expansions } = parseExpand(req);
  if (error) {
    return res.status(400).json({
      type: 'https://api.example.com/errors/invalid-request',
      title: 'Invalid Request',
      status: 400,
      detail: error,
      code: 'invalid_expand',
    });
  }

  const limit = Math.min(Math.max(parseInt(req.query.limit, 10) || 20, 1), 100);
  const after = req.query.after || null;

  const orders = await db.orders.list({ limit: limit + 1, after });
  const hasMore = orders.length > limit;
  const data = hasMore ? orders.slice(0, limit) : orders;

  // Build the list envelope, then expand
  let envelope = {
    data,
    has_more: hasMore,
    next_cursor: hasMore && data.length > 0 ? data[data.length - 1].id : null,
  };

  // Apply expansions (handles "data.customer" prefix)
  envelope = await expandResource(envelope, 'order', expansions);

  res.json(envelope);
});

/**
 * POST /v1/orders?expand[]=customer
 *
 * Create with expand -- return expanded data in the creation response.
 */
router.post('/v1/orders', async (req, res) => {
  const { error, expansions } = parseExpand(req);
  if (error) {
    return res.status(400).json({
      type: 'https://api.example.com/errors/invalid-request',
      title: 'Invalid Request',
      status: 400,
      detail: error,
      code: 'invalid_expand',
    });
  }

  const order = await db.orders.create(req.body);
  const result = await expandResource(order, 'order', expansions);

  res.status(201).header('Location', `/v1/orders/${order.id}`).json(result);
});

module.exports = router;
```

### Example responses

**Without expand:**
```bash
curl https://api.example.com/v1/orders/ord_01HXK3GJ5V
```

```json
{
  "id": "ord_01HXK3GJ5V",
  "customer": "cus_4QFJOjw2pOmAGJ",
  "status": "shipped",
  "total": 7900,
  "currency": "usd",
  "line_items": [
    { "id": "li_01ABC", "quantity": 2, "product": "prod_NWjs8kKb" },
    { "id": "li_01DEF", "quantity": 1, "product": "prod_MXrt7pLq" }
  ],
  "created_at": "2026-01-15T10:30:00Z",
  "updated_at": "2026-02-20T14:22:00Z"
}
```

**With expand:**
```bash
curl "https://api.example.com/v1/orders/ord_01HXK3GJ5V?expand[]=customer&expand[]=line_items.product"
```

```json
{
  "id": "ord_01HXK3GJ5V",
  "customer": {
    "id": "cus_4QFJOjw2pOmAGJ",
    "name": "Ada Lovelace",
    "email": "ada@example.com",
    "created_at": "2025-11-01T09:00:00Z",
    "updated_at": "2026-02-18T16:45:00Z"
  },
  "status": "shipped",
  "total": 7900,
  "currency": "usd",
  "line_items": [
    {
      "id": "li_01ABC",
      "quantity": 2,
      "product": {
        "id": "prod_NWjs8kKb",
        "name": "Pro Plan (Annual)",
        "price": 2900,
        "currency": "usd",
        "created_at": "2025-06-01T00:00:00Z",
        "updated_at": "2026-01-10T12:00:00Z"
      }
    },
    {
      "id": "li_01DEF",
      "quantity": 1,
      "product": {
        "id": "prod_MXrt7pLq",
        "name": "Add-on: Priority Support",
        "price": 2100,
        "currency": "usd",
        "created_at": "2025-08-15T00:00:00Z",
        "updated_at": "2025-12-20T09:30:00Z"
      }
    }
  ],
  "created_at": "2026-01-15T10:30:00Z",
  "updated_at": "2026-02-20T14:22:00Z"
}
```

---

## Python / FastAPI

```python
# middleware/expand.py
from fastapi import Query, HTTPException
from typing import Optional


def parse_expand(
    expand: Optional[list[str]] = Query(None, alias="expand[]"),
) -> list[str]:
    """
    Parse and validate expand[] query parameters.

    Usage in route:
        @router.get("/v1/orders/{order_id}")
        async def get_order(order_id: str, expansions: list[str] = Depends(parse_expand)):
    """
    if not expand:
        return []

    if len(expand) > 20:
        raise HTTPException(
            status_code=400,
            detail={
                "type": "https://api.example.com/errors/invalid-request",
                "title": "Invalid Request",
                "status": 400,
                "detail": "Maximum 20 expand parameters per request.",
                "code": "invalid_expand",
            },
        )

    for exp in expand:
        depth = len(exp.split("."))
        if depth > 4:
            raise HTTPException(
                status_code=400,
                detail={
                    "type": "https://api.example.com/errors/invalid-request",
                    "title": "Invalid Request",
                    "status": 400,
                    "detail": f'Expansion "{exp}" exceeds maximum depth of 4 levels.',
                    "code": "invalid_expand",
                },
            )

    return expand
```

```python
# services/expander.py
from typing import Any, Callable, Awaitable

# Registry: resource_type -> field_name -> loader function
LoaderFn = Callable[[str], Awaitable[dict | None]]

EXPANDABLE_FIELDS: dict[str, dict[str, LoaderFn]] = {}


def register_expandable(resource_type: str, field: str, loader: LoaderFn):
    """Register a field as expandable for a given resource type."""
    EXPANDABLE_FIELDS.setdefault(resource_type, {})[field] = loader


async def expand_resource(
    resource: dict[str, Any],
    resource_type: str,
    expansions: list[str],
    depth: int = 0,
) -> dict[str, Any]:
    """
    Recursively expand fields on a resource.

    - Bare ID strings are replaced with the full loaded object.
    - Nested expansions (e.g., "line_items.product") are resolved recursively.
    - List-level expansions use "data." prefix (e.g., "data.customer").
    - Max depth: 4 levels.
    """
    if depth > 4 or not expansions:
        return resource

    result = {**resource}
    config = EXPANDABLE_FIELDS.get(resource_type, {})

    for expansion in expansions:
        parts = expansion.split(".", 1)
        field = parts[0]
        remaining = parts[1] if len(parts) > 1 else None

        # Handle list-level expansions: expand[]=data.customer
        if field == "data" and isinstance(result.get("data"), list):
            sub = [remaining] if remaining else []
            result["data"] = [
                await expand_resource(item, resource_type, sub, depth)
                for item in result["data"]
            ]
            continue

        value = result.get(field)

        if isinstance(value, str) and field in config:
            # Field is a bare ID -- hydrate it
            loaded = await config[field](value)
            if loaded is not None:
                result[field] = (
                    await expand_resource(loaded, field, [remaining], depth + 1)
                    if remaining
                    else loaded
                )

        elif isinstance(value, list) and remaining:
            # Field is an array of objects -- expand nested fields
            nested_config = EXPANDABLE_FIELDS.get(field, {})
            if nested_config:
                result[field] = [
                    await expand_resource(item, field, [remaining], depth + 1)
                    for item in value
                ]

    return result
```

```python
# routes/orders.py
from fastapi import APIRouter, Depends, HTTPException
from typing import Optional
from middleware.expand import parse_expand
from services.expander import expand_resource, register_expandable
from db import orders_db, customers_db, products_db

router = APIRouter()

# Register expandable fields at module load time
register_expandable("order", "customer", customers_db.find_by_id)
register_expandable("line_items", "product", products_db.find_by_id)


@router.get("/v1/orders/{order_id}")
async def get_order(
    order_id: str,
    expansions: list[str] = Depends(parse_expand),
):
    """
    Get a single order.

    Without expand: customer is "cus_4QFJOjw2pOmAGJ"
    With ?expand[]=customer: customer is the full object.
    """
    order = await orders_db.find_by_id(order_id)
    if not order:
        raise HTTPException(
            status_code=404,
            detail={
                "type": "https://api.example.com/errors/resource-not-found",
                "title": "Resource Not Found",
                "status": 404,
                "detail": f"No order found with ID {order_id}.",
                "code": "order_not_found",
            },
        )

    return await expand_resource(order, "order", expansions)


@router.get("/v1/orders")
async def list_orders(
    limit: int = 20,
    after: Optional[str] = None,
    expansions: list[str] = Depends(parse_expand),
):
    """
    List orders with cursor pagination and expand support.

    Use expand[]=data.customer to expand customer on every list item.
    """
    limit = max(1, min(limit, 100))
    rows = await orders_db.list(limit=limit + 1, after=after)

    has_more = len(rows) > limit
    data = rows[:limit] if has_more else rows
    next_cursor = data[-1]["id"] if has_more and data else None

    envelope = {
        "data": data,
        "has_more": has_more,
        "next_cursor": next_cursor,
    }

    return await expand_resource(envelope, "order", expansions)
```

### Key implementation details

1. **Default to IDs, expand on request.** Every relationship field stores and returns a bare ID string. The expand middleware hydrates it to a full object only when explicitly requested.
2. **Batch loading.** The examples above load one object at a time for clarity. In production, use batch loading (similar to GraphQL's DataLoader) to avoid N+1 queries when expanding a field across a list of items. Collect all IDs first, fetch them in a single `WHERE id IN (...)` query, then distribute the results.
3. **Expand on mutations.** Support `?expand[]` on POST, PUT, and PATCH endpoints so clients get expanded data in the creation/update response without a second round trip.
4. **Silently ignore unknown expansions.** Following Stripe's behavior, skip fields that are not registered as expandable rather than returning an error. This allows clients to request expansions that may only exist in newer API versions.
5. **Depth limit.** Hard-cap at 4 levels of nesting. `?expand[]=customer.default_payment_method.card` (3 levels) is reasonable. Deeper chains create cascading database queries and unpredictable response sizes.
