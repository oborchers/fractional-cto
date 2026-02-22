# saas-design-principles

A Claude Code plugin that codifies the holy principles of SaaS design — research-backed, opinionated guidance drawn from Linear, Stripe, Intercom, Shopify Polaris, GitHub Primer, IBM Carbon, Atlassian, and decades of Nielsen Norman Group research.

## What It Does

When Claude is working on SaaS UI — forms, tables, navigation, authentication, onboarding, errors, or any of the patterns below — the relevant principle skill activates automatically and guides the work with specific, actionable rules and review checklists.

This plugin provides **principles and examples, not boilerplate.** It tells Claude *what* to build and *why*, with code patterns in React, Vue, and Svelte showing *how*.

## The 12 Principles

| # | Principle | Skill | What It Covers |
|---|-----------|-------|----------------|
| I | Speed is the feature | `speed-is-the-feature` | Optimistic UI, skeleton screens, performance budgets, code splitting |
| II | Don't make users think | `saas-navigation` | Sidebar nav, Cmd+K command palette, breadcrumbs, org switching |
| III | Reveal complexity progressively | `progressive-disclosure` | Onboarding, empty states, checklists, signup optimization |
| IV | Forms as conversations | `form-design` | Inline validation, auto-save vs explicit save, error messages |
| V | Match urgency to interruption | `notification-hierarchy` | Toasts, banners, modals, inline messages, alert fatigue |
| VI | The full taxonomy of errors | `error-handling` | Validation, 403s, session expiry, offline, conflicts |
| VII | Tables win or lose SaaS | `data-tables` | Pagination, alignment, bulk actions, column defaults |
| VIII | Permissions felt, not fought | `permissions-and-settings` | RBAC, invitations, account vs workspace settings |
| IX | Invisible authentication | `authentication` | Magic links, MFA, OTP, session management, GDPR |
| X | Accessibility is law | `accessibility` | WCAG 2.2 AA, keyboard nav, focus management, SPA a11y |
| XI | Tokens make theming trivial | `design-tokens` | Three-tier tokens, dark mode, CSS custom properties |
| XII | Responsive means sacrifice | `responsive-design` | Breakpoints, table-to-card, touch targets, mobile nav |

## Installation

### Claude Code (via vibe-cto Marketplace)

```bash
# Register the marketplace (once)
/plugin marketplace add oborchers/vibe-cto

# Install the plugin
/plugin install saas-design-principles@vibe-cto
```

### Local Development

```bash
# Test directly with plugin-dir flag
claude --plugin-dir /path/to/vibe-cto/saas-design-principles
```

## Components

### Skills (13)

One meta-skill (`using-saas-principles`) that provides the index and 12 principle skills that activate automatically when Claude detects relevant SaaS patterns.

Each skill includes:
- Research-backed principles with cited sources
- Actionable review checklists
- Code examples in React, Vue, and Svelte (where applicable)

### Command (1)

- `/saas-review` — Review the current code against all relevant SaaS design principles

### Agent (1)

- `saas-design-reviewer` — Comprehensive design audit agent that evaluates code against all 12 principles with severity-rated findings

### Hook (1)

- `SessionStart` — Injects the skill index at the start of every session so Claude knows the principles are available

## The Three Meta-Principles

All twelve principles rest on three foundations:

1. **Utility → Usability → Beauty** — Sequential dependencies, not tradeoffs
2. **Purpose-built over flexible** — Opinionated defaults for 80% of users
3. **Ship or it doesn't exist** — Principles only matter if they reach real users

## License

MIT
