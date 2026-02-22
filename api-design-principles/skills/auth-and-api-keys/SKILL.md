---
name: auth-and-api-keys
description: "This skill should be used when the user is designing API authentication, implementing API keys with prefixes, choosing between API keys and OAuth, setting up JWT tokens, implementing Bearer token authentication, designing API key rotation, or scoping API key permissions. Covers Stripe-style prefixed keys (sk_live_, pk_test_), OAuth 2.0 flows, JWT patterns, and key management."
version: 1.0.0
---

# Authentication Should Be Invisible Until It Isn't

Authentication is the first impression your API makes. Before a developer can create a resource, list a record, or trigger a webhook, they must authenticate. If this step is confusing, insecure, or poorly designed, nothing else matters. A leaked key with no prefix is invisible until it causes a production incident. A missing 401/403 distinction wastes hours of debugging. A rotation flow that requires downtime erodes trust.

Design authentication so developers never think about it -- until the moment they need to rotate a key, scope a permission, or integrate a third-party OAuth flow. Then make that moment effortless.

## API Key Design: Prefixes Are Non-Negotiable

Every API key must carry a prefix that encodes its type, environment, and provider. Prefixes enable automated secret scanning (GitHub secret scanning, GitGuardian), make wrong-key errors self-diagnosable, and prevent accidental production usage.

Use this format: `{type}_{environment}_{random_entropy}`

- `sk_live_` -- secret key, production
- `sk_test_` -- secret key, test/sandbox
- `pk_live_` -- publishable key, production (safe for client-side)
- `pk_test_` -- publishable key, test/sandbox
- `rk_live_` -- restricted key, production (scoped permissions)

Never issue opaque hex strings like `a1b2c3d4e5f6...`. They cannot be identified by scanners, cannot be distinguished by environment, and force developers to contact support for basic misuse diagnosis.

### Industry Prefix Reference

| Provider | Prefix | Purpose |
|----------|--------|---------|
| Stripe | `sk_live_`, `sk_test_` | Secret keys by environment |
| Stripe | `pk_live_`, `pk_test_` | Publishable keys by environment |
| Stripe | `rk_live_`, `whsec_` | Restricted keys, webhook secrets |
| GitHub | `ghp_`, `ghs_`, `gho_` | Personal, app, and OAuth tokens |
| GitHub | `github_pat_` | Fine-grained personal access token |
| Twilio | `SK` | API key SID |
| Slack | `xoxb-`, `xoxp-` | Bot token, user token |
| AWS | `AKIA` | Access key ID |
| Cloudflare | `v1.0-` | API token |

## Key Generation

Generate keys with cryptographically secure randomness. Use at least 32 bytes (256 bits) of entropy. Encode the random portion in Base62 (`a-z`, `A-Z`, `0-9`) or Base58 (excludes ambiguous characters `0`, `O`, `l`, `I`). Total key length should be 40-70 characters including the prefix.

```
Format:  {prefix}_{random_base62(48)}
Example: sk_live_<random_base62_string_here>
```

Never use UUIDs as API keys. UUIDs have only 122 bits of randomness (v4), are predictable in structure, and do not carry semantic prefixes.

## Key Storage: Hash Everything

Store only a SHA-256 hash of the key server-side. Show the full key exactly once at creation time. Store the prefix and last four characters separately for dashboard display.

```
Creation:
  raw_key   = "sk_live_" + secure_random_base62(48)
  key_hash  = SHA-256(raw_key)
  prefix    = raw_key[:12]       # "sk_live_4eC3" for dashboard display
  last_four = raw_key[-4:]       # for identification

Database record:
  { id, hash, prefix, last_four, scopes, created_at, last_used_at }

Return to user once:
  { key: raw_key }
```

This pattern (used by Stripe, GitHub, and others) means a compromised database does not expose raw API keys. Never log raw keys. Never include them in error messages. Never return them in GET responses after creation.

## Key Scoping: Least Privilege by Default

Restricted keys limit what operations a key can perform. Use resource-level permissions with three tiers: `none`, `read`, `write`.

```json
{
  "id": "rk_live_abc123",
  "permissions": {
    "charges": "write",
    "customers": "read",
    "transfers": "none",
    "balance": "read",
    "webhooks": "none"
  }
}
```

A reporting service needs only `read` on charges and balance. A payment processor needs `write` on charges but nothing on customer deletion. Always create keys with the minimum permissions required. Broad keys are a liability.

GitHub takes scoping further by combining permission scoping with repository-level access, so a CI/CD token for one repo cannot touch another.

## Key Rotation: Zero-Downtime Always

Allow multiple active keys simultaneously. Never force developers into a rotation flow that requires downtime.

**Rotation flow:**
1. Create new key (old key still works)
2. Update application configuration with new key
3. Deploy application
4. Verify new key is working (check `last_used_at` in dashboard)
5. Revoke old key

Support programmatic key creation and revocation via the API itself. Add mandatory or optional expiration dates. Send webhook notifications or emails before keys expire. Track `last_used_at` for every key so developers can identify which keys are still active before revoking.

## OAuth 2.0: For Delegated Access

Use OAuth 2.0 when a third-party application needs to act on behalf of a user. Do not use OAuth for simple server-to-server authentication where API keys suffice.

| Flow | Use Case | Client Type |
|------|----------|-------------|
| Authorization Code + PKCE | Web apps, mobile, SPAs | Public or confidential |
| Client Credentials | Machine-to-machine, services | Confidential (server) |
| Device Authorization | CLIs, TVs, IoT | Public (no browser) |

Always use PKCE (Proof Key for Code Exchange) with the Authorization Code flow, even for confidential clients. The Implicit flow and Resource Owner Password flow are deprecated -- do not implement them.

Include the `state` parameter for CSRF protection. Validate `redirect_uri` against a pre-registered allowlist. Return scopes granted in the token response (they may differ from scopes requested).

## JWT: Short-Lived and Minimal

Use JWTs for short-lived access tokens in microservice architectures where stateless validation avoids per-request database lookups. Do not use JWTs as long-lived session tokens or as a replacement for API keys.

**Structure:**
```
Header:  { "alg": "RS256", "typ": "JWT", "kid": "key-2025-01" }
Payload: { "iss", "sub", "aud", "exp", "iat", "jti", "scope" }
```

**Rules:**
- Keep TTL short: 15 minutes to 1 hour maximum
- Use RS256 (asymmetric) over HS256 (symmetric) -- allows verification without sharing the signing secret
- Always validate `aud` (audience) to prevent cross-service token confusion
- Always validate `alg` server-side and reject `none`
- Keep payloads minimal -- do not stuff user profile data into claims
- Include `jti` (JWT ID) if you need revocation tracking
- Pair with refresh tokens for longer sessions: the refresh token is opaque, stored server-side, and rotated on each use

**Refresh token rotation:** Each time a refresh token is used, invalidate it and issue a new one. If a revoked refresh token is reused (indicating theft), revoke all tokens for that session.

## Decision Framework: API Keys vs OAuth vs JWT

| Scenario | Use |
|----------|-----|
| Developer authenticating their own server | API key |
| Third-party app acting on behalf of a user | OAuth 2.0 (Authorization Code + PKCE) |
| Service-to-service in microservice architecture | OAuth 2.0 (Client Credentials) or mTLS |
| CLI authenticating a developer | OAuth 2.0 (Device Authorization) |
| Stateless identity propagation between services | JWT (short-lived) |
| Browser-to-API with user context | OAuth 2.0 access token (opaque or JWT) |
| Webhook signature verification | HMAC-SHA256 with shared secret |

Do not combine approaches without clear boundaries. If your API uses API keys for external developers and JWTs for internal microservice auth, document which is which and never mix them in the same flow.

## 401 vs 403: Get This Right

This is the most commonly confused HTTP status distinction in API design.

- **401 Unauthorized** -- authentication failed or missing. The server does not know who you are. Include `WWW-Authenticate` header. Response: "No API key provided" or "Invalid API key" or "Token expired."
- **403 Forbidden** -- authenticated but not authorized. The server knows who you are but you lack permission. Response: "Your API key does not have permission to delete users. Required: `users:delete`."

Include the required permission in 403 responses so developers can self-diagnose. Never return 401 for everything -- the distinction between "who are you?" and "you cannot do that" is essential for debugging.

For sensitive resources where existence should be hidden, return 404 instead of 403 to prevent enumeration (GitHub does this for private repositories).

## Examples

Working implementations in `examples/`:
- **`examples/prefixed-api-key-system.md`** -- Complete API key generation with prefixes, SHA-256 hashing, validation, and prefix-based environment routing in Node.js and Python
- **`examples/bearer-token-middleware.md`** -- Authentication middleware that validates Bearer tokens (API keys or JWT), returns proper 401/403 errors, and attaches auth context in Node.js/Express and Python/FastAPI

## Review Checklist

When designing or reviewing API authentication:

- [ ] API keys use descriptive prefixes encoding type and environment (`sk_live_`, `pk_test_`)
- [ ] Keys are generated with cryptographically secure randomness (32+ bytes entropy)
- [ ] Only SHA-256 hashes of keys are stored server-side; raw keys are shown once at creation
- [ ] Keys are never logged, never in URLs, never returned after initial creation
- [ ] Restricted/scoped keys are available with per-resource `none`/`read`/`write` permissions
- [ ] Key rotation supports multiple active keys for zero-downtime migration
- [ ] OAuth 2.0 with PKCE is used for third-party delegated access (not API keys)
- [ ] JWTs are short-lived (15 min - 1 hr) and paired with rotating refresh tokens
- [ ] JWT validation checks `alg`, `aud`, `exp`, and rejects `alg: none`
- [ ] 401 is returned for missing/invalid credentials; 403 for insufficient permissions
- [ ] 403 responses include the required permission for self-diagnosis
- [ ] HTTPS is enforced on all endpoints; keys are only transmitted over TLS
