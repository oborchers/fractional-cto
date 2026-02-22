---
name: errors-and-status-codes
description: "This skill should be used when the user is designing API error responses, choosing HTTP status codes, implementing error envelopes, handling validation errors, creating per-field error messages, or following RFC 9457 Problem Details. Covers status code selection (2xx-5xx), consistent error formats, Stripe/GitHub/Twilio error patterns, and request/trace ID correlation."
version: 1.0.0
---

# Errors Are Part of Your API's Interface

A well-designed error response teaches the developer what went wrong, points them to the fix, and gives their code enough information to handle it automatically. Bad errors generate support tickets. Good errors eliminate them.

The HTTP status code is the first thing a client reads. It must be accurate, specific, and machine-actionable. The status code conveys the category of outcome; the response body conveys the detail. Never return 200 with `{ "success": false }` -- it breaks HTTP semantics, defeats monitoring, and confuses every layer of infrastructure between your server and the client.

## Status Code Decision Table

Pick the most specific code that applies. When in doubt, move down the table.

### 2xx -- Success

| Code | When to Use |
|------|-------------|
| **200 OK** | GET, PUT, PATCH, and POST actions that are not resource creation. Return the resource. |
| **201 Created** | A new resource was created. Return the resource and a `Location` header with its URI. |
| **202 Accepted** | Async work was queued but not yet complete. Return a status object with a job URL. |
| **204 No Content** | Success with intentionally no body. Use for DELETE. Also valid for PUT/PATCH when you omit the updated resource. |

### 3xx -- Redirects

| Code | When to Use |
|------|-------------|
| **301 Moved Permanently** | Resource has a new canonical URI. Clients should update bookmarks. |
| **304 Not Modified** | Resource unchanged since `If-None-Match` or `If-Modified-Since`. Critical for caching. |
| **307 Temporary Redirect** | Temporary reroute, method and body preserved. |

### 4xx -- Client Errors

| Code | When to Use |
|------|-------------|
| **400 Bad Request** | Malformed request. Unparseable JSON, missing required top-level fields, wrong content type. The problem is syntactic. |
| **401 Unauthorized** | Authentication failed or missing. "Who are you?" |
| **403 Forbidden** | Authenticated but not authorized. "I know who you are, and you cannot do this." |
| **404 Not Found** | Resource does not exist. Also use 404 instead of 403 to hide resource existence from unauthorized callers. |
| **405 Method Not Allowed** | HTTP method not supported. Include an `Allow` header listing valid methods. |
| **409 Conflict** | State conflict -- duplicate resource, concurrent modification, invalid state transition. |
| **422 Unprocessable Content** | Syntactically valid but semantically invalid. Business rule violations, field-level validation failures. |
| **429 Too Many Requests** | Rate limit exceeded. Must include `Retry-After` header. |

### 5xx -- Server Errors

| Code | When to Use |
|------|-------------|
| **500 Internal Server Error** | Unhandled exception, bug in server code. Never expose stack traces. |
| **502 Bad Gateway** | Upstream service returned an invalid response. |
| **503 Service Unavailable** | Temporarily unable to handle requests. Include `Retry-After`. |
| **504 Gateway Timeout** | Upstream service timed out. |

**Retry guidance:** Clients should retry on 429, 503, and 504 with exponential backoff. They should not blindly retry on 500 (may not be idempotent-safe).

## The 400 vs 422 Rule

Use 400 when the request is structurally broken -- unparseable JSON, missing content type, absent required fields. Use 422 when the JSON is well-formed and all required fields are present, but the data itself is invalid -- `email` is not a valid email, `start_date` is after `end_date`, `quantity` is negative.

This distinction matters because it tells the client whether the problem is a bug in their request construction (400) or invalid user input that should be surfaced in a form (422).

## The 401 vs 403 Rule

Use 401 when the client has not proven its identity -- missing token, expired token, invalid API key. Re-authenticating can fix it. Use 403 when the client is authenticated but lacks the required permissions. Re-authenticating will not help; they need different access rights.

**Security exception:** When a client requests a resource they are not even authorized to know about, return 404 instead of 403 to prevent enumeration attacks. GitHub does this -- accessing a private repository you are not a member of returns 404.

## The Error Envelope

Use one consistent structure for every error response across every endpoint. Clients should never need to handle multiple error formats.

```json
{
  "type": "https://api.example.com/errors/validation-error",
  "title": "Validation Error",
  "status": 422,
  "detail": "2 fields failed validation.",
  "code": "validation_error",
  "instance": "urn:request:a1b2c3d4-e5f6-7890",
  "errors": [
    {
      "field": "email",
      "code": "invalid_format",
      "message": "Must be a valid email address.",
      "rejected_value": "not-an-email"
    },
    {
      "field": "password",
      "code": "too_short",
      "message": "Must be at least 8 characters."
    }
  ],
  "doc_url": "https://api.example.com/docs/errors/validation-error"
}
```

**Field purposes:**

| Field | For | Audience |
|-------|-----|----------|
| `type` | RFC 9457 problem type URI. Dereferenceable to docs. | Standards-compliant clients, API gateways |
| `title` | Stable human-readable summary. Never changes between occurrences. | Logging, generic displays |
| `status` | HTTP status code mirrored in body. | Clients that lose the HTTP layer (queues, logs) |
| `detail` | Occurrence-specific explanation. | Developer debugging |
| `code` | Machine-readable stable string. Clients switch on this. | Client error-handling logic |
| `instance` | Request or trace ID. | Support correlation, log lookups |
| `errors[]` | Per-field validation details. | Form UIs highlighting individual fields |
| `doc_url` | Link to detailed error documentation. | Developers integrating your API |

Set the `Content-Type` header to `application/problem+json` for RFC 9457 compliance.

## Per-Field Validation Errors

Return all validation errors at once, not one at a time. Each entry in `errors[]` must include the field path, a machine-readable code, and a human-readable message.

For nested objects, use dot notation: `billing_address.zip_code`. For arrays, use bracket notation: `line_items[0].quantity`. This mirrors JSON Pointer in a more developer-friendly form.

```json
{
  "errors": [
    {
      "field": "billing_address.zip_code",
      "code": "invalid_format",
      "message": "Must be a 5-digit ZIP code."
    },
    {
      "field": "line_items[0].quantity",
      "code": "out_of_range",
      "message": "Must be between 1 and 1000."
    }
  ]
}
```

Include `rejected_value` when the value is not sensitive. Omit it for passwords, tokens, and secrets. The `code` field is for machines -- clients switch on it. The `message` field is for humans -- clients must never parse or match on message strings.

## RFC 9457 Problem Details

RFC 9457 (2023, superseding RFC 7807) defines a standard error format for HTTP APIs. Adopt it as your base. The five standard fields are `type`, `title`, `status`, `detail`, and `instance`. Extension fields like `code`, `errors[]`, and `doc_url` are explicitly allowed and encouraged.

The `type` URI serves double duty: it is a machine-readable identifier and, when dereferenced, links to human-readable documentation. Default it to `"about:blank"` if you have no specific error type page.

## Industry Error Shapes

### Stripe

```json
{
  "error": {
    "type": "invalid_request_error",
    "code": "parameter_missing",
    "message": "Missing required param: source.",
    "param": "source",
    "doc_url": "https://stripe.com/docs/error-codes/parameter-missing"
  }
}
```

Lessons: Hierarchy of specificity (`type` -> `code` -> `message`). The `param` field maps directly to form fields. Every error links to its documentation page. Errors are wrapped in `"error": {}` to distinguish from success responses.

### GitHub

```json
{
  "message": "Validation Failed",
  "errors": [
    { "resource": "Issue", "field": "title", "code": "missing_field" }
  ],
  "documentation_url": "https://docs.github.com/rest/reference/issues"
}
```

Lessons: Each error identifies the resource, field, and code. Codes are a small, stable enum (`missing`, `missing_field`, `invalid`, `already_exists`, `unprocessable`). Documentation URL always present.

### Twilio

```json
{
  "code": 21211,
  "message": "The 'To' number is not a valid phone number.",
  "more_info": "https://www.twilio.com/docs/errors/21211",
  "status": 400
}
```

Lessons: Numeric error codes, each with a dedicated documentation page. Flat structure, one error per response. Simpler but less expressive for batch validation.

**Takeaway:** All three leaders share the same pattern -- a stable machine-readable code, a human-readable message, and a link to documentation. Adopt all three in your error envelope.

## Error Messages as Documentation

Every error response should include a `doc_url` that links to a page explaining the error in detail -- causes, solutions, and examples. Stripe, GitHub, and Twilio all do this. The incremental cost of maintaining these pages is low; the reduction in support tickets is significant.

Write `message` and `detail` fields as if they will be the only thing a developer reads. Be specific: "The `start_date` field must be before `end_date`" beats "Invalid date range." Be actionable: tell the developer what to do, not just what went wrong.

## Request and Trace IDs

Generate a unique request ID for every incoming request. Return it in a response header (`X-Request-Id` or `Request-Id`) and embed it in error responses as the `instance` field. When a developer files a support ticket, the request ID lets you jump directly to the relevant log entries, traces, and metrics.

For distributed systems, propagate a trace ID across service boundaries and include it alongside the request ID. This turns a vague "the API returned 500" into a precise trail through your infrastructure.

## Good vs Bad Error Responses

**Bad -- 200 with error body:**

```json
HTTP/1.1 200 OK
{ "success": false, "error": "User not found" }
```

Problems: Infrastructure sees success. No machine-readable code. No doc link.

**Good -- correct status code, structured envelope:**

```json
HTTP/1.1 404 Not Found
Content-Type: application/problem+json

{
  "type": "https://api.example.com/errors/resource-not-found",
  "title": "Resource Not Found",
  "status": 404,
  "detail": "No user found with ID 99999.",
  "code": "user_not_found",
  "instance": "urn:request:a1b2c3d4",
  "doc_url": "https://api.example.com/docs/errors/resource-not-found"
}
```

**Bad -- single string for multiple validation errors:**

```json
HTTP/1.1 400 Bad Request
{ "error": "Invalid email and password too short" }
```

Problems: Cannot map to form fields. Client must parse natural language. Rewording breaks clients.

**Good -- per-field, coded validation errors:**

```json
HTTP/1.1 422 Unprocessable Content
Content-Type: application/problem+json

{
  "type": "https://api.example.com/errors/validation-error",
  "title": "Validation Error",
  "status": 422,
  "detail": "2 fields failed validation.",
  "code": "validation_error",
  "errors": [
    { "field": "email", "code": "invalid_format", "message": "Must be a valid email address." },
    { "field": "password", "code": "too_short", "message": "Must be at least 8 characters." }
  ],
  "doc_url": "https://api.example.com/docs/errors/validation-error"
}
```

**Bad -- 500 with stack trace:**

```json
HTTP/1.1 500 Internal Server Error
{ "error": "NullPointerException at UserService.java:142", "stack": "..." }
```

**Good -- safe 500 with trace ID:**

```json
HTTP/1.1 500 Internal Server Error
Content-Type: application/problem+json

{
  "type": "https://api.example.com/errors/internal-error",
  "title": "Internal Server Error",
  "status": 500,
  "detail": "An unexpected error occurred. Please try again later.",
  "code": "internal_error",
  "instance": "urn:request:a1b2c3d4-e5f6-7890"
}
```

## Examples

Working implementations in `examples/`:
- **`examples/error-envelope-implementation.md`** -- Complete error response system with typed error classes, consistent envelope, per-field validation errors, and request ID injection
- **`examples/status-code-middleware.md`** -- Centralized error handler middleware that maps exceptions to correct status codes and formats

## Review Checklist

When designing or reviewing API error responses:

- [ ] Every error uses the correct HTTP status code (4xx for client errors, 5xx for server, never 200)
- [ ] All endpoints return a single, consistent error structure
- [ ] The error structure includes a machine-readable `code` that is stable and documented
- [ ] The error structure includes a human-readable `message` or `detail` for developers
- [ ] Validation errors return per-field details with field path, code, and message
- [ ] 400 is reserved for malformed requests; 422 for semantically invalid input
- [ ] 401 is used for authentication failures; 403 for authorization failures
- [ ] 429 responses include a `Retry-After` header and rate limit context
- [ ] 500 errors never expose stack traces, internal paths, or implementation details
- [ ] Every error response includes a request/trace ID for support correlation
- [ ] Error responses include a `doc_url` or dereferenceable `type` URI linking to documentation
- [ ] The `Content-Type` is set to `application/problem+json` for error responses
