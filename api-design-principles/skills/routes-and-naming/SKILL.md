---
name: routes-and-naming
description: "This skill should be used when the user is designing API routes, URL structures, endpoint naming, resource naming conventions, query parameters vs path parameters, JSON field naming (snake_case vs camelCase), nesting depth, or API URL patterns. Covers plural nouns, flat vs hierarchical URLs, field naming conventions, and real-world patterns from Stripe, GitHub, Twilio, and Google."
version: 1.0.0
---

# URLs Are Your API's User Interface

A URL is the first thing every developer sees when integrating an API. Stripe, GitHub, Twilio, and Shopify all converge on the same core patterns: plural nouns, shallow nesting, snake_case fields, and zero verbs in paths. These are not style preferences — they are battle-tested conventions from APIs handling billions of calls daily. Deviation from them forces every consumer to learn your exceptions instead of relying on muscle memory.

## Resource Naming: Plural Nouns, No Verbs

The HTTP method is the verb. The URL names the resource. Always use plural nouns for collections.

| Operation | URL | Method |
|-----------|-----|--------|
| List all users | `GET /users` | GET |
| Create a user | `POST /users` | POST |
| Get one user | `GET /users/{id}` | GET |
| Update a user | `PATCH /users/{id}` | PATCH |
| Delete a user | `DELETE /users/{id}` | DELETE |

**Rules:**
- Use plural nouns for every collection: `/users`, `/orders`, `/products`
- Use singular only for true singletons: `/users/{id}/profile` (one profile per user), `/health`, `/configuration`
- Never embed verbs in URLs: `POST /orders` not `POST /createOrder`
- Never embed operations: `DELETE /users/123` not `GET /deleteUser?id=123`

**Good:**
```
GET  /orders              # collection of orders
GET  /orders/789          # single order
GET  /users/42/profile    # singleton sub-resource
POST /v1/customers        # Stripe pattern
```

**Bad:**
```
GET  /order               # singular collection name — ambiguous
GET  /getUsers            # verb in URL
POST /createOrder         # verb in URL; HTTP method already says "create"
GET  /getUserById/42      # verb + redundant description
```

Real-world evidence: Stripe uses `GET /v1/customers`, GitHub uses `GET /repos/{owner}/{repo}/issues`, Twilio uses `GET /Accounts/{sid}/Messages`, Shopify uses `GET /admin/api/2026-01/products.json`. All plural nouns.

## Nesting Depth: Maximum 2 Levels

Limit URL hierarchy to `/{resource}/{id}/{sub-resource}`. Never exceed `/{resource}/{id}/{sub-resource}/{id}` in production routes.

**Why:**
1. **Readability** — deep URLs are hard to read, type, and debug in logs
2. **Coupling** — deep nesting binds clients to the server's data model; hierarchy changes break all client URLs
3. **Cacheability** — each nesting level multiplies unique cache keys and reduces hit rates
4. **Authorization** — each level requires a parent lookup and ownership check
5. **Client burden** — clients need all parent IDs even when they already have the child's globally unique ID

**Good (1-2 levels):**
```
GET /users/123/orders                    # orders belonging to user 123
GET /repos/octocat/Hello-World/issues    # issues in a specific repo
POST /v1/customers/cus_xxx/sources       # add payment source to customer
```

**Bad (too deep):**
```
GET /orgs/1/departments/2/teams/5/members/42/tasks
# 5 levels deep — unreadable, hard to cache, brittle
```

**Escape hatch — flatten deep resources:**
```
# Instead of:
GET /organizations/{org}/teams/{team}/projects/{project}/tasks/{task}

# Provide:
GET /tasks/{task_id}                          # direct access
GET /projects/{project_id}/tasks              # scoped list
GET /tasks?project_id=X&team_id=Y             # filtered list
```

Stripe keeps resources flat — charges have globally unique IDs, so `GET /v1/charges/ch_xxx` works without nesting under customers. GitHub nests because repo slugs are not globally unique — `octocat/Hello-World` requires owner context. Nest when child IDs are scoped to the parent; flatten when IDs are globally unique.

## Path Parameters vs Query Parameters

| Aspect | Path Parameter | Query Parameter |
|--------|---------------|-----------------|
| Purpose | Identify a specific resource | Filter, sort, or modify representation |
| Required? | Always | Usually optional |
| Example | `/users/42` | `/users?role=admin` |

**Decision rule (Microsoft REST API Guidelines):** If removing the parameter changes *which* resource the URL points to, it is a path parameter. If removing it changes *how* the resource is returned, it is a query parameter.

**Good:**
```
GET /users/42                         # path param: identifies the resource
GET /users?role=admin&status=active   # query params: filter the collection
GET /users/42/orders?status=pending   # mix: path identifies user, query filters orders
```

**Bad:**
```
GET /users?id=42          # ID identifies a resource — belongs in the path
GET /users/role/admin     # role is a filter, not a resource identifier
GET /getActiveAdminUsers  # filters embedded as a verb
```

**Filtering, sorting, and searching — always use query parameters:**
```
GET /articles?author=jane&sort=-published_at&limit=20&offset=0
GET /products?q=laptop&price_min=500&category=electronics
GET /v1/charges?created[gte]=1609459200&limit=100    # Stripe bracket notation
```

Use the `-` prefix for descending sort (JSON:API convention): `?sort=-created_at`. Use `q` or `search` for full-text search. Never encode filters, sort, or pagination as path segments.

## Case Conventions: Pick One, Apply Everywhere

The most common convention (Stripe, GitHub, Heroku, Zalando):

| Domain | Convention | Example |
|--------|-----------|---------|
| URL path segments | kebab-case | `/user-profiles`, `/payment-methods` |
| Query parameters | snake_case | `?sort_by=name`, `?is_active=true` |
| JSON request/response fields | snake_case | `"created_at"`, `"first_name"` |
| HTTP headers | Train-Case | `Content-Type`, `X-Request-Id` |

**Critical rule: never mix conventions within the same domain.** Having `createdAt` and `updated_at` in the same response body is a major inconsistency.

**Good:**
```
GET /user-accounts/{id}/payment-methods?is_default=true

Response:
{
  "id": "pm_123",
  "card_brand": "visa",
  "last_four": "4242",
  "is_default": true,
  "created_at": "2024-01-15T10:30:00Z"
}
```

**Bad:**
```
GET /userAccounts/{id}/Payment_methods?isDefault=true

Response:
{
  "ID": "pm_123",
  "cardBrand": "visa",
  "last_four": "4242",
  "IsDefault": true,
  "created": "Jan 15 2024"
}
```

## Boolean Field Naming

Always prefix booleans so they read as yes/no questions. Never use bare adjectives or nouns.

| Prefix | Usage | Examples |
|--------|-------|----------|
| `is_` | Current state | `is_active`, `is_verified`, `is_published` |
| `has_` | Possession/capability | `has_password`, `has_two_factor`, `has_children` |
| `can_` | Ability/permission | `can_edit`, `can_delete`, `can_invite` |
| `should_` | Preference/setting | `should_notify`, `should_auto_renew` |
| `allow_` | Permission setting | `allow_comments`, `allow_signups` |

**Rules:**
- Always use a prefix — `active`, `published`, `admin` are ambiguous (boolean? string? sub-object?)
- Never use negative names — `is_not_active` or `is_disabled` produce double negatives when checked with `!`
- Use `is_active: false` instead of `is_disabled: true`

GitHub follows this convention: `has_issues`, `has_projects`, `is_template` in repository responses.

## Date/Time Field Naming

Use `_at` for timestamps, `_on` or `_date` for date-only values, and always ISO 8601 format.

| Field | Meaning |
|-------|---------|
| `created_at` | When the resource was created |
| `updated_at` | When the resource was last modified |
| `deleted_at` | When the resource was soft-deleted (null if not deleted) |
| `published_at` | When the resource was published |
| `expires_at` | When the resource expires |
| `due_date` | Date-only value (no time component) |

**Rules:**
- Always use ISO 8601 with UTC timezone: `"2024-01-15T10:30:00Z"`
- Never use locale-specific formats: `"01/15/2024"` or `"Jan 15 2024"` are ambiguous
- Suffix consistency: pick `_at` for all timestamps and use it everywhere

**Good:**
```json
{
  "created_at": "2024-01-15T10:30:00Z",
  "updated_at": "2024-06-20T14:22:33Z",
  "trial_ends_at": "2024-02-15T00:00:00Z",
  "due_date": "2024-07-01"
}
```

**Bad:**
```json
{
  "creation_date": "Jan 15, 2024",
  "modified": "2024-06-20",
  "trialEnd": 1705276800,
  "last_login": "06/19/2024 8:15 AM EST"
}
```

## Enum Naming Conventions

Use lowercase snake_case strings for enum values. Never use integers, abbreviations, or mixed case.

**Rules:**
- Descriptive values, not codes: `"payment_failed"` not `"PF"` or `3`
- Past tense for completed states: `"cancelled"`, `"completed"`, `"failed"` not `"cancel"`, `"complete"`, `"fail"`
- Document all possible values in the schema — enum values are part of the API contract

**Good:**
```json
{
  "status": "payment_failed",
  "priority": "high",
  "order_type": "subscription",
  "shipping_method": "express_delivery"
}
```

**Bad:**
```json
{
  "status": 3,
  "priority": "HIGH",
  "order_type": "Subscription",
  "shipping_method": "exp-dlvry"
}
```

Stripe uses `"succeeded"`, `"requires_payment_method"`, `"cancelled"` — all lowercase, readable, past tense for final states. GitHub uses `"open"`, `"closed"`. Follow this convention.

## Abbreviation Rules

Do not abbreviate. Spell out words fully. The bandwidth saved by shorter names is negligible; the confusion caused by ambiguous abbreviations is not.

**Allowed exceptions** — universally understood abbreviations: `id`, `url`, `api`, `http`, `html`, `css`, `ip`, `os`, `cpu`, `oauth`.

**Good:**
```json
{
  "id": "usr_123",
  "email": "oliver@example.com",
  "organization_id": "org_456",
  "api_key": "sk_live_abc",
  "ip_address": "192.168.1.1"
}
```

**Bad:**
```json
{
  "usr_id": "123",
  "eml": "oliver@example.com",
  "org_mgr_ref_id": "456",
  "auth_tkn": "abc",
  "ip_addr": "192.168.1.1"
}
```

## Consistent Terminology

Choose one term for each domain concept and use it everywhere. Mixing synonyms for the same entity is one of the most damaging API design mistakes.

| Concept | Pick ONE | Do not mix with |
|---------|----------|-----------------|
| The person using the app | `user` | `account`, `member`, `person`, `customer` |
| Removing something | `delete` | `remove`, `destroy`, `purge`, `erase` |
| Creating something | `create` | `add`, `new`, `insert`, `register` |
| A record identifier | `id` | `identifier`, `key`, `uid`, `code` |
| A creation timestamp | `created_at` | `creation_date`, `date_created`, `timestamp` |

Exception: genuinely different domain concepts (Stripe's `user` vs `customer`) may use different terms, but the distinction must be intentional and documented.

## Action Endpoints for Non-CRUD Operations

Not every operation maps to CRUD. Use `POST /resource/{id}/verb` for actions with side effects.

**Good:**
```
POST /orders/789/cancel               # clear intent, discoverable
POST /accounts/42/verify              # action that triggers side effects
POST /users/123/deactivate            # lifecycle transition
```

**Bad:**
```
GET  /cancelOrder/789                 # GET for a state change, verb as resource
POST /api/doCancel?orderId=789        # RPC-style, not resource-oriented
```

This pattern is used by Stripe (`POST /v1/charges/{id}/refund`), GitHub (`PUT /repos/{owner}/{repo}/pulls/{number}/merge`), and Google Cloud (`POST /projects/{id}:undelete`).

## Examples

Working implementations in `examples/`:
- **`examples/url-structure-patterns.md`** — Good/bad URL examples for CRUD, nested resources, and filtering, with Node.js/Express and Python/FastAPI route definitions
- **`examples/field-naming-conventions.md`** — JSON response examples showing snake_case naming, boolean prefixes, date suffixes, and enum values, with Node.js and Python model/schema examples

## Review Checklist

When designing or reviewing API routes and naming:

- [ ] Resource names are plural nouns (unless true singletons)
- [ ] No verbs in URL paths (except action endpoints like `/cancel`)
- [ ] Nesting depth is 2 levels or fewer
- [ ] Path parameters identify resources; query parameters filter or modify
- [ ] URL path segments use kebab-case for multi-word names
- [ ] JSON fields and query parameters use snake_case consistently
- [ ] Boolean fields have `is_`, `has_`, `can_`, `should_`, or `allow_` prefix
- [ ] Timestamps use `_at` suffix and ISO 8601 format with UTC
- [ ] Enum values are lowercase snake_case strings, not integers
- [ ] No custom abbreviations (only universally understood ones like `id`, `url`, `api`)
- [ ] No synonym conflicts — one term per domain concept across all endpoints
- [ ] Filtering, sorting, and pagination use query parameters, not path segments
