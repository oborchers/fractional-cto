---
name: using-api-principles
description: This skill should be used when the user asks "which API design skill should I use", "show me all API principles", "help me pick an API pattern", or at the start of any RESTful API design conversation. Provides the index of all twelve principle skills and ensures the right ones are invoked before any API design work begins.
version: 1.0.0
---

<IMPORTANT>
When working on any RESTful API pattern — routes, naming, HTTP methods, error handling, authentication, pagination, caching, webhooks, versioning, or documentation — invoke the relevant api-design-principles skill BEFORE writing or reviewing code.

These are not suggestions. They are research-backed, opinionated principles drawn from Stripe, GitHub, Twilio, Shopify, Google, Microsoft, Zalando, Cloudflare, OWASP, and industry RFCs.
</IMPORTANT>

## How to Access Skills

Use the `Skill` tool to invoke any skill by name. When invoked, follow the skill's guidance directly.

## Available Skills

| Skill | Triggers On |
|-------|-------------|
| `api-design-principles:routes-and-naming` | URL design, endpoint naming, plural nouns, nesting depth, query vs path params, snake_case, field naming |
| `api-design-principles:http-methods` | GET/POST/PUT/PATCH/DELETE semantics, idempotency per verb, CRUD operations, method selection |
| `api-design-principles:prefixed-ids` | Type-safe identifiers, Stripe-style prefixed IDs (`cus_`, `ord_`), KSUID, ULID, ID generation |
| `api-design-principles:errors-and-status-codes` | HTTP status codes, error envelopes, per-field validation errors, RFC 9457, error formatting |
| `api-design-principles:response-design-and-pagination` | Response envelopes, cursor/offset/keyset pagination, expand patterns, list metadata |
| `api-design-principles:auth-and-api-keys` | API key design (`sk_live_`, `pk_test_`), OAuth 2.0, JWT, Bearer tokens, key rotation |
| `api-design-principles:rate-limiting-and-security` | Rate limiting algorithms/headers, OWASP API Top 10, CORS, input validation, request signing |
| `api-design-principles:versioning-and-evolution` | URL versioning (`/v1/`), date-based versioning, sunset headers, additive evolution, deprecation |
| `api-design-principles:caching-and-performance` | Cache-Control, ETags, conditional requests, CDN strategies, compression, circuit breakers |
| `api-design-principles:webhooks-and-events` | HMAC-SHA256 signing, retry logic, event naming (`resource.action`), webhook endpoints |
| `api-design-principles:documentation-and-dx` | API docs, interactive explorers, SDK generation, onboarding, time-to-first-call, changelogs |
| `api-design-principles:advanced-patterns` | Bulk/batch ops, REST vs GraphQL vs gRPC, SSE/WebSockets, multi-tenancy, API gateways, CQRS |

## When to Invoke Skills

Invoke a skill when there is even a small chance the work touches one of these areas:

- Designing or modifying any API endpoint, route, or resource
- Implementing authentication, authorization, or rate limiting
- Building error handling, response formatting, or pagination
- Reviewing existing API code for quality or consistency
- Making architectural decisions about caching, versioning, or real-time patterns
- Writing API documentation or designing developer onboarding

## The Three Meta-Principles

All twelve principles rest on three foundations:

1. **Consistency beats cleverness** — A predictable API that follows conventions everywhere is better than a clever API that surprises developers. Pick one pattern and apply it universally.

2. **Errors are part of the interface** — Every error response, status code, and validation message is as carefully designed as the happy path. Developers spend more time debugging than building.

3. **Optimize for the consumer, not the server** — API shape follows what makes client code simple, not what matches the database schema. The server does extra work so every client doesn't have to.
