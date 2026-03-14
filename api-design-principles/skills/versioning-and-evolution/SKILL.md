---
name: versioning-and-evolution
description: "This skill should be used when the user is designing API versioning strategy, choosing between URL path and header-based versioning, implementing Stripe-style date-based versioning, planning API deprecation, using sunset headers, or evolving an API without breaking clients. Covers URL versioning, additive evolution, backward compatibility, and deprecation communication."
version: 1.0.0
---

# Ship V1 and Never Break It

Your API version is a promise. The moment a consumer writes code against your endpoint, you have entered a contract. Breaking that contract -- renaming a field, removing an endpoint, changing a type -- destroys trust and costs integration partners real engineering time. The best APIs treat backward compatibility as non-negotiable and version changes as a carefully managed migration, not a surprise.

Stripe has kept `/v1/` stable since 2012. Over a decade, zero URL-level version bumps. They ship breaking changes behind dated version headers, and every account stays pinned to the version it was created with. This is the gold standard. Your API should aspire to the same discipline.

## Versioning Strategies

Four strategies exist in production. Each has real tradeoffs.

| Strategy | Mechanism | Pros | Cons | Used By |
|----------|-----------|------|------|---------|
| **URL path** | `/v1/resources` | Explicit, visible, cacheable, trivial to route at the gateway | URL changes break clients on major bumps, encourages big-bang migrations | Stripe, Google, Twilio, Facebook, Spotify |
| **Custom header** | `Stripe-Version: 2024-11-20` or `X-GitHub-Api-Version: 2022-11-28` | Clean URLs, per-request granularity, enables incremental migration | Invisible in URLs, harder to debug and cache, must remember the header | Stripe (secondary), GitHub |
| **Query parameter** | `?api-version=2022-12-01` | Easy to add, visible in logs | Mixes versioning with resource params, easily omitted, pollutes query string | Azure, AWS |
| **Date-based header (Stripe model)** | Account pinned to signup date, override with `Stripe-Version` header | Granular per-request migration, no URL changes, each change documented by date | Requires version gate infrastructure internally | Stripe |

**Default to URL path versioning.** It is the most intuitive, most cacheable, and easiest to route. Every developer understands `/v1/`. Reserve header-based versioning for fine-grained control within a major version, following Stripe's hybrid model.

## URL Path Versioning as the Default

Use a single major version in the URL path and keep it stable for years.

- Prefix every endpoint with `/v1/`. Do not increment to `/v2/` unless you are fundamentally restructuring the entire API surface.
- Route at the load balancer or API gateway -- different URL prefixes can point to different deployments.
- Cache naturally -- `/v1/users` and `/v2/users` are different cache keys with no extra configuration.
- Document the version in every code example so consumers always know what they are targeting.

Stripe has been on `/v1/` since 2012. Google Cloud APIs use `/v1/` and `/v2/` across services. Twilio's legacy API bakes the date `2010-04-01` into every URL path. The takeaway: pick a version prefix and commit to it for the long term.

## Additive Evolution: The Only Safe Default

Within a major version, evolve the API using only additive, backward-compatible changes. This is the single most important rule for API stability.

**Non-breaking changes (always safe):**
- Add new optional fields to response bodies
- Add new optional query parameters or request body fields (compatible with strict request validation — the API accepts fields it knows about and rejects unknown ones; see `rate-limiting-and-security` skill)
- Add new endpoints
- Add new enum values (if clients handle unknown values gracefully)
- Increase rate limits
- Relax validation to accept a wider range of inputs

**Breaking changes (never without a version bump):**
- Remove or rename fields in response bodies
- Change a field's type (string to number, object to array)
- Change response structure or envelope format
- Remove endpoints
- Make optional parameters required
- Tighten validation to reject previously accepted inputs
- Change error response formats
- Change authentication requirements
- Reduce rate limits

| Change | Breaking? | Why |
|--------|-----------|-----|
| Add `metadata` field to response | No | Existing clients ignore unknown fields |
| Remove `receipt_url` from response | **Yes** | Clients relying on it will break |
| Rename `source` to `payment_method` | **Yes** | Field access by old name fails |
| Change `amount` from integer to string | **Yes** | Type coercion breaks parsers |
| Add optional `?expand[]` parameter | No | Existing requests are unaffected |
| Make `email` required on create | **Yes** | Existing create calls without email fail |
| Add new `paused` status enum value | No | Only if clients handle unknown enums |
| Change 200 response to 201 for creation | **Yes** | Clients checking status codes break |

**Treat new enum values as non-breaking only if your documentation instructs consumers to handle unknown values.** Stripe does this explicitly -- their docs state that new enum values may be added at any time and client code should not break on unrecognized values.

## Stripe's Date-Based Versioning Deep Dive

Stripe operates the most sophisticated API versioning system in the industry. Understand it, then decide how much of it your API needs.

**How it works:**

1. **Account pinning.** Every Stripe account is pinned to the API version that was current at signup. All requests from that account default to the pinned version.
2. **Per-request override.** Send `Stripe-Version: 2024-11-20.acacia` to use a specific version for a single request. This enables testing new versions without committing your entire integration.
3. **Forward-only upgrade.** Once you upgrade your account's pinned version via the Dashboard, you cannot downgrade. This prevents version confusion.
4. **Webhook version consistency.** Webhook payloads use the version configured on the webhook endpoint, not the version of the triggering request. Consumers are never surprised by schema changes they did not opt into.
5. **Version gates, not separate codebases.** Stripe runs a single API server. Responses are serialized as the latest version, then transformed through version gates -- runtime compatibility layers that reshape the response for older versions.

From Amber Feng (former Stripe engineering lead): "We have a single API server that handles all versions. We transform the response at the edge based on the requested version. This means we only have to maintain one set of business logic."

**Version changelog entries are specific and actionable:**

```
2024-11-20.acacia
- Removed `charges` field from PaymentIntent (use `latest_charge` instead)
- Changed `customer.discount` from object to array
- Renamed `pending_invoice_item_interval` to `pending_update_interval`
```

Each entry documents what changed, the old behavior, the new behavior, and migration instructions. Date-based versions like `2024-11-20` are more meaningful than `v37` because developers immediately know when the version was released and can correlate it with their integration timeline.

**When to adopt this model:** If your API has many consumers, ships changes frequently, and cannot afford to break anyone, the Stripe model is worth the infrastructure investment. For smaller APIs with fewer consumers, URL path versioning with additive evolution is sufficient.

## The Sunset Header and Deprecation Timeline

When retiring an old API version or endpoint, communicate early, loudly, and through multiple channels. RFC 8594 defines the `Sunset` HTTP header for exactly this purpose.

**Return deprecation headers on every response from a deprecated endpoint:**

```http
HTTP/1.1 200 OK
Sunset: Sat, 01 Jun 2026 00:00:00 GMT
Deprecation: true
Link: <https://api.example.com/docs/migration-v2>; rel="successor-version"
X-API-Version: 2024-01-15
```

**Follow a four-phase deprecation timeline:**

1. **Announce (6-12 months before sunset).** Email all API key owners. Add a dashboard warning. Update documentation. Publish a changelog entry with the sunset date and migration guide.
2. **Warn (3-6 months before sunset).** Add `Sunset` and `Deprecation` response headers to every request hitting deprecated endpoints. Send follow-up emails with migration instructions. Track per-API-key usage of deprecated endpoints to identify who still needs to migrate.
3. **Brownout (1-2 months before sunset).** Schedule periodic downtime of deprecated endpoints -- for example, one hour every Tuesday. Alert remaining users each time. This forces stragglers to migrate before the hard cutoff.
4. **Sunset (removal day).** Return `410 Gone` with a response body that includes the migration guide URL. Do not return `404` -- a `410` explicitly signals that the resource existed but has been permanently removed.

**After sunset, return a helpful 410:**

```json
{
  "error": {
    "type": "api_version_error",
    "message": "API version 2022-03-01 has been sunset. Please upgrade to version 2024-01-15 or later.",
    "doc_url": "https://docs.example.com/api/migration/2024-01-15"
  }
}
```

## Deprecation Communication Channels

Headers alone are not enough. Consumers rarely inspect response headers in production unless something breaks. Use every channel available:

- **Changelog.** Publish deprecation notices in your public API changelog. Date them. Include before/after examples.
- **Email.** Send direct email to every API key owner associated with traffic to deprecated endpoints. Include the sunset date, what changes, and a link to the migration guide.
- **Dashboard warnings.** Surface a persistent banner in the developer dashboard for accounts still using deprecated versions.
- **SDK warnings.** If you ship client libraries, emit deprecation warnings in logs when deprecated endpoints or parameters are used.
- **Documentation.** Mark deprecated endpoints visually (strikethrough, badges, banners) and link to the replacement.

GitHub announces deprecations in their changelog, sends email notifications, provides migration guides, returns `Warning` headers on deprecated endpoints, and uses `410 Gone` after sunset. Stripe goes further -- API versions are effectively never removed, and the dashboard shows which version each account is pinned to with an upgrade guide for each version transition.

## Version in Response Headers

Always return the API version used to process the request in a response header. This eliminates debugging guesswork.

```http
HTTP/1.1 200 OK
X-API-Version: 2024-11-20
X-Request-ID: req_9ofKRcFXZEvl2X
Content-Type: application/json
```

If the consumer sends a version header, echo back the version that was actually applied. If no version was sent, return the default version for that account or API key. This is critical for debugging version-related issues -- support can immediately verify which version a consumer is hitting.

Stripe returns `Stripe-Version` in every response. GitHub returns `X-GitHub-Api-Version`. Make this standard practice.

## Migration Guides for Consumers

Every version bump needs a migration guide. A bare changelog entry is not enough -- consumers need step-by-step instructions.

**A good migration guide includes:**

- **Exact diff of what changed.** Field renames, type changes, removed fields, new required fields.
- **Before and after examples.** Show the old request/response and the new one side by side.
- **Code migration snippets.** If `receipt_url` moved behind `expand[]`, show exactly how to update the API call.
- **Timeline.** When does the old version sunset? How long do consumers have?
- **Testing instructions.** How to test the new version without committing (per-request header override, test mode, sandbox).

**Stripe's migration format is a model to follow:**

```
Before: charge.receipt_url (always present in response)
After:  expand=["receipt_url"] to include (omitted by default)

Before: invoice.finalized_at = 1705996400 (Unix timestamp)
After:  invoice.finalized_at = "2025-01-23T12:00:00Z" (ISO 8601 string)
```

Provide a version comparison endpoint or tool if your API has complex version differences. At minimum, link to the migration guide from every deprecation header, error message, and dashboard warning.

## Review Checklist

When designing or reviewing API versioning and evolution:

- [ ] URL path includes a major version prefix (`/v1/`) that remains stable for years
- [ ] All changes within a major version are additive and backward-compatible
- [ ] Breaking changes are documented in a versioned changelog with before/after examples
- [ ] Response headers include the API version used to process the request (`X-API-Version`)
- [ ] Deprecated endpoints return `Sunset` and `Deprecation` headers with the removal date
- [ ] Deprecation is communicated through email, dashboard, changelog, and documentation -- not headers alone
- [ ] Migration guides exist for every version transition with code snippets and timelines
- [ ] Sunset endpoints return `410 Gone` with a migration guide URL, not `404`
- [ ] Consumers can test new versions per-request before committing (header override or sandbox)
- [ ] No fields have been removed or renamed without a version bump
- [ ] New enum values are treated as non-breaking, and documentation instructs clients to handle unknown values
- [ ] Brownout periods are scheduled before hard sunset dates to surface remaining consumers
