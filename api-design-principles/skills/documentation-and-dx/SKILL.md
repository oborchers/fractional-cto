---
name: documentation-and-dx
description: "Use when writing API reference documentation with OpenAPI specs, designing developer onboarding flows to reduce time-to-first-API-call, building interactive try-it API explorers with Swagger UI or Redoc, generating SDKs with Stainless or Fern using hybrid auto-generated plus hand-crafted wrappers, creating multi-language code examples in cURL Python and Node.js, setting up sandbox environments with test keys and magic values, implementing API changelogs with deprecation timelines and Sunset headers, running contract tests with Schemathesis or Dredd in CI, or linting OpenAPI specs with Spectral or Redocly CLI. Covers three-panel docs layout, TTFAC optimization, interactive explorers, sandbox design, error message documentation with doc_url fields, SDK generation strategy, changelog management, design-first API review workflow, and contract testing in CI."
version: 1.0.0
---

# API Documentation and Developer Experience

Documentation is the primary driver of API adoption. The goal: time-to-first-API-call (TTFAC) under 5 minutes, every error self-documenting, and SDKs that feel native.

## Three-Panel Docs Layout

Adopt the Stripe pattern: navigation left, conceptual content center, runnable code right.

- **Navigation:** Organize by task ("Accept a Payment"), not by HTTP method. Two levels maximum.
- **Content:** One-sentence opener per page, minimal request first, optional params in collapsible sections. Cross-link reference pages to tutorials and back.
- **Code panel:** Persist language selection site-wide via cookie/local storage. Pre-fill the developer's actual test API key into every example — never show `YOUR_API_KEY`.

## Onboarding Flow (TTFAC < 5 Minutes)

1. **Sign up** — email and password only, no credit card
2. **Get API key** — visible on dashboard immediately, no email verification for sandbox
3. **Make first call** — pre-filled cURL command from docs
4. **Install SDK** — one-line install for their language
5. **Create a resource** — guided sandbox example
6. **Receive a webhook** — CLI tool or ngrok instructions, trigger test event

Track TTFAC as a product metric. Measure in user testing. Optimize quarterly.

## Code Examples

Provide examples in cURL, Python, and Node.js at minimum. Every example must be complete and runnable.

- Show real JSON responses with actual field names and nesting — never `{ ... }`
- Make examples idiomatic: Python uses `requests`, Node uses `async/await`, Go handles errors explicitly
- Consistent variable names and test data across languages for the same endpoint
- Minimal examples first, collapsible "full example" for production-ready code

**Docs hierarchy:** Quickstart → Task-oriented guides → API Reference → SDKs → Webhooks → Testing → Changelog

## Interactive Explorers

Embed try-it panels (Swagger UI, Redoc) with pre-populated sandbox credentials. Show equivalent cURL alongside GUI. Persist state across requests (auto-populate created resource IDs). Show request and response headers, not just bodies.

**Tiers:** Embedded try-it (minimum) → Postman workspace / custom console → Guided interactive tutorials (best).

## Sandbox Environments

Use the "separate keys" pattern — test keys (`sk_test_...`) hit the same API, separate database.

- Sandbox behaves identically to production: same endpoints, validation, rate limits, error formats
- Provide magic test values for every error scenario (card declined, insufficient funds, network timeout) and document each
- Auto-delete sandbox data after 30 days or provide a "reset sandbox" button
- Include simulated test accounts for complex flows (Plaid model: `user_good / pass_good`)

## Error Messages as Documentation

Every error response includes:

| Field | Purpose |
|-------|---------|
| `type` | Machine-readable category (`invalid_request_error`) |
| `code` | Specific error code (`amount_too_small`) |
| `message` | Human-readable: what went wrong and what to do |
| `param` | Request parameter that caused the error |
| `doc_url` | Link to help page for this specific error |
| `suggestion` | Optional actionable fix ("Set amount to at least 50 for USD") |

Include the problematic value in messages: `"'uds' is not a valid currency. Did you mean 'usd'?"`. Consistent status codes: 400 malformed, 401 missing auth, 403 forbidden, 404 not found, 422 business rule, 429 rate limit.

## SDK Generation Strategy

Use the **hybrid approach**: generate a base client from the OpenAPI spec (Stainless, Fern, Speakeasy), then layer hand-crafted ergonomic wrappers.

1. Generate base client from OpenAPI spec
2. Add ergonomic wrappers: custom method names, builder patterns, convenience methods
3. Generate tests from spec to validate the hand-crafted layer
4. Hand-write quickstart docs, auto-generate reference docs

Target: `stripe.PaymentIntent.create(amount=2000, currency="usd")`, not `client.apis.default_api.create_payment_intent_api_v1_payment_intents_post(...)`.

## Changelog and Deprecation

Maintain date-stamped changelog: Added, Changed, Deprecated, Removed, Fixed. RSS/Atom feed. Dashboard banners for approaching end-of-life.

**Migration guide format:** What changed → Why → Step-by-step code diff → Deadline → Testing instructions.

**Deprecation lifecycle:**
1. **Announce** (6–12 months out): Email, dashboard warning, changelog, docs notice
2. **Warn** (3–6 months): `Sunset` + `Deprecation` response headers, per-key usage tracking
3. **Brownout** (1–2 months): Periodic downtime of deprecated endpoints
4. **Sunset**: Return `410 Gone` with migration guide URL in response body

## Design-First API Review

Write the OpenAPI spec before code. The spec is the contract.

1. Product requirements → Write OpenAPI spec
2. Lint with Spectral (snake_case, required descriptions, required examples)
3. Design review by 1–2 API-experienced engineers
4. Generate mock server with Prism for frontend development
5. Backend implements against spec
6. Contract tests verify implementation matches spec

## Contract Testing in CI

Run on every pull request:

1. Lint OpenAPI spec with Redocly CLI
2. Check breaking changes with Optic (compare against main branch)
3. Start API server
4. Run Schemathesis with `--checks all` for fuzz testing
5. Run Dredd for strict compliance testing

Verify: response schemas match spec, required fields present, status codes correct, error responses conform, pagination `has_more` accurate, Content-Type headers correct.

## Review Checklist

- [ ] Three-panel layout with persistent language selection
- [ ] TTFAC under 5 minutes (measured, not estimated)
- [ ] Code examples in cURL, Python, and Node.js at minimum, all complete and runnable
- [ ] Interactive try-it explorer with pre-filled sandbox credentials
- [ ] Sandbox behaves identically to production with documented magic test values
- [ ] Onboarding covers signup through first webhook in under 10 minutes
- [ ] Every error response includes `type`, `code`, `message`, `param`, and `doc_url`
- [ ] SDKs generated from OpenAPI spec with hand-crafted ergonomic wrappers
- [ ] Changelog date-stamped, categorized, available via RSS feed
- [ ] OpenAPI spec linted in CI with Spectral, breaking changes checked with Optic
- [ ] Contract tests (Schemathesis and/or Dredd) run on every pull request
- [ ] API design review happens before implementation
