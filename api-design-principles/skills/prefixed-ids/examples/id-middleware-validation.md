# ID Middleware Validation

Express and FastAPI middleware that validates prefixed IDs in route parameters, returning a 400 error with a clear message on invalid format or type mismatch. Rejects bad IDs before they reach the database.

## Node.js (Express + TypeScript)

```typescript
import { Request, Response, NextFunction, RequestHandler } from "express";

// --- Shared prefix registry (import from your id-generator module) ---

const ID_PREFIXES: Record<string, string> = {
  user: "usr",
  organization: "org",
  order: "ord",
  product: "prod",
  invoice: "inv",
  payment: "pay",
  subscription: "sub",
  webhook_endpoint: "wh",
  event: "evt",
  session: "sess",
  token: "tok",
  api_key: "key",
  customer: "cus",
  price: "price",
  transaction: "txn",
};

const PREFIXED_ID_REGEX = /^[a-z]{2,5}_[a-zA-Z0-9]{14,27}$/;

// --- Middleware factory ---

/**
 * Creates middleware that validates a route parameter is a valid prefixed ID
 * for the expected resource type.
 *
 * @param paramName - The route parameter name (e.g., "id", "customerId")
 * @param expectedType - The resource type key from ID_PREFIXES
 */
function validatePrefixedId(
  paramName: string,
  expectedType: string
): RequestHandler {
  const expectedPrefix = ID_PREFIXES[expectedType];
  if (!expectedPrefix) {
    throw new Error(
      `Unknown resource type '${expectedType}' -- register it in ID_PREFIXES`
    );
  }

  return (req: Request, res: Response, next: NextFunction): void => {
    const id = req.params[paramName];

    if (!id) {
      res.status(400).json({
        error: {
          type: "invalid_request_error",
          message: `Missing required parameter '${paramName}'`,
          param: paramName,
        },
      });
      return;
    }

    // Check prefix match
    if (!id.startsWith(expectedPrefix + "_")) {
      const actualPrefix = id.split("_")[0];
      res.status(400).json({
        error: {
          type: "invalid_request_error",
          message: `Invalid ${expectedType} ID: expected prefix '${expectedPrefix}_', got '${actualPrefix}_'`,
          param: paramName,
        },
      });
      return;
    }

    // Check overall format
    if (!PREFIXED_ID_REGEX.test(id)) {
      res.status(400).json({
        error: {
          type: "invalid_request_error",
          message: `Malformed ID: '${id}' does not match expected format`,
          param: paramName,
        },
      });
      return;
    }

    next();
  };
}

// --- Route registration ---

import express from "express";
const app = express();

// Single resource routes
app.get(
  "/v1/customers/:id",
  validatePrefixedId("id", "customer"),
  async (req, res) => {
    // req.params.id is guaranteed to start with "cus_" and match the format
    const customer = await db.customers.findUnique({
      where: { id: req.params.id },
    });
    if (!customer) {
      return res.status(404).json({
        error: {
          type: "invalid_request_error",
          message: `No such customer: '${req.params.id}'`,
        },
      });
    }
    res.json(customer);
  }
);

app.get(
  "/v1/orders/:id",
  validatePrefixedId("id", "order"),
  async (req, res) => {
    const order = await db.orders.findUnique({
      where: { id: req.params.id },
    });
    if (!order) {
      return res.status(404).json({
        error: {
          type: "invalid_request_error",
          message: `No such order: '${req.params.id}'`,
        },
      });
    }
    res.json(order);
  }
);

// Nested resource routes with multiple validated params
app.get(
  "/v1/customers/:customerId/orders/:orderId",
  validatePrefixedId("customerId", "customer"),
  validatePrefixedId("orderId", "order"),
  async (req, res) => {
    // Both params are validated before this handler runs
    const order = await db.orders.findFirst({
      where: {
        id: req.params.orderId,
        customerId: req.params.customerId,
      },
    });
    if (!order) {
      return res.status(404).json({
        error: {
          type: "invalid_request_error",
          message: `No such order '${req.params.orderId}' for customer '${req.params.customerId}'`,
        },
      });
    }
    res.json(order);
  }
);
```

## Python (FastAPI)

```python
import re
from fastapi import FastAPI, HTTPException, Path, Depends
from typing import Annotated

# --- Shared prefix registry (import from your id_generator module) ---

ID_PREFIXES: dict[str, str] = {
    "user": "usr",
    "organization": "org",
    "order": "ord",
    "product": "prod",
    "invoice": "inv",
    "payment": "pay",
    "subscription": "sub",
    "webhook_endpoint": "wh",
    "event": "evt",
    "session": "sess",
    "token": "tok",
    "api_key": "key",
    "customer": "cus",
    "price": "price",
    "transaction": "txn",
}

PREFIXED_ID_PATTERN = re.compile(r"^[a-z]{2,5}_[a-zA-Z0-9]{14,27}$")

app = FastAPI()


# --- Dependency factory ---

def prefixed_id(
    param_name: str,
    resource_type: str,
):
    """
    Creates a FastAPI dependency that validates a path parameter
    is a valid prefixed ID for the expected resource type.
    """
    expected_prefix = ID_PREFIXES.get(resource_type)
    if expected_prefix is None:
        raise ValueError(
            f"Unknown resource type '{resource_type}' -- "
            f"register it in ID_PREFIXES"
        )

    def validator(
        id_value: str = Path(..., alias=param_name),
    ) -> str:
        # Check prefix match
        if not id_value.startswith(f"{expected_prefix}_"):
            actual_prefix = id_value.split("_")[0]
            raise HTTPException(
                status_code=400,
                detail={
                    "type": "invalid_request_error",
                    "message": (
                        f"Invalid {resource_type} ID: expected prefix "
                        f"'{expected_prefix}_', got '{actual_prefix}_'"
                    ),
                    "param": param_name,
                },
            )

        # Check overall format
        if not PREFIXED_ID_PATTERN.match(id_value):
            raise HTTPException(
                status_code=400,
                detail={
                    "type": "invalid_request_error",
                    "message": (
                        f"Malformed ID: '{id_value}' does not match "
                        f"expected format"
                    ),
                    "param": param_name,
                },
            )

        return id_value

    return validator


# --- Type aliases for validated IDs ---

ValidCustomerId = Annotated[str, Depends(prefixed_id("customer_id", "customer"))]
ValidOrderId = Annotated[str, Depends(prefixed_id("order_id", "order"))]


# --- Route registration ---

@app.get("/v1/customers/{customer_id}")
async def get_customer(
    customer_id: ValidCustomerId,
):
    # customer_id is guaranteed to start with "cus_" and match the format
    customer = await db.customers.find_unique(where={"id": customer_id})
    if not customer:
        raise HTTPException(
            status_code=404,
            detail={
                "type": "invalid_request_error",
                "message": f"No such customer: '{customer_id}'",
            },
        )
    return customer


@app.get("/v1/orders/{order_id}")
async def get_order(
    order_id: ValidOrderId,
):
    order = await db.orders.find_unique(where={"id": order_id})
    if not order:
        raise HTTPException(
            status_code=404,
            detail={
                "type": "invalid_request_error",
                "message": f"No such order: '{order_id}'",
            },
        )
    return order


@app.get("/v1/customers/{customer_id}/orders/{order_id}")
async def get_customer_order(
    customer_id: ValidCustomerId,
    order_id: ValidOrderId,
):
    # Both params are validated before this handler runs
    order = await db.orders.find_first(
        where={"id": order_id, "customer_id": customer_id}
    )
    if not order:
        raise HTTPException(
            status_code=404,
            detail={
                "type": "invalid_request_error",
                "message": (
                    f"No such order '{order_id}' for customer "
                    f"'{customer_id}'"
                ),
            },
        )
    return order
```

## Key Points

- Validate IDs in middleware, not in route handlers -- the handler should never receive a malformed or wrong-type ID
- Return 400 (not 404) for type mismatches -- the client sent a syntactically wrong request, not a reference to a missing resource
- Include the `param` field in error responses so clients know which parameter failed validation
- Name the expected prefix in the error message so the client can self-correct
- Apply validation to every route parameter that accepts an ID, including nested resources with multiple ID params
- The middleware/dependency is stateless and does not touch the database -- it validates format and prefix only
