# Lossy Compression Example

## Before (agent instruction excerpt — 412 tokens)

```markdown
## API Error Handling

When working with API errors, it's important to follow our established
patterns consistently. This ensures a good developer experience for our
API consumers and makes debugging easier for our team.

### HTTP Status Codes

We use standard HTTP status codes in our API responses. Here's what each
one means:

- **400 Bad Request**: This error is returned when the client sends a
  malformed request. The response body should include a detailed error
  message explaining what was wrong with the request. The client should
  fix the request and try again.
- **401 Unauthorized**: This means authentication has failed. The client
  should check their API key or refresh their authentication token.
- **403 Forbidden**: The authenticated user doesn't have permission to
  access this resource. The client should request elevated access from
  an administrator.
- **404 Not Found**: The requested resource doesn't exist. Make sure to
  check that you're using the correct resource identifier.
- **429 Too Many Requests**: The client has exceeded the rate limit.
  Include a Retry-After header in the response to tell the client when
  they can try again.
- **500 Internal Server Error**: Something went wrong on our end. Log
  the error with full context and return a generic error message to the
  client. Never expose internal error details.

### Error Response Format

All error responses should follow this format:

```json
{
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "Human-readable error description",
    "details": []
  }
}
```

This is important because it gives API consumers a consistent structure
to parse errors programmatically. The code field should be a machine-
readable string, while the message field should be human-readable.

Remember to always include the error code — it's the primary way clients
handle errors programmatically.
```

## After (lossy — 148 tokens, 64% reduction)

```markdown
## API Error Handling

### Status Codes

| Code | Meaning | Client Action | Server Action |
|------|---------|---------------|---------------|
| 400 | Malformed request | Fix request, retry | Include detailed error message |
| 401 | Auth failed | Check API key / refresh token | — |
| 403 | No permission | Request elevated access | — |
| 404 | Not found | Verify resource ID | — |
| 429 | Rate limited | Wait per `Retry-After` | Include `Retry-After` header |
| 500 | Server error | — | Log full context, return generic message. Never expose internals. |

### Error Response Format

```json
{
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "Human-readable description",
    "details": []
  }
}
```

`code`: machine-readable string (primary error-handling key). `message`: human-readable. Always include both.
```

## What Changed

| Technique | Application |
|-----------|------------|
| Boilerplate stripping | Removed motivational intro paragraph |
| Prose-to-table | Converted status code list to table |
| Implied knowledge deletion | Removed "HTTP status codes are standard" explanation |
| Imperative conversion | Shortened all instructions to direct form |
| Inline consolidation | Collapsed error format explanation into one line |
| Deduplication | "Always include error code" appeared twice, kept once |

## What Was Preserved

- All 6 status codes and their exact behaviors
- Server-side vs client-side responsibilities
- Error response JSON structure
- The prohibition "Never expose internal error details"
- The requirement to always include error code
- The Retry-After header requirement
