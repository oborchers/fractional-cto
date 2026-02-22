---
name: documentation-and-dx
description: "This skill should be used when the user is writing API documentation, designing developer onboarding, building interactive API explorers, generating SDKs, creating code examples, setting up sandbox environments, implementing API changelogs, or optimizing time-to-first-API-call. Covers three-panel docs layout, interactive try-it functionality, multi-language examples, and developer experience optimization."
version: 1.0.0
---

# Your Docs Are Your Best Salesperson

Documentation is the #1 factor in API adoption. SmartBear surveys consistently show that "accurate and detailed documentation" is the top requirement developers cite when evaluating an API. Stripe and Twilio did not win because they had better infrastructure -- they won because their docs made developers productive in minutes, not days. Every hour you invest in documentation returns tenfold in reduced support tickets, faster integration times, and higher conversion from free-tier to paid.

## Three-Panel Layout

Adopt the Stripe three-panel pattern: navigation on the left, conceptual content in the center, runnable code on the right. This layout lets developers read context and copy code simultaneously without scrolling or switching tabs.

**Navigation panel rules:**
- Organize by task ("Accept a Payment", "Create a Subscription"), not by HTTP method or endpoint path
- Group related tasks under domain headings (Payments, Billing, Identity)
- Keep the nav tree to two levels maximum -- a third level means the information architecture needs restructuring

**Content panel rules:**
- Open every page with a one-sentence description of what the endpoint or concept does
- Show the minimal request first, then reveal optional parameters in collapsible sections
- Cross-link aggressively: every reference page links to a relevant tutorial, and every tutorial links back to the reference

**Code panel rules:**
- Persist the developer's language selection across the entire docs site using a cookie or local storage
- When a developer selects Python, every code example site-wide switches to Python instantly

## Time to First API Call Under 5 Minutes

"Time to first API call" (TTFAC) is the single most important developer experience metric. Stripe achieves approximately 3 minutes. AWS takes 30+ minutes. The difference is not complexity -- it is onboarding design.

**The ideal onboarding flow:**
1. Sign up with email and password -- no credit card required
2. Dashboard immediately shows API keys with no email verification required for sandbox access
3. A "Get Started" page presents a cURL command pre-filled with the developer's actual test key
4. The developer pastes the command, sees a real response, and feels accomplishment
5. "Next steps" links lead to SDK quickstarts in their chosen language

**Pre-fill everything.** When a developer is logged into your docs site, render their real test API key directly into every code example. Never show `YOUR_API_KEY` as a placeholder. Copy-paste friction kills onboarding.

## Code Examples in 3+ Languages

Provide code examples in at minimum cURL, Python, and JavaScript/Node.js. High-value additions are Ruby, PHP, Java, and Go. Every example must be complete and runnable -- no `// ... your code here ...` placeholders, no truncated response bodies.

**Quality rules:**
- Show real JSON responses with actual field names, types, and nesting -- never `{ ... }`
- Make examples idiomatic: Python uses `requests`, Node uses `async/await`, Go handles errors explicitly
- Use consistent variable names and test data across every language for the same endpoint
- Keep examples minimal -- show only what is necessary for the concept, then offer a collapsible "full example" section for production-ready code with error handling

**Structure the docs hierarchy clearly:**
- Quickstart (first API call in under 5 minutes)
- Task-oriented guides ("Send an SMS", "Create a Charge")
- API Reference (every endpoint, every parameter)
- SDKs and Libraries
- Webhooks
- Testing
- Changelog and Migration Guides

## Interactive "Try It" Explorers

Embed interactive API explorers directly in the documentation so developers can make real or simulated calls without leaving the page. Swagger UI and Redoc both support "Try It" panels that can be pre-populated with sandbox credentials.

**Best practices:**
- Pre-populate test credentials automatically -- never force developers to hunt for API keys before trying an endpoint
- Always show the equivalent cURL command alongside any GUI explorer so developers build transferable knowledge
- Persist state across requests: if a developer creates a resource in one call, auto-populate its ID in subsequent calls
- Show both request and response headers, not just bodies -- developers debugging auth or content-type issues need headers
- Provide a standalone CLI tool (following the Stripe CLI pattern) for developers who prefer terminal-native workflows

**Tier your explorers:** embedded Try-It in docs is the minimum, a standalone Postman workspace or custom console is better, and a guided interactive tutorial that walks through multi-step flows is best.

## Sandbox Environments

Every API that handles real data or real money must provide a sandbox. Use the "separate keys" pattern -- test keys (`sk_test_...`) hit the same API but a separate test database. This is lowest-friction because developers do not need to change base URLs or configure separate environments.

**Sandbox rules:**
- Sandbox must behave identically to production: same endpoints, same validation rules, same rate limits, same error formats
- Provide magic test values for every error scenario developers need to handle (card declined, insufficient funds, network timeout)
- Document every magic value with the exact scenario it triggers
- Make sandbox data ephemeral -- auto-delete after 30 days or provide a "reset sandbox" button
- Include simulated institutions or test accounts with pre-configured scenarios for complex flows (following Plaid's model with test credentials like `user_good / pass_good`)

## Onboarding Checklist

Design the onboarding path so a developer can go from signup to receiving their first webhook in under 10 minutes:

1. **Sign up** -- email and password only, no credit card
2. **Get API key** -- visible on the dashboard immediately, no email verification for sandbox
3. **Make first call** -- copy-paste a pre-filled cURL command from docs
4. **Install SDK** -- one-line install command for their language
5. **Create a resource** -- guided example that creates something real in the sandbox
6. **Receive a webhook** -- set up a local listener (provide a CLI tool or ngrok instructions), trigger a test event, see the payload arrive

Track TTFAC as a product metric. Measure it in user testing. Optimize it quarterly. Every friction point you remove from onboarding directly increases adoption.

## Error Messages as Documentation

Every error response is an opportunity to teach. Include a `doc_url` field in every error that links directly to a help page explaining the error, its common causes, and resolution steps.

**The anatomy of a great API error:**
- `type` -- machine-readable error category (e.g., `invalid_request_error`)
- `code` -- specific error code (e.g., `amount_too_small`)
- `message` -- human-readable explanation that says what went wrong and what to do about it
- `param` -- the request parameter that caused the error
- `doc_url` -- a link to the documentation page for this specific error
- `suggestion` -- optional actionable fix (e.g., "Set amount to at least 50 for USD")

**Rules for error messages:**
- Say what went wrong: "The 'email' field is not a valid email address", not "Invalid request"
- Include the problematic value: "'uds' is not a valid currency. Did you mean 'usd'?"
- Include the field name in every validation error
- Use consistent HTTP status codes everywhere: 400 for malformed requests, 401 for missing auth, 403 for insufficient permissions, 404 for missing resources, 422 for business rule violations, 429 for rate limits

## SDK Generation Strategy

Choose between auto-generated SDKs, hand-crafted SDKs, or the recommended hybrid approach.

**Auto-generated** (openapi-generator, Stainless, Fern, Speakeasy) is fast and consistent but produces unidiomatic, hard-to-use code. **Hand-crafted** (Stripe, Twilio) feels native to each language but costs an entire team per language. **Hybrid** is the sweet spot: generate a base client from the OpenAPI spec, then layer hand-crafted ergonomic wrappers on top.

**The hybrid workflow:**
1. Generate a base client from the OpenAPI spec
2. Add ergonomic wrappers: custom method names, builder patterns, convenience methods
3. Generate tests from the spec to validate the hand-crafted layer
4. Hand-write quickstart and conceptual documentation, auto-generate reference docs

The difference matters: `client.apis.default_api.create_payment_intent_api_v1_payment_intents_post(...)` versus `stripe.PaymentIntent.create(amount=2000, currency="usd")`. Developers judge your entire platform by how your SDK feels.

## Changelog and Breaking Change Communication

Maintain a date-stamped changelog with categorization: Added, Changed, Deprecated, Removed, Fixed. Note the API version on every entry. Provide an RSS/Atom feed so developers can subscribe. Show dashboard banners when a developer's pinned API version approaches end-of-life.

**Migration guide formula:**
1. What changed (one sentence)
2. Why it changed (context reduces frustration)
3. What to do (step-by-step code diff showing old versus new)
4. Deadline (when the old behavior is removed)
5. Testing instructions (how to verify the migration worked)

**Deprecation lifecycle:** Announce with `Sunset` header and docs notice, then soft-deprecate for 6 months with SDK warnings and monthly emails, then hard-deprecate with aggressive rate limits and dashboard countdowns, then remove after 12+ months by returning 410 Gone with migration instructions in the response body.

## API Design Review Process

Adopt design-first for public APIs: write the OpenAPI specification before writing any code. The spec is the contract. Frontend and backend teams can work in parallel (frontend builds against a Prism mock server), and the design review catches naming issues, missing fields, and inconsistencies before any code is written.

**The design-first workflow:**
1. Product requirements
2. Write OpenAPI spec
3. Lint the spec with Spectral (enforce snake_case, required descriptions, required examples)
4. Design review by 1-2 API-experienced engineers
5. Generate mock server with Prism for frontend development
6. Backend implements against the spec
7. Contract tests verify implementation matches spec
8. Deploy

Establish a formal review checklist: resources are nouns, collections are plural, all fields use snake_case, boolean fields use `is_` or `has_` prefix, timestamps use `_at` suffix, every list endpoint supports pagination, every error scenario is documented.

## Contract Testing

Contract tests verify that the running API matches the OpenAPI specification. Run them in CI on every pull request.

**Schemathesis** generates test cases from the spec and throws them at the API -- it checks that response schemas match, status codes are correct, and edge cases (empty strings, huge numbers, special characters) do not crash the server. **Dredd** tests every endpoint in the spec against a running server and reports which responses violate the contract.

**Integrate both into CI:**
1. Lint the OpenAPI spec with Redocly CLI
2. Check for breaking changes with Optic (compare spec against the main branch)
3. Start the API server
4. Run Schemathesis with `--checks all` for fuzz testing
5. Run Dredd for strict compliance testing

Contract tests should verify: response schemas match the spec, required fields are always present, status codes match the spec, error responses conform to the error schema, pagination `has_more` is accurate, and Content-Type headers are correct.

## Review Checklist

When building or reviewing API documentation and developer experience:

- [ ] Three-panel layout with persistent language selection across the docs site
- [ ] Time to first API call is under 5 minutes (measured, not estimated)
- [ ] Code examples provided in cURL, Python, and Node.js at minimum, all complete and runnable
- [ ] Interactive "Try It" explorer embedded in docs with pre-filled sandbox credentials
- [ ] Sandbox environment behaves identically to production with documented magic test values
- [ ] Onboarding flow covers signup through first webhook in under 10 minutes
- [ ] Every error response includes `type`, `code`, `message`, `param`, and `doc_url`
- [ ] SDKs generated from OpenAPI spec with hand-crafted ergonomic wrappers
- [ ] Changelog is date-stamped, categorized, and available via RSS feed
- [ ] OpenAPI spec is linted in CI with Spectral and checked for breaking changes with Optic
- [ ] Contract tests (Schemathesis and/or Dredd) run on every pull request
- [ ] API design review happens before implementation, not after
