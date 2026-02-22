# URL Structure Patterns

Demonstrates correct route definitions for CRUD operations, nested resources, filtering, sorting, and action endpoints using plural nouns, shallow nesting, and query parameters for filters.

## Pseudocode

```
routes:
    # CRUD on a top-level collection (plural noun)
    GET    /users              → list_users(query_params: filters, sort, pagination)
    POST   /users              → create_user(body: user_data)
    GET    /users/{id}         → get_user(path: id)
    PATCH  /users/{id}         → update_user(path: id, body: partial_data)
    DELETE /users/{id}         → delete_user(path: id)

    # Nested sub-resource (max 2 levels)
    GET    /users/{id}/orders           → list_user_orders(path: user_id, query: filters)
    POST   /users/{id}/orders           → create_order_for_user(path: user_id, body: order_data)

    # Singleton sub-resource (singular noun)
    GET    /users/{id}/profile          → get_user_profile(path: user_id)
    PUT    /users/{id}/profile          → replace_user_profile(path: user_id, body: profile_data)

    # Flat access for globally unique resources
    GET    /orders/{id}                 → get_order(path: order_id)
    GET    /orders?user_id=42&status=pending  → list_orders(query: filters)

    # Action endpoint (verb as last segment)
    POST   /orders/{id}/cancel          → cancel_order(path: order_id, body: reason)

    # Filtering, sorting, pagination via query params
    GET    /products?category=electronics&price_min=100&sort=-created_at&limit=20&offset=0
```

## Node.js (Express)

```javascript
import express from "express";

const app = express();
app.use(express.json());

// ---------------------
// CRUD: Users (plural noun, no verbs in path)
// ---------------------

// List users with filtering, sorting, pagination
app.get("/users", async (req, res) => {
  const { role, status, sort = "-created_at", limit = 20, offset = 0 } = req.query;

  const filters = {};
  if (role) filters.role = role;
  if (status) filters.is_active = status === "active";

  const users = await db.users.findMany({
    where: filters,
    orderBy: parseSortParam(sort),
    take: Number(limit),
    skip: Number(offset),
  });

  res.json({ data: users, limit: Number(limit), offset: Number(offset) });
});

// Create a user
app.post("/users", async (req, res) => {
  const user = await db.users.create({ data: req.body });
  res.status(201).json(user);
});

// Get a single user by ID (path parameter)
app.get("/users/:id", async (req, res) => {
  const user = await db.users.findUnique({ where: { id: req.params.id } });
  if (!user) return res.status(404).json({ error: { message: "User not found" } });
  res.json(user);
});

// Partial update (PATCH, not PUT)
app.patch("/users/:id", async (req, res) => {
  const user = await db.users.update({
    where: { id: req.params.id },
    data: req.body,
  });
  res.json(user);
});

// Delete
app.delete("/users/:id", async (req, res) => {
  await db.users.delete({ where: { id: req.params.id } });
  res.status(204).end();
});

// ---------------------
// Nested sub-resource: User Orders (max 2 levels deep)
// ---------------------

// List orders for a specific user (scoped)
app.get("/users/:user_id/orders", async (req, res) => {
  const { status, sort = "-created_at", limit = 20 } = req.query;

  const filters = { user_id: req.params.user_id };
  if (status) filters.status = status;

  const orders = await db.orders.findMany({
    where: filters,
    orderBy: parseSortParam(sort),
    take: Number(limit),
  });

  res.json({ data: orders });
});

// Create an order for a user
app.post("/users/:user_id/orders", async (req, res) => {
  const order = await db.orders.create({
    data: { ...req.body, user_id: req.params.user_id },
  });
  res.status(201).json(order);
});

// ---------------------
// Flat access: Orders (globally unique IDs)
// ---------------------

// Get any order directly by its globally unique ID
app.get("/orders/:id", async (req, res) => {
  const order = await db.orders.findUnique({ where: { id: req.params.id } });
  if (!order) return res.status(404).json({ error: { message: "Order not found" } });
  res.json(order);
});

// List/filter orders across all users
app.get("/orders", async (req, res) => {
  const { user_id, status, created_gte, sort = "-created_at", limit = 20, offset = 0 } = req.query;

  const filters = {};
  if (user_id) filters.user_id = user_id;
  if (status) filters.status = status;
  if (created_gte) filters.created_at = { gte: new Date(created_gte) };

  const orders = await db.orders.findMany({
    where: filters,
    orderBy: parseSortParam(sort),
    take: Number(limit),
    skip: Number(offset),
  });

  res.json({ data: orders, limit: Number(limit), offset: Number(offset) });
});

// ---------------------
// Singleton sub-resource: User Profile (singular, no POST needed)
// ---------------------

app.get("/users/:user_id/profile", async (req, res) => {
  const profile = await db.profiles.findUnique({ where: { user_id: req.params.user_id } });
  if (!profile) return res.status(404).json({ error: { message: "Profile not found" } });
  res.json(profile);
});

app.put("/users/:user_id/profile", async (req, res) => {
  const profile = await db.profiles.upsert({
    where: { user_id: req.params.user_id },
    create: { ...req.body, user_id: req.params.user_id },
    update: req.body,
  });
  res.json(profile);
});

// ---------------------
// Action endpoint: Cancel Order (POST + verb as last segment)
// ---------------------

app.post("/orders/:id/cancel", async (req, res) => {
  const { reason } = req.body;
  const order = await db.orders.update({
    where: { id: req.params.id },
    data: { status: "cancelled", cancelled_at: new Date(), cancellation_reason: reason },
  });
  res.json(order);
});

// ---------------------
// Helper: Parse sort parameter ("-created_at" → { created_at: "desc" })
// ---------------------

function parseSortParam(sort) {
  const fields = sort.split(",").map((field) => {
    if (field.startsWith("-")) {
      return { [field.slice(1)]: "desc" };
    }
    return { [field]: "asc" };
  });
  return fields;
}
```

## Python (FastAPI)

```python
from datetime import datetime
from typing import Optional

from fastapi import FastAPI, HTTPException, Query, Path
from pydantic import BaseModel

app = FastAPI()


# ---------------------
# Models
# ---------------------

class UserCreate(BaseModel):
    email: str
    name: str
    role: str = "member"


class UserUpdate(BaseModel):
    email: Optional[str] = None
    name: Optional[str] = None
    role: Optional[str] = None


class OrderCreate(BaseModel):
    product_id: str
    quantity: int


class ProfileReplace(BaseModel):
    display_name: str
    bio: Optional[str] = None
    avatar_url: Optional[str] = None


class CancelRequest(BaseModel):
    reason: Optional[str] = None


# ---------------------
# CRUD: Users (plural noun, no verbs in path)
# ---------------------

@app.get("/users")
async def list_users(
    role: Optional[str] = Query(None),
    status: Optional[str] = Query(None),
    sort: str = Query("-created_at"),
    limit: int = Query(20, ge=1, le=100),
    offset: int = Query(0, ge=0),
):
    filters = {}
    if role:
        filters["role"] = role
    if status:
        filters["is_active"] = status == "active"

    users = await db.users.find_many(
        where=filters,
        order_by=parse_sort_param(sort),
        take=limit,
        skip=offset,
    )
    return {"data": users, "limit": limit, "offset": offset}


@app.post("/users", status_code=201)
async def create_user(body: UserCreate):
    user = await db.users.create(data=body.model_dump())
    return user


@app.get("/users/{user_id}")
async def get_user(user_id: str = Path(...)):
    user = await db.users.find_unique(where={"id": user_id})
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    return user


@app.patch("/users/{user_id}")
async def update_user(user_id: str, body: UserUpdate):
    update_data = body.model_dump(exclude_unset=True)
    user = await db.users.update(where={"id": user_id}, data=update_data)
    return user


@app.delete("/users/{user_id}", status_code=204)
async def delete_user(user_id: str):
    await db.users.delete(where={"id": user_id})


# ---------------------
# Nested sub-resource: User Orders (max 2 levels deep)
# ---------------------

@app.get("/users/{user_id}/orders")
async def list_user_orders(
    user_id: str,
    status: Optional[str] = Query(None),
    sort: str = Query("-created_at"),
    limit: int = Query(20, ge=1, le=100),
):
    filters = {"user_id": user_id}
    if status:
        filters["status"] = status

    orders = await db.orders.find_many(
        where=filters,
        order_by=parse_sort_param(sort),
        take=limit,
    )
    return {"data": orders}


@app.post("/users/{user_id}/orders", status_code=201)
async def create_order_for_user(user_id: str, body: OrderCreate):
    order = await db.orders.create(
        data={**body.model_dump(), "user_id": user_id},
    )
    return order


# ---------------------
# Flat access: Orders (globally unique IDs)
# ---------------------

@app.get("/orders/{order_id}")
async def get_order(order_id: str):
    order = await db.orders.find_unique(where={"id": order_id})
    if not order:
        raise HTTPException(status_code=404, detail="Order not found")
    return order


@app.get("/orders")
async def list_orders(
    user_id: Optional[str] = Query(None),
    status: Optional[str] = Query(None),
    created_gte: Optional[datetime] = Query(None),
    sort: str = Query("-created_at"),
    limit: int = Query(20, ge=1, le=100),
    offset: int = Query(0, ge=0),
):
    filters = {}
    if user_id:
        filters["user_id"] = user_id
    if status:
        filters["status"] = status
    if created_gte:
        filters["created_at"] = {"gte": created_gte}

    orders = await db.orders.find_many(
        where=filters,
        order_by=parse_sort_param(sort),
        take=limit,
        skip=offset,
    )
    return {"data": orders, "limit": limit, "offset": offset}


# ---------------------
# Singleton sub-resource: User Profile (singular, no POST needed)
# ---------------------

@app.get("/users/{user_id}/profile")
async def get_user_profile(user_id: str):
    profile = await db.profiles.find_unique(where={"user_id": user_id})
    if not profile:
        raise HTTPException(status_code=404, detail="Profile not found")
    return profile


@app.put("/users/{user_id}/profile")
async def replace_user_profile(user_id: str, body: ProfileReplace):
    profile = await db.profiles.upsert(
        where={"user_id": user_id},
        create={**body.model_dump(), "user_id": user_id},
        update=body.model_dump(),
    )
    return profile


# ---------------------
# Action endpoint: Cancel Order (POST + verb as last segment)
# ---------------------

@app.post("/orders/{order_id}/cancel")
async def cancel_order(order_id: str, body: CancelRequest):
    order = await db.orders.update(
        where={"id": order_id},
        data={
            "status": "cancelled",
            "cancelled_at": datetime.utcnow(),
            "cancellation_reason": body.reason,
        },
    )
    return order


# ---------------------
# Helper: Parse sort parameter ("-created_at" → [("created_at", "desc")])
# ---------------------

def parse_sort_param(sort: str) -> list[dict]:
    result = []
    for field in sort.split(","):
        if field.startswith("-"):
            result.append({field[1:]: "desc"})
        else:
            result.append({field: "asc"})
    return result
```

## Key Points

- Every collection uses a **plural noun**: `/users`, `/orders`, `/products` — never singular
- **No verbs in URLs** — the HTTP method (GET, POST, PATCH, DELETE) is the verb
- Nesting stops at **2 levels**: `/users/{id}/orders` is the deepest route; `/orders/{id}` provides flat access
- **Singleton sub-resources** use singular nouns (`/profile`, not `/profiles`) and need no POST endpoint
- **Path parameters** identify resources (`/users/42`); **query parameters** filter and sort (`?status=active&sort=-created_at`)
- The `-` prefix on sort fields means descending: `?sort=-created_at` (JSON:API convention)
- **Action endpoints** use `POST /resource/{id}/verb`: `/orders/{id}/cancel`, not `GET /cancelOrder`
- Both scoped (`/users/{id}/orders`) and flat (`/orders?user_id=42`) access can coexist for the same resource
