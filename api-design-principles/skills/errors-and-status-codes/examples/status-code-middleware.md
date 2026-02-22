# Status Code Middleware

Centralized error handler middleware that maps domain exceptions to correct HTTP status codes and formats every error response into a consistent RFC 9457 envelope. No route ever sets a status code or builds an error JSON directly.

## Node.js / Express

```typescript
import { Request, Response, NextFunction } from "express";

// --- Domain exception hierarchy ---

class DomainError extends Error {
  constructor(message: string) {
    super(message);
    this.name = this.constructor.name;
  }
}

class NotFoundError extends DomainError {
  constructor(public resource: string, public resourceId: string) {
    super(`${resource} '${resourceId}' not found`);
  }
}

class ValidationError extends DomainError {
  constructor(public fieldErrors: { field: string; code: string; message: string; rejected_value?: unknown }[]) {
    super(`${fieldErrors.length} field(s) failed validation`);
  }
}

class ConflictError extends DomainError {
  constructor(public conflictField: string, message: string) {
    super(message);
  }
}

class AuthenticationError extends DomainError {
  constructor(message = "Authentication required") {
    super(message);
  }
}

class ForbiddenError extends DomainError {
  constructor(message = "Insufficient permissions") {
    super(message);
  }
}

class RateLimitError extends DomainError {
  constructor(public retryAfterSeconds: number, public limit: number, public windowSeconds: number) {
    super(`Rate limit exceeded. Retry after ${retryAfterSeconds} seconds.`);
  }
}

class BadRequestError extends DomainError {
  constructor(message: string) {
    super(message);
  }
}

// --- Exception-to-status-code mapping ---

const BASE_URL = "https://api.example.com/errors";
const DOCS_URL = "https://api.example.com/docs/errors";

interface ErrorMapping {
  status: number;
  type: string;
  title: string;
  code: string;
  docUrl: string;
  toBody: (err: DomainError) => Record<string, unknown>;
  toHeaders?: (err: DomainError) => Record<string, string>;
}

const ERROR_MAP = new Map<string, ErrorMapping>([
  ["NotFoundError", {
    status: 404,
    type: `${BASE_URL}/resource-not-found`,
    title: "Resource Not Found",
    code: "resource_not_found",
    docUrl: `${DOCS_URL}/resource-not-found`,
    toBody: (err: NotFoundError) => ({
      code: `${err.resource}_not_found`,
    }),
  }],
  ["ValidationError", {
    status: 422,
    type: `${BASE_URL}/validation-error`,
    title: "Validation Error",
    code: "validation_error",
    docUrl: `${DOCS_URL}/validation-error`,
    toBody: (err: ValidationError) => ({
      errors: err.fieldErrors,
    }),
  }],
  ["ConflictError", {
    status: 409,
    type: `${BASE_URL}/duplicate-resource`,
    title: "Duplicate Resource",
    code: "duplicate_resource",
    docUrl: `${DOCS_URL}/duplicate-resource`,
    toBody: (err: ConflictError) => ({
      code: `${err.conflictField}_already_exists`,
    }),
  }],
  ["AuthenticationError", {
    status: 401,
    type: `${BASE_URL}/authentication-required`,
    title: "Authentication Required",
    code: "authentication_required",
    docUrl: `${DOCS_URL}/authentication-required`,
    toBody: () => ({}),
    toHeaders: () => ({
      "WWW-Authenticate": 'Bearer realm="api.example.com"',
    }),
  }],
  ["ForbiddenError", {
    status: 403,
    type: `${BASE_URL}/insufficient-permissions`,
    title: "Insufficient Permissions",
    code: "insufficient_permissions",
    docUrl: `${DOCS_URL}/insufficient-permissions`,
    toBody: () => ({}),
  }],
  ["RateLimitError", {
    status: 429,
    type: `${BASE_URL}/rate-limit-exceeded`,
    title: "Rate Limit Exceeded",
    code: "rate_limit_exceeded",
    docUrl: `${DOCS_URL}/rate-limit-exceeded`,
    toBody: (err: RateLimitError) => ({
      limit: err.limit,
      window_seconds: err.windowSeconds,
      retry_after_seconds: err.retryAfterSeconds,
    }),
    toHeaders: (err: RateLimitError) => ({
      "Retry-After": String(err.retryAfterSeconds),
      "RateLimit-Limit": String(err.limit),
      "RateLimit-Remaining": "0",
    }),
  }],
  ["BadRequestError", {
    status: 400,
    type: `${BASE_URL}/bad-request`,
    title: "Bad Request",
    code: "bad_request",
    docUrl: `${DOCS_URL}/bad-request`,
    toBody: () => ({}),
  }],
]);

// --- The middleware ---

function errorHandler(err: Error, req: Request, res: Response, _next: NextFunction) {
  const requestId = req.requestId;
  const mapping = ERROR_MAP.get(err.name);

  if (mapping) {
    const extraBody = mapping.toBody(err as DomainError);
    const extraHeaders = mapping.toHeaders?.(err as DomainError) ?? {};

    for (const [key, value] of Object.entries(extraHeaders)) {
      res.setHeader(key, value);
    }

    res
      .status(mapping.status)
      .set("Content-Type", "application/problem+json")
      .json({
        type: mapping.type,
        title: mapping.title,
        status: mapping.status,
        detail: err.message,
        code: mapping.code,
        instance: `urn:request:${requestId}`,
        doc_url: mapping.docUrl,
        ...extraBody,
      });
    return;
  }

  // Unhandled: log internally, return safe 500
  console.error(`[${requestId}] Unhandled error:`, err);
  res
    .status(500)
    .set("Content-Type", "application/problem+json")
    .json({
      type: `${BASE_URL}/internal-error`,
      title: "Internal Server Error",
      status: 500,
      detail: "An unexpected error occurred. Please try again later.",
      code: "internal_error",
      instance: `urn:request:${requestId}`,
    });
}

// --- JSON parse error handling ---

app.use(express.json());
app.use((err: Error, req: Request, res: Response, next: NextFunction) => {
  if (err instanceof SyntaxError && "body" in err) {
    const requestId = req.requestId;
    res
      .status(400)
      .set("Content-Type", "application/problem+json")
      .json({
        type: `${BASE_URL}/bad-request`,
        title: "Bad Request",
        status: 400,
        detail: "The request body contains invalid JSON.",
        code: "invalid_json",
        instance: `urn:request:${requestId}`,
        doc_url: `${DOCS_URL}/bad-request`,
      });
    return;
  }
  next(err);
});

// --- Routes throw domain exceptions, never set status codes ---

app.get("/users/:id", async (req, res, next) => {
  try {
    const user = await db.users.findById(req.params.id);
    if (!user) throw new NotFoundError("user", req.params.id);
    res.json(user);
  } catch (err) {
    next(err);
  }
});

app.post("/users", async (req, res, next) => {
  try {
    const { email, password } = req.body;
    const errors = validateUserInput(email, password);
    if (errors.length) throw new ValidationError(errors);

    const existing = await db.users.findByEmail(email);
    if (existing) throw new ConflictError("email", `A user with email '${email}' already exists.`);

    const user = await db.users.create(req.body);
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
import logging
from dataclasses import dataclass, field
from typing import Any
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

# --- Domain exception hierarchy ---

@dataclass
class DomainError(Exception):
    detail: str = ""

@dataclass
class NotFoundError(DomainError):
    resource: str = ""
    resource_id: str = ""

@dataclass
class ValidationError(DomainError):
    field_errors: list[dict[str, Any]] = field(default_factory=list)

@dataclass
class ConflictError(DomainError):
    conflict_field: str = ""

@dataclass
class AuthenticationError(DomainError):
    detail: str = "Authentication required"

@dataclass
class ForbiddenError(DomainError):
    detail: str = "Insufficient permissions"

@dataclass
class RateLimitError(DomainError):
    retry_after_seconds: int = 0
    limit: int = 0
    window_seconds: int = 0

@dataclass
class BadRequestError(DomainError):
    pass

# --- Exception-to-status-code mapping ---

BASE_URL = "https://api.example.com/errors"
DOCS_URL = "https://api.example.com/docs/errors"

ERROR_MAPPING = {
    NotFoundError: {
        "status": 404,
        "type": f"{BASE_URL}/resource-not-found",
        "title": "Resource Not Found",
        "code": "resource_not_found",
        "doc_url": f"{DOCS_URL}/resource-not-found",
        "to_body": lambda err: {"code": f"{err.resource}_not_found"},
    },
    ValidationError: {
        "status": 422,
        "type": f"{BASE_URL}/validation-error",
        "title": "Validation Error",
        "code": "validation_error",
        "doc_url": f"{DOCS_URL}/validation-error",
        "to_body": lambda err: {"errors": err.field_errors},
    },
    ConflictError: {
        "status": 409,
        "type": f"{BASE_URL}/duplicate-resource",
        "title": "Duplicate Resource",
        "code": "duplicate_resource",
        "doc_url": f"{DOCS_URL}/duplicate-resource",
        "to_body": lambda err: {"code": f"{err.conflict_field}_already_exists"},
    },
    AuthenticationError: {
        "status": 401,
        "type": f"{BASE_URL}/authentication-required",
        "title": "Authentication Required",
        "code": "authentication_required",
        "doc_url": f"{DOCS_URL}/authentication-required",
        "to_body": lambda err: {},
        "headers": {"WWW-Authenticate": 'Bearer realm="api.example.com"'},
    },
    ForbiddenError: {
        "status": 403,
        "type": f"{BASE_URL}/insufficient-permissions",
        "title": "Insufficient Permissions",
        "code": "insufficient_permissions",
        "doc_url": f"{DOCS_URL}/insufficient-permissions",
        "to_body": lambda err: {},
    },
    RateLimitError: {
        "status": 429,
        "type": f"{BASE_URL}/rate-limit-exceeded",
        "title": "Rate Limit Exceeded",
        "code": "rate_limit_exceeded",
        "doc_url": f"{DOCS_URL}/rate-limit-exceeded",
        "to_body": lambda err: {
            "limit": err.limit,
            "window_seconds": err.window_seconds,
            "retry_after_seconds": err.retry_after_seconds,
        },
        "headers_fn": lambda err: {
            "Retry-After": str(err.retry_after_seconds),
            "RateLimit-Limit": str(err.limit),
            "RateLimit-Remaining": "0",
        },
    },
    BadRequestError: {
        "status": 400,
        "type": f"{BASE_URL}/bad-request",
        "title": "Bad Request",
        "code": "bad_request",
        "doc_url": f"{DOCS_URL}/bad-request",
        "to_body": lambda err: {},
    },
}

# --- App setup ---

app = FastAPI()

@app.middleware("http")
async def request_id_middleware(request: Request, call_next):
    request_id = str(uuid.uuid4())
    request.state.request_id = request_id
    response = await call_next(request)
    response.headers["X-Request-Id"] = request_id
    return response

# --- Register a handler for each domain exception ---

def _build_error_response(request: Request, exc: DomainError, mapping: dict) -> JSONResponse:
    request_id = getattr(request.state, "request_id", "unknown")
    extra_body = mapping["to_body"](exc)

    body = {
        "type": mapping["type"],
        "title": mapping["title"],
        "status": mapping["status"],
        "detail": exc.detail,
        "code": mapping["code"],
        "instance": f"urn:request:{request_id}",
        "doc_url": mapping["doc_url"],
        **extra_body,
    }

    headers = mapping.get("headers", {}).copy()
    headers_fn = mapping.get("headers_fn")
    if headers_fn:
        headers.update(headers_fn(exc))

    return JSONResponse(
        status_code=mapping["status"],
        content=body,
        headers=headers,
        media_type="application/problem+json",
    )

for exc_class, mapping in ERROR_MAPPING.items():
    def _make_handler(m):
        async def handler(request: Request, exc: DomainError):
            return _build_error_response(request, exc, m)
        return handler
    app.add_exception_handler(exc_class, _make_handler(mapping))

# --- Catch-all for unhandled exceptions ---

@app.exception_handler(Exception)
async def unhandled_error_handler(request: Request, exc: Exception):
    request_id = getattr(request.state, "request_id", "unknown")
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

# --- Routes throw domain exceptions, never set status codes ---

@app.get("/users/{user_id}")
async def get_user(user_id: str, request: Request):
    user = await db.users.find_by_id(user_id)
    if not user:
        raise NotFoundError(
            detail=f"No user found with ID '{user_id}'.",
            resource="user",
            resource_id=user_id,
        )
    return user.to_dict()

@app.post("/users", status_code=201)
async def create_user(request: Request):
    body = await request.json()
    errors = validate_user_input(body)
    if errors:
        raise ValidationError(
            detail=f"{len(errors)} field(s) failed validation.",
            field_errors=errors,
        )

    existing = await db.users.find_by_email(body["email"])
    if existing:
        raise ConflictError(
            detail=f"A user with email '{body['email']}' already exists.",
            conflict_field="email",
        )

    user = await db.users.create(**body)
    return JSONResponse(
        status_code=201,
        content=user.to_dict(),
        headers={"Location": f"/users/{user.id}"},
    )
```

## Key Points

- Routes never construct error JSON or set error status codes directly -- they throw domain exceptions
- A single mapping table connects each exception type to its HTTP status, problem type URI, title, and code
- Adding a new error type means defining a new exception class and adding one entry to the mapping
- The catch-all handler ensures unhandled exceptions never leak stack traces or internal details
- Special headers (`WWW-Authenticate` for 401, `Retry-After` for 429) are defined in the mapping, not scattered across routes
- Malformed JSON parsing errors are intercepted early and returned as 400 with the consistent envelope
- The `Content-Type` is always `application/problem+json`, enforced in one place
