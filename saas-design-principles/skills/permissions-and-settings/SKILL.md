---
name: permissions-and-settings
description: This skill should be used when the user is building or reviewing role-based access control (RBAC), invitation flows, settings pages, admin panels, or feature gating. Covers the hide/disable/reduce strategy for restricted features, RBAC progression, account vs workspace settings separation, and invitation UX.
version: 1.0.0
---

# Permissions Should Be Felt, Not Fought

Every user should see exactly what they need to get their job done — no more, no less.

## Three Strategies for Restricted Features

All three are needed — choose per feature:

| Strategy | When to Use | Example |
|----------|-------------|---------|
| **Hide completely** | Entire section irrelevant to the role | Admin-only billing section hidden from members |
| **Show but disable** (with tooltip) | User should know the feature exists — upsell path | Plan-gated feature with "Upgrade to Pro" tooltip |
| **Show with reduced functionality** | Read access appropriate, write access isn't | View-only dashboard for member role |

## RBAC Progression

Follow WorkOS's practical progression, building incrementally:

1. **Simple admin/member differentiation** — start here
2. **Fine-grained permissions per feature** — define what each role can do
3. **Roll-up roles** — combine permissions into named roles
4. **Resource groups** — scope roles to orgs, teams, projects
5. **Custom roles** — let admins define their own
6. **IdP attribute mapping** — for enterprise SSO

**Key UX guardrail:** Expose permission bundles that map to real product concepts, not 40 atomic checkboxes. Enforce limits like "max 20 custom roles per tenant" to prevent configuration chaos.

## Invitation Flows

Three mechanisms are needed:

### 1. Email Invite (Default)
Admin enters addresses, sets access level before sending.

### 2. Link Invite (Bulk)
For bulk invitations. Support expiration dates and domain restrictions.

### 3. Domain-Based Provisioning (Enterprise SSO)
Accounts auto-created on first login.

**Invitation email must include:**
- Who invited them
- What the product does
- Who else from their team is already using it

**Differentiate onboarding for invited users** — they get a shorter, different flow because context already exists.

## Settings Architecture

Clean split between two concerns:

| Settings Type | Belongs To | Examples |
|--------------|-----------|----------|
| **Account settings** | The person | Profile, password, notifications, appearance |
| **Workspace settings** | The organization | Members, billing, integrations, security policies |

**Never mix them.**

**Layout:** Sidebar navigation + content area. This is the standard used by GitHub, Linear, and Vercel.

**Avoid tab-based settings** when there are more than 5–6 categories — tabs don't scale.

**Two-column layout (Shopify Polaris pattern):**
- Left column: scannable labels and descriptions
- Right column: grouped settings in cards

## Review Checklist

When reviewing or building permissions and settings:

- [ ] Restricted features use the correct strategy (hide / disable with tooltip / reduced functionality)
- [ ] RBAC uses permission bundles, not atomic checkboxes
- [ ] Custom roles have a reasonable limit per tenant
- [ ] Email, link, and domain-based invitation flows all supported
- [ ] Invitation emails include who invited, what the product does, and who else is using it
- [ ] Invited users get a shorter, differentiated onboarding
- [ ] Account settings (person) and workspace settings (org) are fully separated
- [ ] Settings use sidebar navigation, not tabs (if >5–6 categories)
- [ ] Two-column layout: labels/descriptions on left, controls on right
