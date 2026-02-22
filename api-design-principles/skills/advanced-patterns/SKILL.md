---
name: advanced-patterns
description: "This skill should be used when the user is implementing bulk or batch API operations, choosing between REST and GraphQL or gRPC, designing real-time APIs with SSE or WebSockets, implementing multi-tenant API isolation, setting up API gateways, or applying CQRS and event sourcing patterns. Covers batch operations, protocol comparison, real-time patterns, multi-tenancy, and API gateway selection."
version: 1.0.0
---

# Know When to Break the REST Rules

Standard REST with JSON covers most API needs. But some problems -- bulk data import, real-time streaming, multi-tenant isolation, high read:write asymmetry -- demand patterns that go beyond basic CRUD. Reach for these when standard REST creates friction, not before.

## Bulk and Batch Operations

When clients need to create, update, or delete many resources at once, individual requests are wasteful. Batch endpoints eliminate the round-trip overhead.

**Use the simple batch pattern for homogeneous operations:**

Send an array of resources to a dedicated `/batch` endpoint. Cap batch size at 100 items per request to keep response times predictable and memory usage bounded. Return per-item status with an index for correlation -- never silently drop failures.

**Design for partial success, not all-or-nothing:**

| Approach | When to Use | HTTP Status |
|----------|-------------|-------------|
| **Atomic (all-or-nothing)** | Financial transactions, consistency-critical operations | `200` or `400/422` (all rolled back) |
| **Partial success** | Import operations, bulk updates with independent items | `200` with per-item status |
| **Async processing** | Large batches (1,000+ items) | `202 Accepted`, poll for results |

Every batch response must include a summary object with `total`, `succeeded`, and `failed` counts. For failed items, return the original index and a structured error so the caller knows exactly what to retry.

**Switch to async for large batches:**

Return `202 Accepted` with a `Location` header pointing to a status resource. The client polls that resource for progress updates. Include `estimated_completion` when possible. Provide a separate errors endpoint for downloading failures as JSON or CSV. This is the pattern Shopify uses for bulk mutations and Stripe uses for bulk payouts.

## REST vs GraphQL vs gRPC vs tRPC

Pick the protocol that matches the consumer, not the one that sounds most modern.

| Aspect | REST | GraphQL | gRPC | tRPC |
|--------|------|---------|------|------|
| **Latency** | Good | Good | Excellent (binary, HTTP/2) | Good |
| **Caching** | Excellent (HTTP-native) | Hard (POST, single endpoint) | Custom solution required | Custom solution required |
| **Tooling** | Mature, abundant | Strong (Apollo, Relay) | Strong (protoc, buf) | TypeScript-native |
| **Learning curve** | Low | Medium | Medium-High | Low (TypeScript only) |
| **Browser support** | Native | Native (fetch/POST) | Requires grpc-web proxy | Native |
| **Type safety** | Via codegen from OpenAPI | Via codegen from SDL | Native (protobuf) | Native (TS inference) |
| **Best for** | Public APIs, broad ecosystem | Flexible frontend data needs | Service-to-service | Full-stack TS monorepos |

**Decision framework:**

- **Public API consumed by third parties?** REST. Broadest compatibility, native HTTP caching, well-understood by every developer.
- **Frontend needs flexible data shapes across mobile, web, and admin?** GraphQL. Solves over-fetching and under-fetching in a single query.
- **Internal microservice-to-microservice where latency matters?** gRPC. Binary encoding is 5-10x smaller than JSON, and HTTP/2 multiplexing keeps connections efficient.
- **Full-stack TypeScript monorepo?** tRPC. Zero codegen, end-to-end type safety, fastest iteration speed.
- **Unsure?** Start with REST. You can always add GraphQL or gRPC alongside it later. GitHub, Shopify, and Google all run multiple protocols in parallel.

## Real-Time Patterns

Three mechanisms exist for pushing data to clients. Each solves a different problem.

| Pattern | Direction | Connection | Best For |
|---------|-----------|------------|----------|
| **Webhooks** | Server to server | No persistent connection | Background integrations, event notifications between services |
| **SSE (Server-Sent Events)** | Server to client (one-way) | Persistent HTTP | Browser streaming, notifications, AI token streaming |
| **WebSockets** | Bidirectional | Persistent TCP | Chat, collaborative editing, gaming, anything requiring client-to-server messages |

**Start with webhooks for server-to-server communication.** They work through firewalls, require no persistent connections, and are the most widely supported pattern. Stripe, GitHub, and Twilio all use webhooks as their primary real-time mechanism.

**Use SSE for browser-facing streaming.** SSE is simpler than WebSockets, works through proxies and CDNs, and automatically reconnects on disconnect. The browser's `EventSource` API handles reconnection with `Last-Event-ID` for you. OpenAI and Anthropic both use SSE for streaming LLM responses.

**Reserve WebSockets for true bidirectional needs.** If the client only receives data, SSE is simpler and more robust. WebSockets add complexity: you need heartbeat/ping-pong logic, reconnection handling, message serialization, and authentication on the connection handshake. Use them only when the client must send frequent messages back to the server.

## API Gateways

An API gateway sits between clients and backend services, handling cross-cutting concerns: authentication, rate limiting, routing, monitoring, and CORS. It is the single entry point for all API traffic.

**When to use a gateway:**

- Multiple backend services need unified auth, rate limiting, and logging
- You want a single domain for clients while routing to different services internally
- You need protocol translation (REST to gRPC)
- You want centralized request/response transformation

**When to skip the gateway:**

- Single monolithic backend -- a reverse proxy like Nginx suffices
- Internal-only API with no external consumers
- Every hop adds latency; if sub-millisecond matters, go direct

| Gateway | Type | Best For |
|---------|------|----------|
| **Kong** | OSS + Enterprise | Flexible, multi-cloud, rich plugin ecosystem (Lua, Go, Python, JS) |
| **AWS API Gateway** | Managed | AWS-native apps, Lambda authorizers, tight CloudWatch integration |
| **Cloudflare API Shield** | Managed | Edge-first deployments, DDoS protection, Workers for custom logic |
| **Nginx / OpenResty** | OSS | High-performance reverse proxy, custom Lua scripting |
| **Envoy** | OSS (CNCF) | Service mesh sidecar, gRPC-native, Kubernetes environments |
| **Traefik** | OSS + Enterprise | Kubernetes-native, automatic service discovery via Docker and etcd |

**Use the Backend-for-Frontend (BFF) pattern** when different clients need different gateway behavior. A mobile BFF returns smaller payloads, a web BFF includes richer metadata, and a partner BFF uses a different auth scheme. Each gets its own gateway layer tailored to its needs.

## Multi-Tenancy

Every SaaS API must isolate tenant data. The two decisions: how to identify the tenant, and how to isolate their data.

**Tenant identification -- use the API key or JWT claim:**

The tenant should be determined automatically from the authentication credential. This is what Stripe (API key maps to account), Clerk (JWT contains `org_id`), and WorkOS all do. Avoid requiring a separate `X-Tenant-Id` header or query parameter -- it is easy to forget, hard to audit, and creates a vector for tenant impersonation.

**Data isolation -- start with shared schema plus row-level security:**

| Strategy | Cost | Isolation | Tenant Count | Best For |
|----------|------|-----------|--------------|----------|
| **Shared schema + RLS** | Lowest | App-enforced + DB safety net | Unlimited | SaaS startups, small tenants |
| **Schema-per-tenant** | Medium | Schema-level separation | Hundreds | Moderate isolation needs |
| **Database-per-tenant** | Highest | Full database isolation | Tens to low hundreds | Enterprise, regulated industries, data residency |

Start with shared schema. Add a `tenant_id` column to every table. Enable PostgreSQL Row-Level Security as a safety net so that even if application code has a bug, the database enforces tenant boundaries. Move to schema-per-tenant or database-per-tenant only when compliance, performance isolation, or data residency requirements demand it.

**Make resource IDs globally unique, not just unique per tenant.** Auto-incrementing integers scoped to a tenant create confusion when resources cross tenant boundaries (marketplace scenarios, admin tools, migrations). Prefixed IDs like `ord_NffrFeUfNV2Hib` are globally unique by nature.

**Rate-limit per tenant, not globally.** One noisy tenant must never degrade service for others.

## CQRS: Separate Read and Write Models

CQRS (Command Query Responsibility Segregation) splits your API into commands (writes) and queries (reads), each with its own optimized model. Traditional CRUD uses a single model for both.

**When CQRS earns its complexity:**

- Read and write patterns diverge significantly (e.g., 100:1 read:write ratio)
- Read models need different shapes than write models (dashboards, analytics, search)
- You need independent scaling of read and write workloads
- Write operations involve complex domain logic that does not map to simple CRUD

**When CQRS is overkill:**

- Simple CRUD applications with balanced read/write ratios
- Small teams that cannot absorb the operational complexity of eventual consistency
- Early-stage products where the data model is still evolving rapidly

In a CQRS API, commands are intent-revealing (`POST /commands/place-order`) rather than generic (`POST /orders`). Queries return purpose-built read models (`GET /queries/order-summary/:id`) optimized for their specific use case. The trade-off is eventual consistency between write and read sides -- the read model updates asynchronously after a command succeeds.

## Event Sourcing

Event sourcing stores state as an append-only log of events rather than overwriting current state. Each event records what happened: `order.placed`, `order.shipped`, `order.cancelled`. Current state is derived by replaying events.

**When event sourcing is worth it:**

- Audit trail is a hard requirement (finance, healthcare, compliance)
- You need to reconstruct past states ("what did this order look like last Tuesday?")
- Temporal queries matter ("how many orders were in 'pending' status on January 15th?")
- You are already using CQRS and events are the natural bridge between write and read models

**When event sourcing is overkill:**

- Standard CRUD applications where current state is sufficient
- Teams without experience in event-driven architectures
- When you only need an audit log -- a simple `changes` table is far simpler than full event sourcing

Expose event history through the API with a `GET /v1/orders/:id/events` endpoint for audit and debugging. But serve current state from a read-optimized projection, not by replaying events on every request.

## Design-First with OpenAPI

Write the OpenAPI spec before writing code. For public APIs, the contract is the product -- designing it after implementation leads to inconsistent, hard-to-use interfaces.

**The design-first workflow:**

1. Write the OpenAPI 3.1 spec (YAML or JSON)
2. Lint with Spectral to enforce naming conventions, required fields, and consistent error formats
3. Generate server stubs, client SDKs, mock servers, and documentation from the spec
4. Implement endpoints against the generated interfaces
5. Run contract tests (Schemathesis) to verify the implementation matches the spec

**Use design-first for public APIs** where the contract matters most. Use code-first (generate spec from annotations) for internal APIs where iteration speed matters more and spec drift is less costly.

**Key tools:** Redocly or Scalar for documentation, Spectral for linting, openapi-generator or Kiota for SDK generation, Prism for mock servers, Schemathesis for property-based testing.

## Review Checklist

When reviewing or building advanced API patterns:

- [ ] Batch endpoints cap at 100 items per request with per-item status in the response
- [ ] Large batches (1,000+ items) use `202 Accepted` with async polling, not synchronous processing
- [ ] Protocol choice matches the consumer: REST for public, GraphQL for flexible frontends, gRPC for internal services
- [ ] Real-time pattern matches the use case: webhooks for server-to-server, SSE for browser streaming, WebSockets only for bidirectional
- [ ] API gateway handles cross-cutting concerns (auth, rate limiting, monitoring) so individual services do not
- [ ] Tenant is identified from the API key or JWT claim, not from a separate header or query parameter
- [ ] Every table has a `tenant_id` column with Row-Level Security enabled as a safety net
- [ ] Rate limits are enforced per tenant, not globally
- [ ] Resource IDs are globally unique across tenants (prefixed IDs, not auto-incrementing integers)
- [ ] CQRS is only applied when read/write patterns genuinely diverge -- not as a default architecture
- [ ] Event sourcing is reserved for audit-critical domains, not used where a simple changelog table suffices
- [ ] Public APIs use design-first OpenAPI with linting and contract testing in CI
