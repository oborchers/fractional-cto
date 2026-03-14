# Field Naming Conventions

Demonstrates consistent snake_case JSON field naming with boolean prefixes (`is_`, `has_`, `can_`, `should_`, `allow_`), timestamp suffixes (`_at`), descriptive enum values, and no abbreviations.

## Pseudocode

```
model User:
    id:              string        # prefixed ID: "usr_a8Tk3mRp..."
    email:           string
    display_name:    string        # snake_case, spelled out (not "disp_name")
    organization_id: string        # full word, not "org_id" or "org_ref"
    role:            enum          # "admin", "member", "viewer" (lowercase strings)
    is_active:       boolean       # "is_" prefix for state
    is_verified:     boolean       # "is_" prefix for state
    has_two_factor:  boolean       # "has_" prefix for possession
    can_create_repos: boolean      # "can_" prefix for ability
    should_notify:   boolean       # "should_" prefix for preference/setting
    allow_comments:  boolean       # "allow_" prefix for permission setting
    created_at:      datetime      # "_at" suffix, ISO 8601 UTC
    updated_at:      datetime      # "_at" suffix, ISO 8601 UTC
    last_login_at:   datetime      # "_at" suffix for timestamps
    deleted_at:      datetime|null # null means not deleted (soft-delete)

model Order:
    id:                  string    # "ord_xYz..."
    user_id:             string    # foreign key uses full resource name + "_id"
    status:              enum      # "pending", "confirmed", "shipped", "delivered", "cancelled"
    shipping_method:     enum      # "standard_delivery", "express_delivery" (not "exp-dlvry")
    is_gift:             boolean
    has_tracking_number: boolean
    total_amount:        integer   # amount in smallest currency unit (cents)
    currency:            string    # "usd", "eur" (ISO 4217 lowercase)
    created_at:          datetime
    shipped_at:          datetime|null
    delivered_at:        datetime|null
    cancelled_at:        datetime|null

example JSON response:
{
    "id": "ord_7kPmNqRs2vXwYz",
    "user_id": "usr_a8Tk3mRpBxYvQn",
    "status": "shipped",
    "shipping_method": "express_delivery",
    "is_gift": false,
    "has_tracking_number": true,
    "total_amount": 4999,
    "currency": "usd",
    "created_at": "2024-01-15T10:30:00Z",
    "shipped_at": "2024-01-17T14:22:33Z",
    "delivered_at": null,
    "cancelled_at": null
}
```

## Node.js (Express)

```javascript
// ---------------------
// Response serializer: ensures consistent field naming
// ---------------------

function serializeUser(user) {
  return {
    id: user.id,                           // "usr_a8Tk3mRp..."
    email: user.email,
    display_name: user.display_name,       // snake_case, not displayName
    organization_id: user.organization_id, // full word, not org_id
    role: user.role,                       // "admin" | "member" | "viewer"
    is_active: user.is_active,             // boolean with is_ prefix
    is_verified: user.is_verified,
    has_two_factor: user.has_two_factor,   // boolean with has_ prefix
    can_create_repos: user.can_create_repos, // boolean with can_ prefix
    created_at: user.created_at,           // ISO 8601: "2024-01-15T10:30:00Z"
    updated_at: user.updated_at,
    last_login_at: user.last_login_at,
  };
}

function serializeOrder(order) {
  return {
    id: order.id,                             // "ord_7kPmNqRs..."
    user_id: order.user_id,                   // foreign key: resource_name + _id
    status: order.status,                     // "pending" | "confirmed" | "shipped" | "delivered" | "cancelled"
    shipping_method: order.shipping_method,   // "standard_delivery" | "express_delivery"
    is_gift: order.is_gift,                   // boolean with is_ prefix
    has_tracking_number: order.has_tracking_number,
    total_amount: order.total_amount,         // integer cents, not float dollars
    currency: order.currency,                 // "usd" lowercase ISO 4217
    created_at: order.created_at,
    shipped_at: order.shipped_at || null,     // null when not yet shipped
    delivered_at: order.delivered_at || null,
    cancelled_at: order.cancelled_at || null, // null means not cancelled
  };
}

// ---------------------
// Prefixed ID generator
// ---------------------

import crypto from "node:crypto";

const PREFIX_MAP = {
  user: "usr",
  order: "ord",
  product: "prod",
  invoice: "inv",
  subscription: "sub",
};

function generateId(resourceType) {
  const prefix = PREFIX_MAP[resourceType];
  const random = crypto.randomBytes(18).toString("base64url"); // 24 chars, URL-safe
  return `${prefix}_${random}`;
}

// generateId("user")  → "usr_a8Tk3mRpBxYvQn7wJzL2"
// generateId("order") → "ord_7kPmNqRs2vXwYzAbCdEf"

// ---------------------
// Database model (Prisma-style schema showing naming)
// ---------------------

/*
model User {
  id               String    @id @default(cuid())  // stored as "usr_..."
  email            String    @unique
  display_name     String
  organization_id  String
  role             String    @default("member")     // enum: admin, member, viewer
  is_active        Boolean   @default(true)
  is_verified      Boolean   @default(false)
  has_two_factor   Boolean   @default(false)
  can_create_repos Boolean   @default(false)
  created_at       DateTime  @default(now())
  updated_at       DateTime  @updatedAt
  last_login_at    DateTime?
  deleted_at       DateTime?                        // null = not deleted
  orders           Order[]
}

model Order {
  id                  String    @id @default(cuid())
  user_id             String
  user                User      @relation(fields: [user_id], references: [id])
  status              String    @default("pending")  // pending, confirmed, shipped, delivered, cancelled
  shipping_method     String                         // standard_delivery, express_delivery
  is_gift             Boolean   @default(false)
  has_tracking_number Boolean   @default(false)
  total_amount        Int                            // cents
  currency            String    @default("usd")
  created_at          DateTime  @default(now())
  shipped_at          DateTime?
  delivered_at        DateTime?
  cancelled_at        DateTime?
}
*/

// ---------------------
// Route example: consistent naming in request and response
// ---------------------

app.get("/users/:user_id", async (req, res) => {
  const user = await db.users.findUnique({ where: { id: req.params.user_id } });
  if (!user) {
    return res.status(404).json({
      error: {
        type: "not_found",           // snake_case error type
        message: "User not found",
      },
    });
  }
  res.json(serializeUser(user));
});

app.get("/users/:user_id/orders", async (req, res) => {
  const { status, is_gift, sort = "-created_at", limit = 20 } = req.query;

  const filters = { user_id: req.params.user_id };
  if (status) filters.status = status;                  // "pending", "shipped", etc.
  if (is_gift !== undefined) filters.is_gift = is_gift === "true";

  const orders = await db.orders.findMany({
    where: filters,
    orderBy: parseSortParam(sort),
    take: Number(limit),
  });

  res.json({
    data: orders.map(serializeOrder),
    has_more: orders.length === Number(limit),  // boolean with has_ prefix
  });
});
```

## Python (FastAPI)

```python
from datetime import datetime
from typing import Optional

from fastapi import FastAPI, HTTPException, Query
from pydantic import BaseModel, Field


app = FastAPI()


# ---------------------
# Prefixed ID generator
# ---------------------

import secrets
import string

PREFIX_MAP = {
    "user": "usr",
    "order": "ord",
    "product": "prod",
    "invoice": "inv",
    "subscription": "sub",
}

ALPHABET = string.ascii_letters + string.digits  # base62


def generate_id(resource_type: str, length: int = 24) -> str:
    prefix = PREFIX_MAP[resource_type]
    random_part = "".join(secrets.choice(ALPHABET) for _ in range(length))
    return f"{prefix}_{random_part}"


# generate_id("user")  → "usr_a8Tk3mRpBxYvQn7wJzL2hF9d"
# generate_id("order") → "ord_7kPmNqRs2vXwYzAbCdEfGh3j"


# ---------------------
# Response models: enforce consistent snake_case naming
# ---------------------

class UserResponse(BaseModel):
    """All fields use snake_case. Booleans have is_/has_/can_ prefixes.
    Timestamps use _at suffix with ISO 8601 UTC."""

    id: str                                    # "usr_a8Tk3mRp..."
    email: str
    display_name: str                          # snake_case, not displayName
    organization_id: str                       # full word, not org_id
    role: str                                  # "admin" | "member" | "viewer"
    is_active: bool                            # is_ prefix for state
    is_verified: bool
    has_two_factor: bool                       # has_ prefix for possession
    can_create_repos: bool                     # can_ prefix for ability
    created_at: datetime                       # _at suffix, ISO 8601
    updated_at: datetime
    last_login_at: Optional[datetime] = None
    deleted_at: Optional[datetime] = None      # null = not deleted


class OrderResponse(BaseModel):
    """Consistent naming: foreign keys use resource_name + _id,
    enums are lowercase snake_case strings, amounts are integers (cents)."""

    id: str                                       # "ord_7kPmNqRs..."
    user_id: str                                  # foreign key: resource_name + _id
    status: str                                   # "pending" | "confirmed" | "shipped" | "delivered" | "cancelled"
    shipping_method: str                          # "standard_delivery" | "express_delivery"
    is_gift: bool                                 # is_ prefix
    has_tracking_number: bool                     # has_ prefix
    total_amount: int                             # cents, not float dollars
    currency: str                                 # "usd" lowercase ISO 4217
    created_at: datetime
    shipped_at: Optional[datetime] = None         # null when not yet shipped
    delivered_at: Optional[datetime] = None
    cancelled_at: Optional[datetime] = None       # null = not cancelled


class OrderListResponse(BaseModel):
    data: list[OrderResponse]
    has_more: bool                                # boolean with has_ prefix


class ErrorDetail(BaseModel):
    type: str                                     # snake_case: "not_found", "validation_error"
    message: str


class ErrorResponse(BaseModel):
    error: ErrorDetail


# ---------------------
# Database model (SQLAlchemy-style showing naming conventions)
# ---------------------

"""
class User(Base):
    __tablename__ = "users"                    # plural table name

    id               = Column(String, primary_key=True)   # "usr_..."
    email            = Column(String, unique=True, nullable=False)
    display_name     = Column(String, nullable=False)
    organization_id  = Column(String, nullable=False)
    role             = Column(String, default="member")     # admin, member, viewer
    is_active        = Column(Boolean, default=True)
    is_verified      = Column(Boolean, default=False)
    has_two_factor   = Column(Boolean, default=False)
    can_create_repos = Column(Boolean, default=False)
    created_at       = Column(DateTime, default=datetime.utcnow)
    updated_at       = Column(DateTime, onupdate=datetime.utcnow)
    last_login_at    = Column(DateTime, nullable=True)
    deleted_at       = Column(DateTime, nullable=True)      # null = not deleted

    orders = relationship("Order", back_populates="user")


class Order(Base):
    __tablename__ = "orders"

    id                  = Column(String, primary_key=True)
    user_id             = Column(String, ForeignKey("users.id"), nullable=False)
    status              = Column(String, default="pending")
    shipping_method     = Column(String, nullable=False)
    is_gift             = Column(Boolean, default=False)
    has_tracking_number = Column(Boolean, default=False)
    total_amount        = Column(Integer, nullable=False)    # cents
    currency            = Column(String, default="usd")
    created_at          = Column(DateTime, default=datetime.utcnow)
    shipped_at          = Column(DateTime, nullable=True)
    delivered_at        = Column(DateTime, nullable=True)
    cancelled_at        = Column(DateTime, nullable=True)
"""


# ---------------------
# Route example: consistent naming in request and response
# ---------------------

@app.get("/users/{user_id}", response_model=UserResponse)
async def get_user(user_id: str):
    user = await db.users.find_unique(where={"id": user_id})
    if not user:
        raise HTTPException(
            status_code=404,
            detail={"type": "not_found", "message": "User not found"},
        )
    return user


@app.get("/users/{user_id}/orders", response_model=OrderListResponse)
async def list_user_orders(
    user_id: str,
    status: Optional[str] = Query(None),       # "pending", "shipped", etc.
    is_gift: Optional[bool] = Query(None),      # boolean query param with is_ prefix
    sort: str = Query("-created_at"),
    limit: int = Query(20, ge=1, le=100),
):
    filters = {"user_id": user_id}
    if status:
        filters["status"] = status
    if is_gift is not None:
        filters["is_gift"] = is_gift

    orders = await db.orders.find_many(
        where=filters,
        order_by=parse_sort_param(sort),
        take=limit,
    )

    return {
        "data": orders,
        "has_more": len(orders) == limit,       # boolean with has_ prefix
    }
```

## Key Points

- **snake_case everywhere** in JSON fields, query parameters, and database columns — never mix with camelCase
- **Boolean prefixes are mandatory**: `is_active` (state), `has_two_factor` (possession), `can_create_repos` (ability) — never bare `active` or `verified`
- **Timestamp suffix `_at`** for all points in time: `created_at`, `shipped_at`, `last_login_at` — always ISO 8601 with UTC (`Z` suffix)
- **Nullable timestamps** signal state: `deleted_at: null` means not deleted, `shipped_at: null` means not yet shipped
- **Enum values are lowercase snake_case strings**: `"express_delivery"`, `"payment_failed"` — never integers or abbreviations
- **Foreign keys** use the full resource name plus `_id`: `user_id`, `organization_id` — never abbreviated (`org_ref`)
- **Prefixed IDs** identify resource type at a glance: `usr_`, `ord_`, `prod_` — following the Stripe/Twilio pattern
- **Amounts as integers** in smallest currency unit (cents): `total_amount: 4999` not `total: 49.99` — avoids floating-point precision issues
