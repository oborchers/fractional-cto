# Error Envelope Implementation

Complete error response system with typed error classes, a consistent RFC 9457 envelope, per-field validation errors, and request ID injection.

## Node.js / Express

```typescript
import { randomUUID } from "crypto";
import { Request, Response, NextFunction } from "express";

// --- Error classes ---

interface FieldError {
  field: string;
  code: string;
  message: string;
  rejected_value?: unknown;
}

class ApiError extends Error {
  readonly type: string;
  readonly title: string;
  readonly status: number;
  readonly code: string;
  readonly detail: string;
  readonly docUrl?: string;
  readonly errors?: FieldError[];

  constructor(opts: {
    type: string;
    title: string;
    status: number;
    code: string;
    detail: string;
    docUrl?: string;
    errors?: FieldError[];
  }) {
    super(opts.detail);
    this.type = opts.type;
    this.title = opts.title;
    this.status = opts.status;
    this.code = opts.code;
    this.detail = opts.detail;
    this.docUrl = opts.docUrl;
    this.errors = opts.errors;
  }

  toResponse(requestId: string) {
    const body: Record<string, unknown> = {
      type: this.type,
      title: this.title,
      status: this.status,
      detail: this.detail,
      code: this.code,
      instance: `urn:request:${requestId}`,
    };
    if (this.errors?.length) body.errors = this.errors;
    if (this.docUrl) body.doc_url = this.docUrl;
    return body;
  }
}

// --- Reusable error factories ---

const BASE_URL = "https://api.example.com/errors";
const DOCS_URL = "https://api.example.com/docs/errors";

function notFoundError(resource: string, id: string): ApiError {
  return new ApiError({
    type: `${BASE_URL}/resource-not-found`,
    title: "Resource Not Found",
    status: 404,
    code: `${resource}_not_found`,
    detail: `No ${resource} found with ID '${id}'.`,
    docUrl: `${DOCS_URL}/resource-not-found`,
  });
}

function validationError(errors: FieldError[]): ApiError {
  return new ApiError({
    type: `${BASE_URL}/validation-error`,
    title: "Validation Error",
    status: 422,
    code: "validation_error",
    detail: `${errors.length} field(s) failed validation.`,
    docUrl: `${DOCS_URL}/validation-error`,
    errors,
  });
}

function conflictError(field: string, detail: string): ApiError {
  return new ApiError({
    type: `${BASE_URL}/duplicate-resource`,
    title: "Duplicate Resource",
    status: 409,
    code: `${field}_already_exists`,
    detail,
    docUrl: `${DOCS_URL}/duplicate-resource`,
  });
}

function authenticationError(detail: string): ApiError {
  return new ApiError({
    type: `${BASE_URL}/authentication-required`,
    title: "Authentication Required",
    status: 401,
    code: "authentication_required",
    detail,
    docUrl: `${DOCS_URL}/authentication-required`,
  });
}

function forbiddenError(detail: string): ApiError {
  return new ApiError({
    type: `${BASE_URL}/insufficient-permissions`,
    title: "Insufficient Permissions",
    status: 403,
    code: "insufficient_permissions",
    detail,
    docUrl: `${DOCS_URL}/insufficient-permissions`,
  });
}

// --- Request ID middleware ---

function requestIdMiddleware(req: Request, res: Response, next: NextFunction) {
  const requestId = randomUUID();
  req.requestId = requestId;
  res.setHeader("X-Request-Id", requestId);
  next();
}

// Extend Express Request type
declare global {
  namespace Express {
    interface Request {
      requestId: string;
    }
  }
}

// --- Error handler middleware ---

function errorHandler(err: Error, req: Request, res: Response, _next: NextFunction) {
  if (err instanceof ApiError) {
    res
      .status(err.status)
      .set("Content-Type", "application/problem+json")
      .json(err.toResponse(req.requestId));
    return;
  }

  // Unhandled errors become 500. Never expose internals.
  console.error(`[${req.requestId}]`, err);
  res
    .status(500)
    .set("Content-Type", "application/problem+json")
    .json({
      type: `${BASE_URL}/internal-error`,
      title: "Internal Server Error",
      status: 500,
      detail: "An unexpected error occurred. Please try again later.",
      code: "internal_error",
      instance: `urn:request:${req.requestId}`,
    });
}

// --- Usage in a route ---

app.use(requestIdMiddleware);

app.post("/users", async (req, res, next) => {
  try {
    const { email, password, name } = req.body;

    // Validate fields
    const errors: FieldError[] = [];
    if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
      errors.push({
        field: "email",
        code: "invalid_format",
        message: "Must be a valid email address.",
        rejected_value: email,
      });
    }
    if (!password || password.length < 8) {
      errors.push({
        field: "password",
        code: "too_short",
        message: "Must be at least 8 characters.",
        // Do not include rejected_value for passwords
      });
    }
    if (errors.length) throw validationError(errors);

    // Check uniqueness
    const existing = await db.users.findByEmail(email);
    if (existing) {
      throw conflictError("email", `A user with email '${email}' already exists.`);
    }

    const user = await db.users.create({ email, password, name });
    res.status(201).location(`/users/${user.id}`).json(user);
  } catch (err) {
    next(err);
  }
});

app.use(errorHandler);
```

## Python / FastAPI

```python
import uuid
from typing import Any
from dataclasses import dataclass, field
from fastapi import FastAPI, Request, HTTPException
from fastapi.responses import JSONResponse

# --- Error classes ---

@dataclass
class FieldError:
    field: str
    code: str
    message: str
    rejected_value: Any = None

@dataclass
class ApiError(Exception):
    type: str
    title: str
    status: int
    code: str
    detail: str
    doc_url: str | None = None
    errors: list[FieldError] = field(default_factory=list)

    def to_response(self, request_id: str) -> dict:
        body = {
            "type": self.type,
            "title": self.title,
            "status": self.status,
            "detail": self.detail,
            "code": self.code,
            "instance": f"urn:request:{request_id}",
        }
        if self.errors:
            body["errors"] = [
                {k: v for k, v in {
                    "field": e.field,
                    "code": e.code,
                    "message": e.message,
                    "rejected_value": e.rejected_value,
                }.items() if v is not None}
                for e in self.errors
            ]
        if self.doc_url:
            body["doc_url"] = self.doc_url
        return body

# --- Error factories ---

BASE_URL = "https://api.example.com/errors"
DOCS_URL = "https://api.example.com/docs/errors"

def not_found_error(resource: str, id: str) -> ApiError:
    return ApiError(
        type=f"{BASE_URL}/resource-not-found",
        title="Resource Not Found",
        status=404,
        code=f"{resource}_not_found",
        detail=f"No {resource} found with ID '{id}'.",
        doc_url=f"{DOCS_URL}/resource-not-found",
    )

def validation_error(errors: list[FieldError]) -> ApiError:
    return ApiError(
        type=f"{BASE_URL}/validation-error",
        title="Validation Error",
        status=422,
        code="validation_error",
        detail=f"{len(errors)} field(s) failed validation.",
        doc_url=f"{DOCS_URL}/validation-error",
        errors=errors,
    )

def conflict_error(field_name: str, detail: str) -> ApiError:
    return ApiError(
        type=f"{BASE_URL}/duplicate-resource",
        title="Duplicate Resource",
        status=409,
        code=f"{field_name}_already_exists",
        detail=detail,
        doc_url=f"{DOCS_URL}/duplicate-resource",
    )

# --- App setup ---

app = FastAPI()

@app.middleware("http")
async def request_id_middleware(request: Request, call_next):
    request_id = str(uuid.uuid4())
    request.state.request_id = request_id
    response = await call_next(request)
    response.headers["X-Request-Id"] = request_id
    return response

@app.exception_handler(ApiError)
async def api_error_handler(request: Request, exc: ApiError):
    return JSONResponse(
        status_code=exc.status,
        content=exc.to_response(request.state.request_id),
        media_type="application/problem+json",
    )

@app.exception_handler(Exception)
async def unhandled_error_handler(request: Request, exc: Exception):
    request_id = getattr(request.state, "request_id", "unknown")
    import logging
    logging.exception(f"[{request_id}] Unhandled error")
    return JSONResponse(
        status_code=500,
        content={
            "type": f"{BASE_URL}/internal-error",
            "title": "Internal Server Error",
            "status": 500,
            "detail": "An unexpected error occurred. Please try again later.",
            "code": "internal_error",
            "instance": f"urn:request:{request_id}",
        },
        media_type="application/problem+json",
    )

# --- Usage in a route ---

import re

@app.post("/users", status_code=201)
async def create_user(request: Request):
    body = await request.json()
    email = body.get("email", "")
    password = body.get("password", "")

    errors = []
    if not email or not re.match(r"^[^\s@]+@[^\s@]+\.[^\s@]+$", email):
        errors.append(FieldError(
            field="email",
            code="invalid_format",
            message="Must be a valid email address.",
            rejected_value=email,
        ))
    if not password or len(password) < 8:
        errors.append(FieldError(
            field="password",
            code="too_short",
            message="Must be at least 8 characters.",
            # Do not include rejected_value for passwords
        ))
    if errors:
        raise validation_error(errors)

    existing = await db.users.find_by_email(email)
    if existing:
        raise conflict_error("email", f"A user with email '{email}' already exists.")

    user = await db.users.create(email=email, password=password, name=body.get("name"))
    return JSONResponse(
        status_code=201,
        content=user.to_dict(),
        headers={"Location": f"/users/{user.id}"},
    )
```

## Key Points

- Define a single `ApiError` class that every error flows through -- no ad-hoc JSON construction
- Error factories (`notFoundError`, `validationError`, `conflictError`) enforce consistency and reduce boilerplate at the call site
- Request ID is generated once per request and injected into every error response automatically
- Per-field validation errors collect all failures before throwing, so clients see every problem at once
- Sensitive fields (passwords, tokens) never include `rejected_value`
- Unhandled exceptions are caught at the top level, logged with the request ID, and returned as a safe 500
- The `Content-Type` is always `application/problem+json` for error responses
