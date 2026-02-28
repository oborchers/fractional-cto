# Parallel Agent Exploration: Auth System Greenfield

## User Prompt

"We're building a new SaaS product. How should we design the authentication and authorization system?"

## Why Subagents

Greenfield, high-stakes (auth failures are security incidents), many valid approaches, touches every part of the system — premature convergence here would be costly. Spawning parallel `brainstorm-explorer` agents.

## Agent Dispatch

Four `brainstorm-explorer` subagents spawned in parallel:

```
brainstorm-explorer #1: First Principles + Assumption Surfacing
  → Strip auth to fundamentals, challenge "obvious" choices

brainstorm-explorer #2: Inversion / Pre-Mortem + Perspective Forcing
  → Failure modes + stakeholder perspectives on auth

brainstorm-explorer #3: Analogy Search + Constraint Manipulation
  → Cross-domain auth patterns + "what if" explorations

brainstorm-explorer #4: MECE Decomposition + Diverge-then-Converge
  → Systematic coverage + 10 distinct approaches
```

---

## brainstorm-explorer #1 Findings: First Principles + Assumption Surfacing

### First Principles

**What does auth actually need to do?**
1. Verify identity: "Is this person who they claim to be?"
2. Authorize actions: "Can this verified person do this specific thing?"
3. Maintain session: "Remember that verification for some time period."
4. Revoke access: "Immediately stop a person's access."

That's it. Everything else is implementation detail.

### Challenged Assumptions

| Assumption | Challenge | Alternative |
|-----------|-----------|-------------|
| "We need to store passwords" | Third-party auth (Google/GitHub SSO) eliminates password storage entirely | Passwordless-first, passwords as fallback |
| "We need JWTs" | JWTs are a specific token format with tradeoffs (can't revoke without extra infra). Opaque tokens + server lookup are simpler | Evaluate whether JWT benefits (stateless) actually matter at your scale |
| "We need roles" | Roles are a coarse-grained abstraction. Early-stage SaaS might need only 2 levels: "member" and "admin" | Start with boolean is_admin, add roles when there's a third access level |
| "Auth needs to be a microservice" | For a new product, auth in the monolith is simpler and eliminates network calls on every request | Keep auth in the monolith until there's a concrete scaling reason to extract |
| "We need OAuth2" | OAuth2 is for delegated authorization between services. For user-facing auth, OIDC (built on OAuth2) or simple session cookies may be all that's needed | Distinguish between "users logging in" (session auth) and "services calling services" (OAuth2/OIDC) |

### Bottom Line
Start simpler than you think. Passwordless (magic links or SSO) + session cookies + boolean is_admin covers most early SaaS needs without JWTs, roles tables, or auth microservices.

---

## brainstorm-explorer #2 Findings: Inversion / Pre-Mortem + Perspective Forcing

### Pre-Mortem: Auth Failed

**Scenario 1: Credential Stuffing**
"Attackers used credential lists from other breaches against our login endpoint. We had no rate limiting, no breach detection, and stored passwords with bcrypt cost factor 4 (too low). 50,000 accounts compromised."

**Prevention:** Rate limiting on login, bcrypt cost 12+, breach password detection (HaveIBeenPwned API), MFA for sensitive actions.

**Scenario 2: Token Theft**
"A stored XSS in the dashboard leaked JWTs from localStorage. JWTs had 24-hour expiry and no revocation mechanism. Attacker had full access for hours."

**Prevention:** HttpOnly cookies (not localStorage), short-lived tokens (15 min), refresh token rotation, token revocation capability.

**Scenario 3: Authorization Bypass**
"A developer added a new API endpoint but forgot to add the authorization check. Any authenticated user could access admin data for 3 weeks before a security audit caught it."

**Prevention:** Default-deny middleware (every route requires explicit authorization), automated tests that verify auth on every endpoint.

### Perspective Forcing

**End User:** "Don't make me create another password. Let me sign in with Google. Don't log me out every hour."

**Operator:** "I need to disable a compromised account instantly. I need to see who logged in, from where, and when. I need MFA enforcement to be configurable."

**Critic:** "Custom auth is the most common source of security vulnerabilities in SaaS products. Why not use a managed auth provider (Auth0, Clerk, Cognito)?"

**Business:** "A security breach in our first year would kill the company. But spending 3 months building custom auth delays launch. What's the fastest path to secure-enough?"

### Bottom Line
The Critic's point is strongest: for a new SaaS product, managed auth (Auth0/Clerk/Cognito) eliminates an entire class of vulnerabilities. Build custom auth only if there's a specific reason the managed providers can't satisfy.

---

## brainstorm-explorer #3 Findings: Analogy Search + Constraint Manipulation

### Cross-Domain Analogies

**Physical security model:** Buildings use layers: perimeter (fence), entrance (badge reader), room (key card), safe (combination). Auth should layer similarly: network (HTTPS), app (session), resource (permissions), sensitive action (MFA step-up).

**Banking model:** Banks distinguish between "identify yourself" (login) and "authorize this transaction" (PIN/OTP for wire transfers). Apply this: login is low-friction, but sensitive actions (delete account, change email, export data) require step-up authentication.

**Airport model:** Security screening happens once (authentication). But boarding requires a specific pass for a specific flight (authorization). And some areas require additional clearance (step-up). The separation is explicit and physically enforced.

### Constraint Manipulation

| Manipulation | Resulting Design |
|-------------|-----------------|
| "No passwords at all" | Magic links only. Simplest possible auth. No password storage, reset flow, or complexity rules. |
| "Auth must work offline" | Pre-issued tokens with local verification. Changes the entire architecture toward signed tokens (JWTs). |
| "Must support 10,000 organizations" | Multi-tenant auth with org-level SSO. Changes design from user-centric to org-centric. |
| "Zero vendor lock-in" | Open standards only (OIDC, SAML). No proprietary SDKs. |
| "A developer must be able to add auth to a new endpoint in 1 line" | Middleware-based, decorator pattern. Auth is a framework feature, not a per-endpoint decision. |

### Bottom Line
The layered security model (authenticate once, authorize per-resource, step-up for sensitive actions) is the most robust pattern. The "one-line developer experience" constraint is critical — auth should be framework-level middleware, not per-endpoint code.

---

## brainstorm-explorer #4 Findings: MECE Decomposition + Diverge-then-Converge

### MECE Decomposition of Auth

**By function:**
1. Identity (who are you?) — Passwords, SSO, magic links, biometrics
2. Session management (remember who you are) — Cookies, tokens, sessions table
3. Authorization (what can you do?) — Roles, permissions, policies
4. Account lifecycle (create, modify, disable, delete) — Registration, profile, offboarding

**By implementation approach:**
1. Build from scratch (full control, maximum risk)
2. Framework libraries (Passport.js, Devise, etc.) — balanced
3. Managed service (Auth0, Clerk) — lowest risk, least flexibility
4. Identity platform (Keycloak self-hosted) — full control with pre-built features

### Diverge (10 approaches)

1. Managed auth provider (Auth0/Clerk) + their authorization
2. Managed auth provider + custom authorization layer
3. Magic links only, no passwords, session cookies
4. SSO-only (Google/GitHub), no email/password at all
5. Framework auth library (Passport.js/Devise) + RBAC table
6. Custom JWT-based with refresh tokens
7. Custom session-cookie based with server-side sessions
8. Keycloak self-hosted for full identity platform
9. API gateway auth (Cloudflare Access / AWS ALB auth)
10. Passwordless + passkeys (WebAuthn) as primary

### Converge (criteria: time-to-market, security, flexibility, cost)

| Approach | Time | Security | Flexibility | Cost |
|----------|------|----------|-------------|------|
| 1. Managed + managed authz | Fast | High | Low | $$ |
| 2. Managed + custom authz | Fast | High | Medium | $$ |
| 3. Magic links + cookies | Fast | High | Medium | $ |
| 5. Framework lib + RBAC | Medium | Medium | High | $ |

### Bottom Line
Approach 2 (managed identity + custom authorization) or Approach 3 (magic links + custom) score highest. Managed identity handles the security-critical part (passwords, MFA, breach detection) while custom authorization handles the business-specific part (what can this user do in THIS product).

---

## Synthesis

### All agents agree on:
- **Do not build custom password handling.** Use managed auth or passwordless.
- **Separate authentication from authorization.** Different concerns, different change rates.
- **Default-deny.** Every endpoint requires explicit authorization. Middleware-level enforcement, not per-endpoint.
- **Layered security.** Authenticate once, authorize per-resource, step-up for sensitive actions.

### Genuine disagreement:
- **Managed auth vs. magic links.** Agent 1 and 3 lean toward magic links (simpler). Agent 2 and 4 lean toward managed providers (more secure out-of-the-box). The deciding factor: does the product need enterprise SSO (SAML/OIDC for customer organizations)? If yes, managed provider. If no, magic links + session cookies.

### Surprising finding:
- Agent 1's assumption challenge on JWTs — for a new product, simple session cookies with server-side sessions may be better than JWTs. JWTs introduce complexity (revocation, refresh rotation) that only pays off at scale.

## Recommendation

**For an early SaaS product:**

1. **Authentication:** Managed provider (Clerk or Auth0) for identity. Handles passwords, SSO, MFA, breach detection. Switch to passwordless/passkeys as adoption grows.
2. **Authorization:** Custom, in the monolith. Start with is_admin boolean. Add RBAC when there's a third role. Use default-deny middleware.
3. **Sessions:** Let the managed provider handle session tokens. Short-lived access tokens (15 min) + refresh tokens.
4. **Step-up auth:** MFA required for: changing email, deleting account, accessing billing, inviting users.
5. **Revisit when:** You need enterprise SSO (SAML), fine-grained permissions (ABAC), or multi-tenant organization hierarchy.

**Open questions:**
- Does the product need enterprise SSO in the first year? This is the biggest design driver.
- What's the budget for a managed auth provider? ($0.05-0.10/MAU adds up.)
- Does the team have security expertise for custom auth? If not, managed provider is non-negotiable.
