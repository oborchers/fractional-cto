---
name: versioning-and-evolution
description: "Use when designing API versioning strategy with URL path or header-based approaches, implementing Stripe-style date-based version pinning with per-request overrides, adding new fields or endpoints without breaking existing clients, classifying changes as breaking vs non-breaking, planning API deprecation timelines with RFC 8594 Sunset headers, writing migration guides with before and after code diffs, configuring version response headers like X-API-Version, implementing brownout periods before hard sunset dates, or reviewing PRs for backward compatibility violations like field removal or type changes. Covers URL path versioning as default, additive-only evolution rules, breaking change classification, Stripe version gate architecture, four-phase deprecation lifecycle, and consumer migration guide format."
version: 1.0.0
---

# API Versioning and Evolution

The API version is a contract. Backward compatibility is non-negotiable within a major version. Breaking changes require version bumps with documented migration paths.

## Versioning Strategy Selection

| Strategy | Mechanism | Best For |
|----------|-----------|----------|
| **URL path** (default) | `/v1/resources` | Most APIs — explicit, cacheable, easy to route |
| **Custom header** | `Stripe-Version: 2024-11-20` | Fine-grained control within a major version |
| **Query parameter** | `?api-version=2022-12-01` | Easy to add but pollutes query string |
| **Date-based (Stripe)** | Account pinned to signup date, per-request override | High-consumer APIs that ship frequent changes |

**Default to URL path versioning.** Prefix every endpoint with `/v1/`. Do not increment to `/v2/` unless fundamentally restructuring the entire API surface. Route at the load balancer — different prefixes can point to different deployments.

## Additive Evolution Rules

Within a major version, only additive, backward-compatible changes are permitted.

**Non-breaking (always safe):**
- Add optional response fields, query parameters, or request body fields
- Add new endpoints
- Add enum values (if docs instruct clients to handle unknowns)
- Increase rate limits or relax validation

**Breaking (requires version bump):**
- Remove or rename response fields
- Change field types (string→number, object→array)
- Remove endpoints or make optional params required
- Tighten validation, change error formats, reduce rate limits

**Quick reference:**

| Change | Breaking? | Reason |
|--------|-----------|--------|
| Add `metadata` to response | No | Clients ignore unknown fields |
| Remove `receipt_url` | **Yes** | Clients relying on it break |
| Rename `source` → `payment_method` | **Yes** | Old field access fails |
| Change `amount` int → string | **Yes** | Parsers break |
| Add optional `?expand[]` | No | Existing requests unaffected |
| Make `email` required | **Yes** | Existing creates without email fail |
| Add `paused` enum value | No | Only if clients handle unknowns |

## Stripe Date-Based Versioning

For high-consumer APIs needing granular migration:

1. **Account pinning** — default to version at signup
2. **Per-request override** — `Stripe-Version: 2024-11-20.acacia` for testing
3. **Forward-only upgrade** — no downgrades after pinning
4. **Webhook version consistency** — payload version matches endpoint config, not triggering request
5. **Version gates** — single API server transforms responses through compatibility layers per version

**When to adopt:** Many consumers, frequent changes, zero-breakage requirement. For smaller APIs, URL path + additive evolution is sufficient.

## Deprecation Lifecycle

**Always return deprecation headers on deprecated endpoints:**

```http
HTTP/1.1 200 OK
Sunset: Sat, 01 Jun 2026 00:00:00 GMT
Deprecation: true
Link: <https://api.example.com/docs/migration-v2>; rel="successor-version"
X-API-Version: 2024-01-15
```

**Four-phase timeline:**

| Phase | Timing | Actions |
|-------|--------|---------|
| Announce | 6–12 months before | Email all API key owners, dashboard warning, changelog entry, migration guide |
| Warn | 3–6 months before | `Sunset` + `Deprecation` headers, per-key usage tracking, follow-up emails |
| Brownout | 1–2 months before | Periodic downtime (e.g., 1hr every Tuesday), alert remaining users |
| Sunset | Removal day | Return `410 Gone` with migration guide URL (not `404`) |

**Post-sunset response:**

```json
{
  "error": {
    "type": "api_version_error",
    "message": "API version 2022-03-01 has been sunset. Upgrade to 2024-01-15 or later.",
    "doc_url": "https://docs.example.com/api/migration/2024-01-15"
  }
}
```

**Communication channels:** Headers alone are insufficient. Use changelog, direct email to affected API key owners, dashboard banners, SDK deprecation warnings, and visual markers in docs.

## Version Response Headers

Always return the applied API version in responses:

```http
X-API-Version: 2024-11-20
```

Echo the version actually applied (whether from header, account default, or API-key default). Critical for debugging version-related issues.

## Migration Guide Format

Every version bump requires a migration guide:

1. **What changed** — exact field renames, type changes, removals
2. **Why** — context reduces frustration
3. **Before/after code diff:**
   ```
   Before: charge.receipt_url (always present)
   After:  expand=["receipt_url"] to include (omitted by default)
   ```
4. **Deadline** — sunset date
5. **Testing instructions** — per-request header override or sandbox

Link migration guides from every deprecation header, error message, and dashboard warning.

## Review Checklist

- [ ] URL path includes major version prefix (`/v1/`) stable for years
- [ ] All changes within major version are additive and backward-compatible
- [ ] Breaking changes documented in versioned changelog with before/after examples
- [ ] Response headers include `X-API-Version` with applied version
- [ ] Deprecated endpoints return `Sunset` and `Deprecation` headers
- [ ] Deprecation communicated via email, dashboard, changelog, and docs — not headers alone
- [ ] Migration guides exist for every version transition with code diffs and timelines
- [ ] Sunset endpoints return `410 Gone` with migration URL, not `404`
- [ ] Consumers can test new versions per-request before committing
- [ ] No fields removed or renamed without version bump
- [ ] Docs instruct clients to handle unknown enum values gracefully
- [ ] Brownout periods scheduled before hard sunset dates
