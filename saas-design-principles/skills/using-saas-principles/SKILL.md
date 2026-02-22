---
name: using-saas-principles
description: This skill should be used when the user asks "which SaaS design skill should I use", "show me all design principles", "help me pick a design pattern", or at the start of any SaaS-related conversation. Provides the index of all twelve principle skills and ensures the right ones are invoked before any SaaS UI work begins.
version: 1.0.0
---

<IMPORTANT>
When working on any SaaS UI pattern — forms, tables, navigation, authentication, onboarding, notifications, errors, permissions, settings, theming, or responsive layouts — invoke the relevant saas-design-principles skill BEFORE writing or reviewing code.

These are not suggestions. They are research-backed, opinionated principles drawn from Linear, Stripe, Intercom, Shopify Polaris, GitHub Primer, IBM Carbon, Atlassian, and decades of Nielsen Norman Group research.
</IMPORTANT>

## How to Access Skills

Use the `Skill` tool to invoke any skill by name. When invoked, follow the skill's guidance directly.

## Available Skills

| Skill | Triggers On |
|-------|-------------|
| `saas-design-principles:speed-is-the-feature` | Performance, loading states, optimistic UI, skeleton screens, perceived speed |
| `saas-design-principles:saas-navigation` | Sidebar nav, command palette (Cmd+K), breadcrumbs, org/workspace switching |
| `saas-design-principles:progressive-disclosure` | Onboarding flows, empty states, checklists, feature revelation, signup |
| `saas-design-principles:form-design` | Form validation, auto-save vs explicit save, inline errors, multi-step wizards |
| `saas-design-principles:notification-hierarchy` | Toasts, banners, modals, inline messages, alert fatigue, feedback |
| `saas-design-principles:error-handling` | Validation errors, 403s, session expiry, network errors, conflict resolution |
| `saas-design-principles:data-tables` | Tables, pagination, column alignment, bulk actions, sorting, filtering |
| `saas-design-principles:permissions-and-settings` | RBAC, invitations, role management, account vs workspace settings |
| `saas-design-principles:authentication` | Login, MFA, magic links, SSO, session management, GDPR |
| `saas-design-principles:accessibility` | WCAG 2.2 AA, keyboard navigation, focus management, SPA a11y, ARIA |
| `saas-design-principles:design-tokens` | Theming, dark mode, CSS variables, token architecture, color naming |
| `saas-design-principles:responsive-design` | Breakpoints, mobile layouts, table-to-card conversion, touch targets |

## When to Invoke Skills

Invoke a skill when there is even a small chance the work touches one of these areas:

- Building or modifying any UI component listed above
- Reviewing existing SaaS UI for quality
- Making architectural decisions about layout, navigation, or state management
- Designing new features that involve user interaction

## The Three Meta-Principles

All twelve principles rest on three foundations:

1. **Utility before Usability before Beauty** — A feature must work correctly before it works smoothly, and smoothly before it delights. Sequential dependencies, not tradeoffs.

2. **Purpose-built over flexible** — Opinionated defaults that work for 80% of users beat infinitely configurable systems that work for nobody without setup.

3. **Ship or it doesn't exist** — Every principle only matters if it reaches real users and improves measurable outcomes.
