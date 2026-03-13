# Lossy Compression Techniques

Lossy compression rewrites content for maximum semantic density. Unlike lossless mode, this changes wording and may remove information deemed non-critical. The compressor-reviewer loop catches over-aggressive compression.

## Technique Catalog

### 1. Imperative Conversion

Convert descriptive, passive, or hedging language to direct imperative instructions.

**Before:**
```markdown
It's generally recommended that you should validate all user input before
processing it. This helps prevent security vulnerabilities and ensures
data integrity throughout the system.
```

**After:**
```markdown
Validate all user input before processing. Prevents security vulnerabilities and ensures data integrity.
```

**Token reduction:** ~50%

**Rule:** Strip "It's recommended", "You should", "It's important to", "Make sure to", "Remember to", "Please ensure". Start with the verb.

### 2. Deduplication Across Sections

Identify concepts stated multiple times and keep only the most complete version.

**Before:**
```markdown
## Overview
Always use parameterized queries to prevent SQL injection.

## Database
Use parameterized queries for all database operations. Never concatenate
user input into SQL strings, as this creates SQL injection vulnerabilities.

## Security
SQL injection prevention: use parameterized queries instead of string
concatenation.
```

**After:**
```markdown
## Overview
Use parameterized queries for all database operations. Never concatenate user input into SQL strings.

## Database
(SQL injection prevention covered in Overview.)

## Security
(SQL injection prevention covered in Overview.)
```

Or better — remove the cross-references entirely if the LLM will process the full file:

**After (preferred):**
```markdown
## Overview
Use parameterized queries for all database operations. Never concatenate user input into SQL strings.
```

**Handling orphaned sections:** When deduplication removes most or all content from a section, the heading is left without context. Three options, in order of preference:

1. **Remove the heading entirely** if the section has no remaining unique content
2. **Add a one-line cross-reference** if the heading is a natural navigation landmark: `Standard auth pattern: see Function Structure Pattern above.`
3. **Merge the heading into an adjacent section** if the remaining content fits naturally elsewhere

Never leave a section heading followed immediately by a sub-heading with no introductory content — this creates a "headless section" that disorients readers scanning by heading structure.

### 3. Prose-to-Table Conversion

Convert parallel-structured prose into tables when items share common attributes.

**Before:**
```markdown
## Error Codes

The 400 error means the request was malformed. The client should fix the
request body and retry. The 401 error means authentication failed. The
client should refresh their token. The 403 error means the user doesn't
have permission. The client should request elevated access. The 429 error
means rate limiting. The client should back off and retry after the
Retry-After header value.
```

**After:**
```markdown
## Error Codes

| Code | Meaning | Client Action |
|------|---------|---------------|
| 400 | Malformed request | Fix request body, retry |
| 401 | Auth failed | Refresh token |
| 403 | No permission | Request elevated access |
| 429 | Rate limited | Backoff per `Retry-After` header |
```

**Token reduction:** ~40%

### 4. Inline Consolidation

Collapse nested structures into inline parenthetical or dash-separated formats when the sub-items are short.

**Before:**
```markdown
## Caching

- **Strategy:** LRU
  - **Max size:** 1000 entries
  - **TTL:** 300 seconds
  - **Eviction:** When memory exceeds 512MB
```

**After:**
```markdown
## Caching

LRU cache — max 1000 entries, 300s TTL, evict at 512MB.
```

### 5. Implied Knowledge Deletion

Remove explanations of concepts the LLM already knows. Only state what is specific to *this* system.

**Before:**
```markdown
## Authentication

We use JWT (JSON Web Tokens) for authentication. JWT is a compact,
URL-safe means of representing claims to be transferred between two
parties. The claims in a JWT are encoded as a JSON object that is
digitally signed.

Tokens expire after 1 hour. Refresh tokens expire after 30 days.
Use the `Authorization: Bearer <token>` header format.
```

**After:**
```markdown
## Authentication

JWT auth. Tokens expire 1h, refresh tokens 30d. Header: `Authorization: Bearer <token>`.
```

**Token reduction:** ~65%

**Rule:** Delete explanations of standard protocols (JWT, OAuth, REST, GraphQL, gRPC), common data formats (JSON, YAML, TOML), well-known patterns (MVC, pub/sub, CQRS), and language features (async/await, generics, closures).

### 6. Example Triage

When multiple examples illustrate the same concept, keep only the most distinctive one.

**Before:**
```markdown
## Naming Convention

Use snake_case for variables:

```python
user_name = "Alice"
account_balance = 100.50
is_active = True
max_retry_count = 3
database_connection_string = "postgresql://..."
```
```

**After:**
```markdown
## Naming Convention

snake_case for variables: `user_name`, `database_connection_string`.
```

**Rule:** Keep examples that show edge cases, non-obvious behavior, or the longest/most complex form. Delete examples that show the obvious application of the rule.

**Critical distinction — operational vs. illustrative examples:**

Not all code examples serve the same purpose. Distinguish between:

- **Operational examples** — meant to be copy-pasted and executed verbatim: curl commands, CLI invocations, config snippets, environment setup blocks, Makefile targets. These earn their tokens because users run them directly. Compress whitespace within them but **preserve the full runnable command**.
- **Illustrative examples** — showing a pattern or convention: code samples demonstrating naming conventions, architecture patterns, API usage. These are compressible — inline them, shorten them, or replace with the shortest form that conveys the pattern.

**Before (operational curl block compressed away):**
```markdown
Same pattern as local — substitute DEV_URL and DEV_ANON_KEY.
```

**After (operational curl block preserved):**
```markdown
```bash
TOKEN=$(curl -s "$DEV_URL/auth/v1/token?grant_type=password" \
  -H "apikey: $DEV_ANON_KEY" -H "Content-Type: application/json" \
  -d '{"email":"your@email.com","password":"yourpassword"}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")
curl -X POST "$DEV_URL/functions/v1/hello-world" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -d '{"name":"Test"}'
`` `
```

The first version saves ~50 tokens but forces the user to reconstruct the commands mentally. The second is copy-pasteable and worth the tokens.

### 7. Section Merging

Combine sections that share >50% of their content or that address the same topic from slightly different angles.

**Before:**
```markdown
## Input Validation

Validate all string inputs for length (max 255 chars) and allowed characters.
Reject null values early.

## Data Sanitization

Sanitize string inputs by escaping HTML entities. Trim whitespace.
Reject null values before processing.
```

**After:**
```markdown
## Input Validation & Sanitization

Validate all string inputs: max 255 chars, allowed characters only, no nulls. Escape HTML entities, trim whitespace.
```

### 8. Conditional Compression

Compress complex conditional logic into decision tables or compact if-then notation.

**Before:**
```markdown
## Rate Limiting

If the user is on the free plan, they get 100 requests per hour. If they
exceed this, return a 429 error with a Retry-After header. If the user
is on the pro plan, they get 1000 requests per hour. Enterprise users
get 10000 requests per hour. If any user exceeds their limit by more
than 50%, temporarily block the API key for 1 hour.
```

**After:**
```markdown
## Rate Limiting

| Plan | Limit/hr |
|------|----------|
| Free | 100 |
| Pro | 1,000 |
| Enterprise | 10,000 |

Exceed limit: 429 + `Retry-After`. Exceed by >50%: block API key 1h.
```

### 9. Boilerplate Stripping

Remove standard disclaimers, motivational text, and organizational preamble that don't affect LLM behavior.

**Before:**
```markdown
# API Guidelines

Welcome to our API guidelines! These guidelines have been carefully
crafted by our engineering team over the past two years. We believe
strongly in API consistency and developer experience. Please take the
time to read through these guidelines carefully before starting any
API development work.

## Getting Started

Before diving in, let's establish some common ground...
```

**After:**
```markdown
# API Guidelines

## Getting Started
```

### 10. Abbreviation Where Unambiguous

Use standard abbreviations when context makes them unambiguous.

| Full Form | Abbreviation | Use When |
|-----------|-------------|----------|
| configuration | config | Always in tech context |
| environment | env | Always in tech context |
| authentication | auth | Always in tech context |
| authorization | authz | When auth already means authentication |
| application | app | Always in tech context |
| development | dev | Always in tech context |
| production | prod | Always in tech context |
| repository | repo | Always in git context |
| dependencies | deps | Always in package context |
| documentation | docs | Always |

## Judgment Heuristics

### Keep If:
- Removing it would change behavior ("timeout is 30s" vs "use a timeout")
- It handles an edge case the LLM wouldn't infer
- It overrides default behavior or common assumptions
- It's a prohibition ("NEVER", "DO NOT", "MUST NOT")
- It's a specific identifier (file path, env var, API endpoint)
- It's an operational example meant to be copy-pasted (curl, CLI, config snippets)

### Remove If:
- It restates what the heading already says
- It explains a concept the LLM knows from training data
- It motivates rather than instructs ("This is important because...")
- It's one of multiple illustrative examples showing the same pattern
- It appeared earlier in the document with equal or greater specificity
- Deduplication left a section heading with no remaining unique content

### Compress (Don't Remove) If:
- It contains both useful specifics and unnecessary prose
- It's a valid instruction wrapped in hedging language
- It's a long example that could be a short inline example

## Compression Aggressiveness Levels

The section-compressor agent should target aggressive compression. The reviewer catches when it went too far.

| Aspect | Aggressive (Target) | Conservative (Fallback) |
|--------|-------------------|----------------------|
| Prose | Imperative fragments | Short sentences |
| Examples | 1 per concept, inline | 1-2 per concept, code blocks |
| Explanations | Delete if implied | Keep if non-obvious |
| Structure | Tables, inline | Preserve original format |
| Transitions | Delete all | Delete most |
