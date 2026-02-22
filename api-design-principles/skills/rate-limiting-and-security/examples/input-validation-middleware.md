# Input Validation Middleware

Request validation middleware that enforces size limits, type checking, and sanitization on all incoming requests. Rejects unknown fields (mass assignment prevention), validates parameter formats, and returns structured errors matching the Stripe error format.

## What This Covers

1. **Body size limits** — reject payloads exceeding a maximum size before parsing
2. **Type checking** — validate path parameters, query parameters, and body fields against schemas
3. **Unknown field rejection** — return a clear error for unexpected fields (prevents mass assignment)
4. **Sanitization** — strip control characters, enforce string length limits, validate enum values
5. **Numeric bounds** — enforce minimum/maximum on pagination and numeric fields

## Node.js / Express

```ts
import { Router, Request, Response, NextFunction } from "express";
import { z, ZodError, ZodSchema } from "zod";

// --- Reusable validation primitives ---

/** Prefixed ID format: {prefix}_{20 alphanumeric chars} */
function prefixedId(prefix: string) {
  const pattern = new RegExp(`^${prefix}_[a-zA-Z0-9]{20}$`);
  return z.string().regex(pattern, {
    message: `Invalid ID format. Expected ${prefix}_<20 alphanumeric chars>`,
  });
}

/** Pagination query parameters with safe defaults and bounds */
const paginationSchema = z.object({
  limit: z.coerce.number().int().min(1).max(100).default(20),
  offset: z.coerce.number().int().min(0).default(0),
});

/** Strip control characters from strings */
function sanitizedString(maxLength: number) {
  return z
    .string()
    .max(maxLength)
    .transform((val) => val.replace(/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/g, ""));
}

// --- Validation middleware factory ---

interface ValidationSchemas {
  body?: ZodSchema;
  query?: ZodSchema;
  params?: ZodSchema;
}

function validate(schemas: ValidationSchemas) {
  return (req: Request, res: Response, next: NextFunction) => {
    const errors: Array<{ location: string; field: string; message: string }> = [];

    if (schemas.params) {
      const result = schemas.params.safeParse(req.params);
      if (!result.success) {
        for (const issue of result.error.issues) {
          errors.push({
            location: "path",
            field: issue.path.join("."),
            message: issue.message,
          });
        }
      } else {
        req.params = result.data;
      }
    }

    if (schemas.query) {
      const result = schemas.query.safeParse(req.query);
      if (!result.success) {
        for (const issue of result.error.issues) {
          errors.push({
            location: "query",
            field: issue.path.join("."),
            message: issue.message,
          });
        }
      } else {
        (req as any).validatedQuery = result.data;
      }
    }

    if (schemas.body) {
      const result = schemas.body.safeParse(req.body);
      if (!result.success) {
        for (const issue of result.error.issues) {
          errors.push({
            location: "body",
            field: issue.path.join("."),
            message: issue.message,
          });
        }
      } else {
        req.body = result.data;
      }
    }

    if (errors.length > 0) {
      return res.status(400).json({
        error: {
          type: "invalid_request_error",
          message: errors[0].message,
          param: errors[0].field,
          errors,
        },
      });
    }

    next();
  };
}

// --- Content-Type enforcement ---

function requireJson(req: Request, res: Response, next: NextFunction) {
  if (
    ["POST", "PUT", "PATCH"].includes(req.method) &&
    !req.is("application/json")
  ) {
    return res.status(415).json({
      error: {
        type: "invalid_request_error",
        message: "Expected Content-Type: application/json",
      },
    });
  }
  next();
}

// --- Unknown field rejection (Zod .strict()) ---

const createUserSchema = z
  .object({
    name: sanitizedString(255),
    email: z.string().email().max(320),
    role: z.enum(["viewer", "editor", "admin"]).optional().default("viewer"),
  })
  .strict(); // Rejects unknown fields like "is_admin", "password_hash"

const updateUserSchema = z
  .object({
    name: sanitizedString(255).optional(),
    email: z.string().email().max(320).optional(),
  })
  .strict();

const userParamsSchema = z.object({
  user_id: prefixedId("usr"),
});

// --- Routes ---

const app = Router();

// Body size limit: 10 KB for standard endpoints
// Set at the Express app level with express.json({ limit: "10kb" })

app.use(requireJson);

app.get(
  "/api/v1/users",
  validate({ query: paginationSchema }),
  (req: Request, res: Response) => {
    const { limit, offset } = (req as any).validatedQuery;
    // limit is guaranteed 1-100, offset >= 0
    res.json({ data: [], limit, offset });
  }
);

app.post(
  "/api/v1/users",
  validate({ body: createUserSchema }),
  (req: Request, res: Response) => {
    // req.body is typed and sanitized. Unknown fields rejected.
    // If client sent { "name": "Eve", "is_admin": true },
    // response is 400: "Unrecognized key(s) in object: 'is_admin'"
    res.status(201).json({ data: req.body });
  }
);

app.patch(
  "/api/v1/users/:user_id",
  validate({
    params: userParamsSchema,
    body: updateUserSchema,
  }),
  (req: Request, res: Response) => {
    // user_id matches usr_<20 chars>. Body has only allowed fields.
    res.json({ data: { id: req.params.user_id, ...req.body } });
  }
);

export { validate, prefixedId, paginationSchema, sanitizedString };
```

## Python / FastAPI

```python
import re
from typing import Optional

from fastapi import FastAPI, Path, Query, Request, HTTPException
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field, field_validator, model_validator
from starlette.middleware.base import BaseHTTPMiddleware

app = FastAPI()


# --- Body size limit middleware ---

class BodySizeLimitMiddleware(BaseHTTPMiddleware):
    """Reject requests with bodies exceeding max_bytes before parsing."""

    def __init__(self, app, max_bytes: int = 10_240):  # 10 KB
        super().__init__(app)
        self.max_bytes = max_bytes

    async def dispatch(self, request: Request, call_next):
        if request.method in ("POST", "PUT", "PATCH"):
            content_length = request.headers.get("content-length")
            if content_length and int(content_length) > self.max_bytes:
                return JSONResponse(
                    status_code=413,
                    content={
                        "error": {
                            "type": "invalid_request_error",
                            "message": (
                                f"Request body too large. "
                                f"Maximum size is {self.max_bytes} bytes."
                            ),
                        }
                    },
                )
        return await call_next(request)


class ContentTypeMiddleware(BaseHTTPMiddleware):
    """Enforce application/json Content-Type on write methods."""

    async def dispatch(self, request: Request, call_next):
        if request.method in ("POST", "PUT", "PATCH"):
            content_type = request.headers.get("content-type", "")
            if "application/json" not in content_type:
                return JSONResponse(
                    status_code=415,
                    content={
                        "error": {
                            "type": "invalid_request_error",
                            "message": "Expected Content-Type: application/json",
                        }
                    },
                )
        return await call_next(request)


app.add_middleware(BodySizeLimitMiddleware, max_bytes=10_240)
app.add_middleware(ContentTypeMiddleware)


# --- Reusable validation primitives ---

PREFIXED_ID_PATTERN = re.compile(r"^[a-z]{2,6}_[a-zA-Z0-9]{20}$")
CONTROL_CHARS = re.compile(r"[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]")


def validate_prefixed_id(value: str, prefix: str) -> str:
    pattern = re.compile(rf"^{prefix}_[a-zA-Z0-9]{{20}}$")
    if not pattern.match(value):
        raise ValueError(
            f"Invalid ID format. Expected {prefix}_<20 alphanumeric chars>"
        )
    return value


def sanitize_string(value: str) -> str:
    """Strip control characters from user input."""
    return CONTROL_CHARS.sub("", value)


# --- Request/response models ---

class CreateUserRequest(BaseModel):
    """Strict model: unknown fields are rejected."""

    model_config = {"extra": "forbid"}  # Rejects unknown fields

    name: str = Field(max_length=255)
    email: str = Field(max_length=320)
    role: str = Field(default="viewer")

    @field_validator("name")
    @classmethod
    def sanitize_name(cls, v: str) -> str:
        return sanitize_string(v)

    @field_validator("email")
    @classmethod
    def validate_email(cls, v: str) -> str:
        # Basic email format check
        if not re.match(r"^[^@\s]+@[^@\s]+\.[^@\s]+$", v):
            raise ValueError("Invalid email format")
        return v.lower()

    @field_validator("role")
    @classmethod
    def validate_role(cls, v: str) -> str:
        allowed = {"viewer", "editor", "admin"}
        if v not in allowed:
            raise ValueError(f"Invalid role. Allowed values: {', '.join(sorted(allowed))}")
        return v


class UpdateUserRequest(BaseModel):
    """Partial update model. All fields optional, unknown fields rejected."""

    model_config = {"extra": "forbid"}

    name: Optional[str] = Field(default=None, max_length=255)
    email: Optional[str] = Field(default=None, max_length=320)

    @field_validator("name")
    @classmethod
    def sanitize_name(cls, v: Optional[str]) -> Optional[str]:
        return sanitize_string(v) if v is not None else None

    @field_validator("email")
    @classmethod
    def validate_email(cls, v: Optional[str]) -> Optional[str]:
        if v is not None and not re.match(r"^[^@\s]+@[^@\s]+\.[^@\s]+$", v):
            raise ValueError("Invalid email format")
        return v.lower() if v else None


# --- Custom error handler for Pydantic validation errors ---

from fastapi.exceptions import RequestValidationError


@app.exception_handler(RequestValidationError)
async def validation_error_handler(request: Request, exc: RequestValidationError):
    """Format validation errors in Stripe-style structure."""
    first_error = exc.errors()[0]
    field = ".".join(str(loc) for loc in first_error["loc"] if loc != "body")

    # Detect unknown field errors (extra="forbid")
    if first_error["type"] == "extra_forbidden":
        message = f"Received unknown parameter: {field}"
    else:
        message = first_error["msg"]

    return JSONResponse(
        status_code=400,
        content={
            "error": {
                "type": "invalid_request_error",
                "message": message,
                "param": field,
                "errors": [
                    {
                        "location": str(err["loc"][0]) if err["loc"] else "body",
                        "field": ".".join(
                            str(loc) for loc in err["loc"] if loc != "body"
                        ),
                        "message": err["msg"],
                    }
                    for err in exc.errors()
                ],
            }
        },
    )


# --- Routes ---


@app.get("/api/v1/users")
async def list_users(
    limit: int = Query(default=20, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
):
    # limit is guaranteed 1-100, offset >= 0 by FastAPI/Pydantic
    return {"data": [], "limit": limit, "offset": offset}


@app.post("/api/v1/users", status_code=201)
async def create_user(body: CreateUserRequest):
    # Body is validated and sanitized. Unknown fields rejected with:
    # 400: "Received unknown parameter: is_admin"
    return {"data": body.model_dump()}


@app.patch("/api/v1/users/{user_id}")
async def update_user(
    body: UpdateUserRequest,
    user_id: str = Path(...),
):
    # Validate prefixed ID format
    validate_prefixed_id(user_id, "usr")
    return {"data": {"id": user_id, **body.model_dump(exclude_none=True)}}
```

## Key Points

- **Unknown fields are rejected**, not silently ignored. `extra = "forbid"` in Pydantic, `.strict()` in Zod. This prevents mass assignment attacks where an attacker sends `{ "is_admin": true }` alongside legitimate fields
- **Body size limit is enforced before JSON parsing.** A 100 MB payload should never reach the parser. Set this at the middleware and web server levels
- **Content-Type is enforced.** A `POST` with `text/plain` is rejected before the handler runs
- **Prefixed ID validation** uses regex to reject path traversal and injection attempts. `/users/../../etc/passwd` fails the format check immediately
- **String sanitization** strips control characters that could cause display issues or log injection
- **Pagination is bounded.** `?limit=999999` is clamped to 100. `?offset=-1` is rejected. Defaults are explicit
- **Error format matches Stripe's convention:** `type`, `message`, `param` at the top level, with the first error's field in `param` for quick debugging
- **Enum validation** uses allowlists, not blocklists. The role field only accepts `viewer`, `editor`, `admin` -- every other value is rejected with a clear message listing allowed values
