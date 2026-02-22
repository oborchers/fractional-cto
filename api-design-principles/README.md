# api-design-principles

A Claude Code plugin that codifies world-class RESTful API design — research-backed, opinionated guidance drawn from Stripe, GitHub, Twilio, Shopify, Google, Microsoft, Zalando, Cloudflare, OWASP, and industry RFCs.

## What It Does

When Claude is working on API design — routes, errors, authentication, pagination, caching, webhooks, or any of the patterns below — the relevant principle skill activates automatically and guides the work with specific, actionable rules and review checklists.

This plugin provides **principles and examples, not boilerplate.** It tells Claude *what* to build and *why*, with code patterns in Node.js/Express and Python/FastAPI showing *how*.

## The 12 Principles

| # | Principle | Skill | What It Covers |
|---|-----------|-------|----------------|
| I | URLs are your API's user interface | `routes-and-naming` | Plural nouns, nesting depth, snake_case, query vs path params, field naming |
| II | Every verb is a promise | `http-methods` | GET/POST/PUT/PATCH/DELETE semantics, idempotency, CRUD patterns |
| III | Every ID should declare its type | `prefixed-ids` | Stripe-style prefixed IDs, ULID/KSUID, validation, prefix registries |
| IV | Errors are part of your API's interface | `errors-and-status-codes` | HTTP status codes, RFC 9457, error envelopes, per-field validation |
| V | Responses are contracts, not accidents | `response-design-and-pagination` | Envelopes, cursor pagination, expand/embed, list metadata |
| VI | Authentication should be invisible until it isn't | `auth-and-api-keys` | Prefixed API keys, OAuth 2.0, JWT, key rotation, 401 vs 403 |
| VII | Guard every gate, log every attempt | `rate-limiting-and-security` | Sliding window, token bucket, OWASP Top 10, CORS, input validation |
| VIII | Ship v1 and never break it | `versioning-and-evolution` | URL versioning, additive evolution, sunset headers, migration guides |
| IX | The fastest request is the one you never make | `caching-and-performance` | Cache-Control, ETags, CDN, compression, circuit breakers |
| X | Webhooks are promises you must keep | `webhooks-and-events` | HMAC-SHA256 signing, retries, event naming, deduplication |
| XI | Your docs are your best salesperson | `documentation-and-dx` | Three-panel docs, time-to-first-call, SDKs, sandbox, contract testing |
| XII | Know when to break the REST rules | `advanced-patterns` | Bulk/batch, REST vs GraphQL vs gRPC, SSE/WebSockets, multi-tenancy |

## Installation

### Claude Code (via vibe-cto Marketplace)

```bash
# Register the marketplace (once)
/plugin marketplace add oborchers/vibe-cto

# Install the plugin
/plugin install api-design-principles@vibe-cto
```

### Local Development

```bash
# Test directly with plugin-dir flag
claude --plugin-dir /path/to/vibe-cto/api-design-principles
```

## Components

### Skills (13)

One meta-skill (`using-api-principles`) that provides the index and 12 principle skills that activate automatically when Claude detects relevant API design patterns.

Each skill includes:
- Research-backed principles with cited sources
- Good/bad examples with concrete code
- Actionable review checklists
- Code examples in Node.js and Python (where applicable)

### Command (1)

- `/api-review` — Review the current API code against all relevant design principles

### Agent (1)

- `api-design-reviewer` — Comprehensive API audit agent that evaluates code against all 12 principles with severity-rated findings

### Hook (1)

- `SessionStart` — Injects the skill index at the start of every session so Claude knows the principles are available

## The Three Meta-Principles

All twelve principles rest on three foundations:

1. **Consistency beats cleverness** — A predictable API that follows conventions everywhere is better than a clever API that surprises developers
2. **Errors are part of the interface** — Every error response, status code, and validation message is as carefully designed as the happy path
3. **Optimize for the consumer, not the server** — API shape follows what makes client code simple, not what matches the database schema

## License

MIT
