# CRUD Endpoint Patterns for /orders

Complete CRUD implementation for an orders resource showing the correct HTTP method, route, status code, request body, and response body for each operation. Every endpoint follows the rules from the HTTP Methods skill: GET is safe, POST returns 201 with Location, PATCH for partial updates, DELETE returns 204, and status codes match the operation semantics.

## Pseudocode

```
RESOURCE: /orders

LIST    → GET    /orders?status=pending&sort=-created_at  → 200 OK (array)
CREATE  → POST   /orders                                   → 201 Created + Location header
READ    → GET    /orders/{id}                              → 200 OK (object)
UPDATE  → PATCH  /orders/{id}                              → 200 OK (updated object)
REPLACE → PUT    /orders/{id}                              → 200 OK (replaced object)
DELETE  → DELETE /orders/{id}                              → 204 No Content
ACTION  → POST   /orders/{id}/cancel                       → 200 OK (state change)

Status code rules:
  201 → resource created (POST that creates)
  200 → resource returned or updated
  204 → resource deleted, no body
  404 → resource not found
  422 → validation failed
```

## Node.js (Express)

```javascript
import express from "express";
import crypto from "crypto";

const app = express();
app.use(express.json());

// In-memory store for demonstration
const orders = new Map();

function generateId() {
  return `ord_${crypto.randomBytes(12).toString("base64url")}`;
}

// LIST — GET /orders
// Safe, idempotent, cacheable. Query params for filtering and sorting.
app.get("/orders", (req, res) => {
  const { status, sort, limit = "20", offset = "0" } = req.query;

  let results = Array.from(orders.values());

  // Filter by status
  if (status) {
    results = results.filter((o) => o.status === status);
  }

  // Sort (prefix "-" for descending)
  if (sort) {
    const desc = sort.startsWith("-");
    const field = desc ? sort.slice(1) : sort;
    results.sort((a, b) => {
      if (a[field] < b[field]) return desc ? 1 : -1;
      if (a[field] > b[field]) return desc ? -1 : 1;
      return 0;
    });
  }

  const total = results.length;
  results = results.slice(Number(offset), Number(offset) + Number(limit));

  res.status(200).json({
    object: "list",
    total_count: total,
    has_more: Number(offset) + results.length < total,
    data: results,
  });
});

// CREATE — POST /orders
// Not idempotent. Returns 201 with Location header.
app.post("/orders", (req, res) => {
  const { customer_id, items, shipping_address } = req.body;

  if (!customer_id || !items || items.length === 0) {
    return res.status(422).json({
      error: {
        type: "validation_error",
        message: "customer_id and at least one item are required.",
        params: ["customer_id", "items"],
      },
    });
  }

  const id = generateId();
  const now = new Date().toISOString();

  const order = {
    id,
    object: "order",
    customer_id,
    items,
    shipping_address: shipping_address || null,
    status: "pending",
    total_amount: items.reduce((sum, i) => sum + i.amount * i.quantity, 0),
    currency: "usd",
    created_at: now,
    updated_at: now,
  };

  orders.set(id, order);

  res.status(201).location(`/orders/${id}`).json(order);
});

// READ — GET /orders/:id
// Safe, idempotent. Returns 200 or 404.
app.get("/orders/:id", (req, res) => {
  const order = orders.get(req.params.id);

  if (!order) {
    return res.status(404).json({
      error: {
        type: "not_found_error",
        message: `Order ${req.params.id} not found.`,
      },
    });
  }

  res.status(200).json(order);
});

// PARTIAL UPDATE — PATCH /orders/:id
// Only updates the fields provided. All other fields preserved.
app.patch("/orders/:id", (req, res) => {
  const order = orders.get(req.params.id);

  if (!order) {
    return res.status(404).json({
      error: {
        type: "not_found_error",
        message: `Order ${req.params.id} not found.`,
      },
    });
  }

  // Only allow specific fields to be patched
  const allowedFields = ["shipping_address", "items", "status"];
  const updates = {};

  for (const field of allowedFields) {
    if (req.body[field] !== undefined) {
      updates[field] = req.body[field];
    }
  }

  // Recalculate total if items changed
  if (updates.items) {
    updates.total_amount = updates.items.reduce(
      (sum, i) => sum + i.amount * i.quantity,
      0
    );
  }

  const updated = {
    ...order,
    ...updates,
    updated_at: new Date().toISOString(),
  };

  orders.set(req.params.id, updated);

  res.status(200).json(updated);
});

// FULL REPLACE — PUT /orders/:id
// Idempotent. Client must send the complete representation.
app.put("/orders/:id", (req, res) => {
  const { customer_id, items, shipping_address, status } = req.body;

  if (!customer_id || !items) {
    return res.status(422).json({
      error: {
        type: "validation_error",
        message:
          "PUT requires the complete resource: customer_id, items, shipping_address, status.",
      },
    });
  }

  const existing = orders.get(req.params.id);
  const now = new Date().toISOString();

  const order = {
    id: req.params.id,
    object: "order",
    customer_id,
    items,
    shipping_address: shipping_address || null,
    status: status || "pending",
    total_amount: items.reduce((sum, i) => sum + i.amount * i.quantity, 0),
    currency: "usd",
    created_at: existing ? existing.created_at : now,
    updated_at: now,
  };

  orders.set(req.params.id, order);

  // 201 if created, 200 if replaced
  const statusCode = existing ? 200 : 201;
  res.status(statusCode).json(order);
});

// DELETE — DELETE /orders/:id
// Idempotent. Returns 204 whether the resource existed or not.
app.delete("/orders/:id", (req, res) => {
  orders.delete(req.params.id);

  // 204 No Content — no response body
  res.status(204).end();
});

// ACTION — POST /orders/:id/cancel
// Non-CRUD action modeled as a sub-resource verb.
app.post("/orders/:id/cancel", (req, res) => {
  const order = orders.get(req.params.id);

  if (!order) {
    return res.status(404).json({
      error: {
        type: "not_found_error",
        message: `Order ${req.params.id} not found.`,
      },
    });
  }

  if (order.status === "cancelled") {
    // Already cancelled — return current state
    return res.status(200).json(order);
  }

  if (order.status === "shipped") {
    return res.status(422).json({
      error: {
        type: "invalid_state_error",
        message: "Cannot cancel a shipped order. Use POST /orders/:id/refund.",
      },
    });
  }

  const updated = {
    ...order,
    status: "cancelled",
    cancelled_at: new Date().toISOString(),
    updated_at: new Date().toISOString(),
  };

  orders.set(req.params.id, updated);

  res.status(200).json(updated);
});

app.listen(3000);
```

## Python (FastAPI)

```python
from datetime import datetime, timezone
from uuid import uuid4

from fastapi import FastAPI, HTTPException, Query, Response
from pydantic import BaseModel

app = FastAPI()

# In-memory store for demonstration
orders: dict[str, dict] = {}


def generate_id() -> str:
    return f"ord_{uuid4().hex[:24]}"


class OrderItem(BaseModel):
    product_id: str
    amount: int
    quantity: int


class CreateOrderRequest(BaseModel):
    customer_id: str
    items: list[OrderItem]
    shipping_address: str | None = None


class UpdateOrderRequest(BaseModel):
    shipping_address: str | None = None
    items: list[OrderItem] | None = None
    status: str | None = None


class ReplaceOrderRequest(BaseModel):
    customer_id: str
    items: list[OrderItem]
    shipping_address: str | None = None
    status: str = "pending"


# LIST — GET /orders
# Safe, idempotent, cacheable.
@app.get("/orders")
def list_orders(
    status: str | None = None,
    sort: str | None = None,
    limit: int = Query(default=20, le=100),
    offset: int = Query(default=0, ge=0),
):
    results = list(orders.values())

    # Filter
    if status:
        results = [o for o in results if o["status"] == status]

    # Sort (prefix "-" for descending)
    if sort:
        desc = sort.startswith("-")
        field = sort.lstrip("-")
        results.sort(key=lambda o: o.get(field, ""), reverse=desc)

    total = len(results)
    page = results[offset : offset + limit]

    return {
        "object": "list",
        "total_count": total,
        "has_more": offset + len(page) < total,
        "data": page,
    }


# CREATE — POST /orders
# Not idempotent. Returns 201 with Location header.
@app.post("/orders", status_code=201)
def create_order(body: CreateOrderRequest, response: Response):
    if not body.items:
        raise HTTPException(
            status_code=422,
            detail="At least one item is required.",
        )

    order_id = generate_id()
    now = datetime.now(timezone.utc).isoformat()

    order = {
        "id": order_id,
        "object": "order",
        "customer_id": body.customer_id,
        "items": [item.model_dump() for item in body.items],
        "shipping_address": body.shipping_address,
        "status": "pending",
        "total_amount": sum(i.amount * i.quantity for i in body.items),
        "currency": "usd",
        "created_at": now,
        "updated_at": now,
    }

    orders[order_id] = order

    response.headers["Location"] = f"/orders/{order_id}"
    return order


# READ — GET /orders/{order_id}
# Safe, idempotent.
@app.get("/orders/{order_id}")
def get_order(order_id: str):
    order = orders.get(order_id)
    if not order:
        raise HTTPException(status_code=404, detail=f"Order {order_id} not found.")
    return order


# PARTIAL UPDATE — PATCH /orders/{order_id}
# Only updates the fields provided.
@app.patch("/orders/{order_id}")
def update_order(order_id: str, body: UpdateOrderRequest):
    order = orders.get(order_id)
    if not order:
        raise HTTPException(status_code=404, detail=f"Order {order_id} not found.")

    updates = body.model_dump(exclude_unset=True)

    if "items" in updates:
        items = [OrderItem(**i) for i in updates["items"]]
        updates["total_amount"] = sum(i.amount * i.quantity for i in items)

    order.update(updates)
    order["updated_at"] = datetime.now(timezone.utc).isoformat()

    return order


# FULL REPLACE — PUT /orders/{order_id}
# Idempotent. Client must send the complete representation.
@app.put("/orders/{order_id}")
def replace_order(order_id: str, body: ReplaceOrderRequest, response: Response):
    existing = orders.get(order_id)
    now = datetime.now(timezone.utc).isoformat()

    order = {
        "id": order_id,
        "object": "order",
        "customer_id": body.customer_id,
        "items": [item.model_dump() for item in body.items],
        "shipping_address": body.shipping_address,
        "status": body.status,
        "total_amount": sum(i.amount * i.quantity for i in body.items),
        "currency": "usd",
        "created_at": existing["created_at"] if existing else now,
        "updated_at": now,
    }

    orders[order_id] = order

    if not existing:
        response.status_code = 201
    return order


# DELETE — DELETE /orders/{order_id}
# Idempotent. Returns 204 whether or not the resource existed.
@app.delete("/orders/{order_id}", status_code=204)
def delete_order(order_id: str):
    orders.pop(order_id, None)
    return Response(status_code=204)


# ACTION — POST /orders/{order_id}/cancel
# Non-CRUD action as sub-resource verb.
@app.post("/orders/{order_id}/cancel")
def cancel_order(order_id: str):
    order = orders.get(order_id)
    if not order:
        raise HTTPException(status_code=404, detail=f"Order {order_id} not found.")

    if order["status"] == "cancelled":
        return order

    if order["status"] == "shipped":
        raise HTTPException(
            status_code=422,
            detail="Cannot cancel a shipped order. Use POST /orders/{id}/refund.",
        )

    now = datetime.now(timezone.utc).isoformat()
    order["status"] = "cancelled"
    order["cancelled_at"] = now
    order["updated_at"] = now

    return order
```

## Key Points

- **POST /orders returns 201 Created** with a `Location` header — never 200 for resource creation.
- **PATCH sends only changed fields.** The server merges them into the existing resource. All other fields stay untouched.
- **PUT sends the complete resource.** Missing fields are reset to defaults. This is the correct behavior; if you do not want it, use PATCH.
- **DELETE returns 204 No Content** with an empty body. Deleting a non-existent resource still returns 204 (idempotent).
- **Actions use POST on a sub-resource verb** (`POST /orders/{id}/cancel`), not DELETE or GET.
- **422 Unprocessable Entity** for validation errors — the syntax is valid JSON, but the content fails business rules.
- **Prefixed IDs** (`ord_...`) make log grep and debugging immediate — you know it is an order without looking it up.
